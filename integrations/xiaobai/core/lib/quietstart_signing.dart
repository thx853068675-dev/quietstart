// Copyright QuietStart contributors. SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const workerPath = 'resources/rawfile/quietstart-worker.hap';
const manifestPath = 'resources/rawfile/quietstart-worker.json';
const bundleName = 'com.tonghongxiang.quietstart';
const maxBytes = 64 * 1024 * 1024;

typedef SignFile = Future<void> Function(File input, File output, int minimum);
typedef SignProgress = void Function(String message);

// Huawei uses zero-filled alignment padding as ZIP extra bytes. archive 3.x
// interprets even a trailing one-byte pad as a structured field and crashes.
// Normalize only the in-memory central-directory view used for decoding;
// signing/Profile checks always use the original bytes.
List<int> zipView(List<int> bytes) {
  if (bytes.length > maxBytes || bytes.length < 22) {
    throw const FormatException('无效的安装包长度');
  }
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  var end = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50 &&
        i + 22 + data.getUint16(i + 20, Endian.little) == bytes.length) {
      end = i;
      break;
    }
  }
  if (end < 0 || data.getUint32(end + 4, Endian.little) != 0) {
    throw const FormatException('不支持的 ZIP 结构');
  }
  final count = data.getUint16(end + 10, Endian.little);
  final cd = data.getUint32(end + 16, Endian.little);
  if (count > 4096 ||
      count != data.getUint16(end + 8, Endian.little) ||
      cd + data.getUint32(end + 12, Endian.little) != end) {
    throw const FormatException('安装包中央目录无效');
  }
  final directory = BytesBuilder(copy: false);
  var position = cd, total = 0;
  for (var i = 0; i < count; i++) {
    if (position + 46 > end ||
        data.getUint32(position, Endian.little) != 0x02014b50) {
      throw const FormatException('安装包目录截断');
    }
    final name = data.getUint16(position + 28, Endian.little);
    final extra = data.getUint16(position + 30, Endian.little);
    final comment = data.getUint16(position + 32, Endian.little);
    final next = position + 46 + name + extra + comment;
    total += data.getUint32(position + 24, Endian.little);
    if (next > end ||
        total > maxBytes ||
        data.getUint16(position + 8, Endian.little) & 1 != 0 ||
        data.getUint32(position + 42, Endian.little) >= cd ||
        data.getUint32(position + 20, Endian.little) == 0xffffffff) {
      throw const FormatException('安装包过大、加密或目录越界');
    }
    final header =
        Uint8List.fromList(bytes.sublist(position, position + 46 + name));
    ByteData.sublistView(header).setUint16(30, 0, Endian.little);
    directory.add(header);
    directory.add(bytes.sublist(next - comment, next));
    position = next;
  }
  if (position != end) throw const FormatException('安装包目录数量不符');
  final tail = Uint8List.fromList(bytes.sublist(end));
  ByteData.sublistView(tail).setUint32(12, directory.length, Endian.little);
  return [...bytes.take(cd), ...directory.takeBytes(), ...tail];
}

Map<String, List<int>> readHap(List<int> bytes) {
  if (bytes.length > maxBytes) throw const FormatException('安装包过大');
  final archive = ZipDecoder().decodeBytes(zipView(bytes), verify: true);
  final result = <String, List<int>>{};
  var total = 0;
  if (archive.length > 4096) throw const FormatException('安装包文件过多');
  for (final file in archive) {
    total += file.size;
    if (file.size < 0 || total > maxBytes || result.containsKey(file.name)) {
      throw const FormatException('安装包大小或重复文件校验失败');
    }
    if (file.name.startsWith('/') ||
        file.name.contains('\\') ||
        file.name.split('/').contains('..')) {
      throw const FormatException('安装包文件路径无效');
    }
    final content = List<int>.from(file.content as List<int>);
    if (content.length != file.size) throw const FormatException('文件长度不符');
    result[file.name] = content;
  }
  return result;
}

