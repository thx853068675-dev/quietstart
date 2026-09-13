"""Failure and integrity checks for the precompiled-package re-signing workflow."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('resign', Path(__file__).parents[1] / 'tools/resign-hap.py')
resign = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resign)


def zip_bytes(files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as z:
        for name, content in files.items():
            z.writestr(name, content)
    return output.getvalue()


def fixture():
    def module(name):
        return json.dumps({'app': {'bundleName': resign.BUNDLE, 'versionCode': 94200, 'minAPIVersion': 24},
                           'module': {'name': name}}).encode()
    worker = zip_bytes({'module.json': module('entry_test'), 'ets/modules.abc': b'compiled-worker' * 100})
    manifest = {'bundleName': resign.BUNDLE, 'moduleName': 'entry_test', 'versionCode': 94200,
                'sha256': hashlib.sha256(worker).hexdigest(), 'size': len(worker)}
    return zip_bytes({'module.json': module('entry'), 'ets/modules.abc': b'compiled-main',
                      resign.WORKER: worker, resign.MANIFEST: json.dumps(manifest).encode()})


class FakeSigner:
    def __init__(self, fail_at=None, corrupt=False):
        self.events = []
        self.fail_at = fail_at
        self.corrupt = corrupt

    def verify(self, source, directory, label):
        self.events.append(label)
        if label == self.fail_at:
            raise ValueError('test-only verification failure')

    def sign(self, source, target, minimum):
        self.events.append(source.name)
        target.write_bytes(source.read_bytes() + b'mock-signature')
        if self.corrupt:
            resign.repack(source.read_bytes(), target, {'ets/modules.abc': b'changed-code'})


class ResignTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.source = self.directory / 'original.hap'
        self.source.write_bytes(fixture())
        self.output = self.directory / 'result.hap'

    def test_replaces_worker_and_manifest_preserving_original_and_code(self):
        original = self.source.read_bytes()
        signer = FakeSigner()
        resign.resign(self.source, self.output, signer)
        self.assertEqual(self.source.read_bytes(), original)
        _, _, before, _ = resign.validate(original)
        _, _, after, worker = resign.validate(self.output.read_bytes())
        self.assertNotEqual(before['sha256'], after['sha256'])
        self.assertEqual(after['sha256'], hashlib.sha256(worker).hexdigest())
        self.assertEqual(signer.events, ['input', 'input-worker', 'worker-unsigned.hap', 'worker', 'main-unsigned.hap', 'main'])
        self.assertEqual(resign.archive(original)[1]['ets/modules.abc'], resign.archive(self.output.read_bytes())[1]['ets/modules.abc'])

    def test_failure_does_not_publish_partial_output_or_leave_temp_directory(self):
        for stage in ['input', 'input-worker', 'worker', 'main']:
            with self.assertRaises(ValueError):
                resign.resign(self.source, self.output, FakeSigner(fail_at=stage))
            self.assertFalse(self.output.exists())
            self.assertEqual(list(self.directory.iterdir()), [self.source])

    def test_refuses_code_changes_by_signer(self):
        with self.assertRaisesRegex(ValueError, '非预期变化'):
            resign.resign(self.source, self.output, FakeSigner(corrupt=True))
        self.assertFalse(self.output.exists())

    def test_refuses_existing_output_and_original_as_output(self):
        self.output.write_bytes(b'keep')
        for target in (self.output, self.source):
            with self.assertRaises(ValueError):
                resign.resign(self.source, target, FakeSigner())
        self.assertEqual(self.output.read_bytes(), b'keep')

    def test_rejects_stale_manifest_before_signing(self):
        resign.repack(self.source.read_bytes(), self.output, {resign.WORKER: b'broken'})
        with self.assertRaises((ValueError, zipfile.BadZipFile)):
            resign.validate(self.output.read_bytes())

    def test_does_not_overwrite_file_created_during_signing(self):
        outer = self
        class RaceSigner(FakeSigner):
            def verify(self, source, directory, label):
                super().verify(source, directory, label)
                if label == 'main':
                    outer.output.write_bytes(b'other-process-output')
        with self.assertRaises(FileExistsError):
            resign.resign(self.source, self.output, RaceSigner())
        self.assertEqual(self.output.read_bytes(), b'other-process-output')

    def test_rejects_duplicate_zip_names(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(self.source, 'a') as z:
                z.writestr('module.json', '{}')
        with self.assertRaisesRegex(ValueError, '重复文件名'):
            resign.validate(self.source.read_bytes())


if __name__ == '__main__':
    unittest.main()
