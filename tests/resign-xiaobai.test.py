"""Check unattended signing interaction without exposing temporary passwords."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import unittest

spec = importlib.util.spec_from_file_location('xiaobai_resign',
    Path(__file__).parents[1] / 'tools/resign-xiaobai-macos.py')
xiaobai = importlib.util.module_from_spec(spec)
spec.loader.exec_module(xiaobai)


class PasswordInteractionTests(unittest.TestCase):
    def test_two_prompts_automated_without_logging_password(self):
        program = '''
import getpass
a = getpass.getpass('Enter KeystorePwd:')
b = getpass.getpass('Enter KeyPwd:')
raise SystemExit(0 if a == b and len(a) > 12 else 1)
'''
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            xiaobai.sign_with_temporary_password([sys.executable, '-c', program], b'test-only-ephemeral')
        self.assertNotIn('test-only-ephemeral', captured.getvalue())

    def test_failed_signer_stops(self):
        with self.assertRaisesRegex(ValueError, '签名工具失败'):
            xiaobai.sign_with_temporary_password([sys.executable, '-c', 'raise SystemExit(1)'], b'test-only')

    def test_success_exit_without_expected_prompts_is_rejected(self):
        with self.assertRaisesRegex(ValueError, '签名工具失败'):
            xiaobai.sign_with_temporary_password([sys.executable, '-c', 'pass'], b'test-only')


if __name__ == '__main__':
    unittest.main()