Map<String, dynamic> object(List<int>? bytes) {
  if (bytes == null) throw const FormatException('安装包缺少必要文件');
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

bool same(List<int> a, List<int> b) =>
    a.length == b.length && sha256.convert(a) == sha256.convert(b);

class QuietStartPackage {
  final Map<String, List<int>> files;
  final Map<String, dynamic> main, worker, manifest;
  QuietStartPackage._(this.files, this.main, this.worker, this.manifest);

  static QuietStartPackage? inspect(List<int> bytes) {
    final files = readHap(bytes);
    final main = object(files['module.json']);
    if (main['app']['bundleName'] != bundleName) return null;
    final manifest = object(files[manifestPath]);
    final payload = files[workerPath];
    if (payload == null ||
        payload.length < 1024 ||
        payload.length > 16777216 ||
        manifest['size'] != payload.length ||
        manifest['sha256'] != sha256.convert(payload).toString()) {
      throw const FormatException('轻启工作模块缺失或摘要不符，请重新下载完整安装包');
    }
    final inner = readHap(payload);
    final worker = object(inner['module.json']);
    if (inner.keys.any((n) =>
            n.endsWith('quietstart-worker.hap') ||
            n.endsWith('quietstart-worker.json')) ||
        main['module']['name'] != 'entry' ||
        worker['module']['name'] != 'entry_test' ||
        manifest['moduleName'] != 'entry_test' ||
        worker['app']['bundleName'] != bundleName ||
        manifest['bundleName'] != bundleName ||
        main['app']['versionCode'] != worker['app']['versionCode'] ||
        main['app']['versionCode'] != manifest['versionCode']) {
      throw const FormatException('轻启主包、工作模块的名称或版本不一致');
    }
    for (final module in [main, worker]) {
      if (module['app']['minAPIVersion'] is! int ||
          module['app']['minAPIVersion'] <= 0) {
        throw const FormatException('安装包 API 版本无效');
      }
    }
    return QuietStartPackage._(files, main, worker, manifest);
  }
}

List<int> repack(List<int> original, Map<String, List<int>> replacements) {
  final input = ZipDecoder().decodeBytes(zipView(original), verify: true);
  final output = Archive();
  for (final entry in input) {
    final bytes = replacements[entry.name];
    if (bytes == null) {
      output.addFile(entry);
    } else {
      output.addFile(ArchiveFile(entry.name, bytes.length, bytes)
        ..mode = entry.mode
        ..lastModTime = entry.lastModTime);
    }
  }
  return ZipEncoder().encode(output)!;
}

void checkPayload(List<int> original, List<int> result,
    [Map<String, List<int>> replacements = const {}]) {
  final expected = readHap(original)..addAll(replacements);
  final actual = readHap(result);
  if (expected.length != actual.length ||
      expected.entries.any((e) =>
          !actual.containsKey(e.key) || !same(e.value, actual[e.key]!))) {
    throw const FormatException('签名器意外改变了程序内容，已停止安装');
  }
}

/// Checks signing-block structure and returns the original signed Profile.
/// This is NOT a cryptographic verification of the HAP signature; final
/// certificate trust and signature validation are performed by the phone.
List<int> signedProfile(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  var eocd = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50 &&
        i + 22 + data.getUint16(i + 20, Endian.little) == bytes.length) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0 ||
      data.getUint32(eocd + 4, Endian.little) != 0 ||
      data.getUint16(eocd + 8, Endian.little) !=
          data.getUint16(eocd + 10, Endian.little)) {
    throw const FormatException('无效或不支持的 HAP ZIP 结构');
  }
  final cd = data.getUint32(eocd + 16, Endian.little);
  if (cd < 32 ||
      cd >= eocd ||
      cd + data.getUint32(eocd + 12, Endian.little) != eocd) {
    throw const FormatException('无效的 HAP 中央目录');
  }
  final footer = cd - 32;
  final count = data.getUint32(footer, Endian.little);
  final size = data.getUint64(footer + 4, Endian.little);
  if (count < 2 ||
      count > 16 ||
      size > cd ||
      size < 32 + count * 12 ||
      !same(bytes.sublist(footer + 12, footer + 28),
          ascii.encode('<hap sign block>')) ||
      data.getUint32(footer + 28, Endian.little) != 3) {
    throw const FormatException('签名器未生成有效的 HAP 签名块');
  }
  final start = cd - size;
  final blocks = <int, List<int>>{};
  final ranges = <List<int>>[];
  for (var i = 0; i < count; i++) {
    final pos = start + i * 12;
    final type = data.getUint32(pos, Endian.little);
    final length = data.getUint32(pos + 4, Endian.little);
    final offset = data.getUint32(pos + 8, Endian.little);
    if (blocks.containsKey(type) ||
        length == 0 ||
        offset < count * 12 ||
        offset + length > size - 32 ||
        ranges.any((r) => offset < r[1] && offset + length > r[0])) {
      throw const FormatException('HAP 签名块越界、重复或重叠');
    }
    ranges.add([offset, offset + length]);
    blocks[type] = bytes.sublist(start + offset, start + offset + length);
  }
  final profile = blocks[0x20000002];
  if (profile == null ||
      profile.length < 64 ||
      (blocks[0x20000000]?.length ?? 0) < 64 ||
      !blocks.containsKey(0x20000003)) {
    throw const FormatException('缺少 Profile、签名或代码签名块');
  }
  return profile;
}

