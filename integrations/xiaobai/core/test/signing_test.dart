import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:quietstart_signing/quietstart_signing.dart';
import 'package:test/test.dart';

List<int> zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return ZipEncoder().encode(archive)!;
}
List<int> jsonBytes(Object o) => utf8.encode(jsonEncode(o));
Map<String, dynamic> module(String name, {String bundle = bundleName}) => {
      'app': {'bundleName': bundle, 'versionCode': 94300, 'minAPIVersion': 24},
      'module': {'name': name}
    };
List<int> fixture() {
  final random = Random(9);
  final worker = zip({
    'module.json': jsonBytes(module('entry_test')),
    'ets/modules.abc': List.generate(2048, (_) => random.nextInt(256))
  });
  return zip({
    'module.json': jsonBytes(module('entry')),
    workerPath: worker,
    manifestPath: jsonBytes({
      'moduleName': 'entry_test',
      'bundleName': bundleName,
      'versionCode': 94300,
      'size': worker.length,
      'sha256': sha256.convert(worker).toString()
    }),
    'unchanged.txt': utf8.encode('do not modify')
  });
}

// Synthetic blocks test bounds and pipeline handling, NOT real crypto signing.
List<int> syntheticSignature(List<int> unsigned, List<int> profile) {
  final data = ByteData.sublistView(Uint8List.fromList(unsigned));
  final eocd = unsigned.length - 22;
  final cd = data.getUint32(eocd + 16, Endian.little);
  final blocks = {
    0x20000000: List<int>.filled(128, 1),
    0x20000002: profile,
    0x20000003: List<int>.filled(128, 2)
  };
  final size = 36 + blocks.values.fold<int>(0, (n, b) => n + b.length) + 32;
  final signing = Uint8List(size);
  final table = ByteData.sublistView(signing);
  var offset = 36, index = 0;
  for (final entry in blocks.entries) {
    table.setUint32(index * 12, entry.key, Endian.little);
    table.setUint32(index * 12 + 4, entry.value.length, Endian.little);
    table.setUint32(index * 12 + 8, offset, Endian.little);
    signing.setRange(offset, offset + entry.value.length, entry.value);
    offset += entry.value.length;
    index++;
  }
  table.setUint32(offset, 3, Endian.little);
  table.setUint64(offset + 4, size, Endian.little);
  signing.setRange(offset + 12, offset + 28, ascii.encode('<hap sign block>'));
  table.setUint32(offset + 28, 3, Endian.little);
  final result = Uint8List.fromList(
      [...unsigned.take(cd), ...signing, ...unsigned.skip(cd)]);
  ByteData.sublistView(result)
      .setUint32(eocd + size + 16, cd + size, Endian.little);
  return result;
}

void main() {
  final profile = List<int>.filled(128, 8);
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('quietstart-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test('other bundles use the original assistant path', () {
    expect(
        QuietStartPackage.inspect(zip({
          'module.json': jsonBytes(module('entry', bundle: 'example.other'))
        })),
        isNull);
  });
  test('broken QuietStart cannot fall back to outer-only signing', () {
    expect(
        () => QuietStartPackage.inspect(
            zip({'module.json': jsonBytes(module('entry'))})),
        throwsFormatException);
    expect(
        () => QuietStartPackage.inspect(repack(fixture(), {
              workerPath: [1, 2, 3]
            })),
        throwsFormatException);
  });
  test('version conflict is rejected', () {
    final changed = module('entry');
    changed['app']['versionCode'] = 1;
    expect(
        () => QuietStartPackage.inspect(
            repack(fixture(), {'module.json': jsonBytes(changed)})),
        throwsFormatException);
  });
  test('unsigned files and fake signer success are rejected', () {
    expect(() => signedProfile(utf8.encode('verify-app success')),
        throwsFormatException);
    expect(() => signedProfile(fixture()), throwsFormatException);
  });
  test('signing block offsets and duplicate types are rejected', () {
    final bytes = Uint8List.fromList(syntheticSignature(fixture(), profile));
    final data = ByteData.sublistView(bytes);
    final cd = data.getUint32(bytes.length - 6, Endian.little);
    final size = data.getUint64(cd - 28, Endian.little);
    data.setUint32(cd - size + 8, 0xffffffff, Endian.little);
    expect(() => signedProfile(bytes), throwsFormatException);
  });
  test('both signatures and manifest update preserve payload', () async {
    final output = File('${temp.path}/result.hap');
    final order = <String>[];
    await resignQuietStart(
        input: fixture(),
        output: output,
        profile: profile,
        progress: order.add,
        sign: (input, target, api) async {
          expect(api, 24);
          await target.writeAsBytes(
              syntheticSignature(await input.readAsBytes(), profile));
        });
    final result = await output.readAsBytes();
    final package = QuietStartPackage.inspect(result)!;
    expect(signedProfile(result), profile);
    expect(signedProfile(package.files[workerPath]!), profile);
    expect(package.files['unchanged.txt'], utf8.encode('do not modify'));
    expect(order.length, 3);
  });
  test('wrong inner Profile stops before outer signing, leaves no output',
      () async {
    var calls = 0;
    final output = File('${temp.path}/result.hap');
    await expectLater(
        resignQuietStart(
            input: fixture(),
            output: output,
            profile: profile,
            progress: (_) {},
            sign: (input, target, api) async {
              calls++;
              await target.writeAsBytes(syntheticSignature(
                  await input.readAsBytes(), List.filled(128, 9)));
            }),
        throwsFormatException);
    expect(calls, 1);
    expect(await output.exists(), isFalse);
  });
  test('changing application payload is rejected', () async {
    final output = File('${temp.path}/result.hap');
    await expectLater(
        resignQuietStart(
            input: fixture(),
            output: output,
            profile: profile,
            progress: (_) {},
            sign: (input, target, api) async {
              final changed = repack(await input.readAsBytes(), {
                'ets/modules.abc': [42]
              });
              await target.writeAsBytes(syntheticSignature(changed, profile));
            }),
        throwsFormatException);
    expect(await output.exists(), isFalse);
  });
  test('existing output is never overwritten', () async {
    final output = File('${temp.path}/result.hap');
    await output.writeAsString('original');
    await expectLater(
        resignQuietStart(
            input: fixture(),
            output: output,
            profile: profile,
            progress: (_) {},
            sign: (_, __, ___) async {}),
        throwsFormatException);
    expect(await output.readAsString(), 'original');
  });
}