Future<void> resignQuietStart(
    {required List<int> input,
    required File output,
    required List<int> profile,
    required SignFile sign,
    required SignProgress progress}) async {
  final original = List<int>.from(input);
  final package = QuietStartPackage.inspect(original);
  if (package == null) throw const FormatException('这不是轻启安装包');
  if (await output.exists()) throw const FormatException('输出已存在，请重新选择');
  final temporary = await Directory.systemTemp.createTemp('quietstart-resign-');
  try {
    final worker = package.files[workerPath]!;
    final wi = File(p.join(temporary.path, 'worker-unsigned.hap'));
    final wo = File(p.join(temporary.path, 'worker-signed.hap'));
    await wi.writeAsBytes(repack(worker, {}));
    progress('1/3 重签工作模块');
    await sign(wi, wo, package.worker['app']['minAPIVersion'] as int);
    final newWorker = await wo.readAsBytes();
    checkPayload(worker, newWorker);
    if (!same(signedProfile(newWorker), profile)) {
      throw const FormatException('工作模块未使用本次的设备授权 Profile');
    }
    final manifest = Map<String, dynamic>.from(package.manifest)
      ..['size'] = newWorker.length
      ..['sha256'] = sha256.convert(newWorker).toString();
    final replacements = <String, List<int>>{
      workerPath: newWorker,
      manifestPath: utf8
          .encode('${const JsonEncoder.withIndent('  ').convert(manifest)}\n'),
    };
    final mi = File(p.join(temporary.path, 'main-unsigned.hap'));
    final mo = File(p.join(temporary.path, 'main-signed.hap'));
    await mi.writeAsBytes(repack(original, replacements));
    progress('2/3 重签轻启主包');
    await sign(mi, mo, package.main['app']['minAPIVersion'] as int);
    final result = await mo.readAsBytes();
    progress('3/3 检查内外模块与安装内容');
    checkPayload(original, result, replacements);
    QuietStartPackage.inspect(result);
    if (!same(signedProfile(result), profile)) {
      throw const FormatException('主包与工作模块的设备授权不一致');
    }
    // Only this complete output is handed to the existing installation flow.
    await output.create(exclusive: true);
    try {
      await output.writeAsBytes(result, flush: true);
    } catch (_) {
      await output.delete();
      rethrow;
    }
  } finally {
    await temporary.delete(recursive: true);
  }
}
