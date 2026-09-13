#!/usr/bin/env python3
"""Apply QuietStart's integration to one pinned XiaoBai source checkout."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess

UPSTREAM = '24388dd86e6c3c7cab83fc27d3e6f4f9cb1b7801'
HAP_SHA = '242cd4c309333e7aa1b00ded05c89056671348034f293cf20b198b4493d5f03c'
HERE = Path(__file__).resolve().parent

def replace(file, old, new):
    text = file.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise ValueError(f'Upstream changed; refusing ambiguous patch: {file.name}')
    file.write_text(text.replace(old, new), encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--hap', type=Path, required=True)
    args = parser.parse_args()
    root = args.source.resolve()
    revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != UPSTREAM:
        raise ValueError('Unexpected XiaoBai source revision')
    if hashlib.sha256(args.hap.read_bytes()).hexdigest() != HAP_SHA:
        raise ValueError('Unexpected QuietStart HAP checksum')
    app = root / 'flutter/hap_installer'
    shutil.copytree(HERE / 'core', app / 'packages/quietstart_signing',
                    ignore=shutil.ignore_patterns('.dart_tool', 'build'), dirs_exist_ok=True)
    shutil.copyfile(HERE / 'QuietStartAdapter.dart', app / 'lib/hdc/QuietStartAdapter.dart')
    shutil.copyfile(HERE / 'selection_test.dart', app / 'test/quietstart_selection_test.dart')
    for file in [app/'pubspec.yaml', app/'plugins/native_core/pubspec.yaml']:
        replace(file, 'sdk: ^2.19.6', "sdk: '>=3.6.0 <4.0.0'")
    replace(app/'plugins/ohos_adapter/pubspec.yaml', "sdk: '>=2.19.6 <3.0.0'", "sdk: '>=3.6.0 <4.0.0'")
    replace(app/'pubspec.yaml', '\ndependencies:\n', '\ndependencies:\n  quietstart_signing:\n    path: packages/quietstart_signing\n')
    service = app/'lib/hdc/CmdService.dart'
    replace(service, "import 'dart:convert';", "import 'dart:convert';\nimport 'package:flutter/services.dart';\nimport 'QuietStartAdapter.dart';")
    replace(service, '  Future<String> getOutPath(String inPath) async {', '''  Future<String> getQuietStartSignerDir() async {
    final directory = Directory(path.join(await getTempDir(), 'quietstart-integrated-signer'));
    await directory.create(recursive: true);
    final platform = Platform.isWindows ? 'windows' : 'macos';
    final files = Platform.isWindows
      ? ['signer.exe', 'libcrypto-3-x64.dll', 'libgcc_s_seh-1.dll',
          'libstdc++-6.dll', 'libwinpthread-1.dll', 'libcjson.dll']
      : ['signer'];
    for (final name in files) {
      final data = await rootBundle.load('assets/$platform/$name');
      final file = File(path.join(directory.path, name));
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['700', path.join(directory.path, 'signer')]);
      if (result.exitCode != 0) throw const FormatException('签名器无法启动');
    }
    return directory.path;
  }

  Future<String> getOutPath(String inPath) async {''')
    replace(service, 'Future<String?> signHap(String inPath, SignConfig signConfig) async {',
            'Future<String?> signHap(String inPath, SignConfig signConfig, {void Function(String)? onProgress}) async {')
    replace(service, '    final outPath = await getOutPath(inPath);\n    var cmd = "";', '''    final outPath = await getOutPath(inPath);
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        if (await signQuietStart(inPath, outPath, signConfig, await getQuietStartSignerDir(),
            onProgress ?? (_) {})) return null;
      } on FormatException catch (e) {
        return e.message;
      } catch (_) {
        return '轻启内外模块重签失败，请检查证书、Profile 和签名器';
      }
    }
    var cmd = "";''')
    view = app/'lib/EcoViewModel.dart'
    replace(view, "import 'dart:isolate';", "import 'dart:isolate';\nimport 'package:quietstart_signing/quietstart_signing.dart' as quietstart;")
    replace(view, '  toSelectFile(BuildContext context) async {', '''  String? quietStartFileName;
  Directory? quietStartSelectionDirectory;

  selectQuietStartFile(BuildContext context, {String? selectedPath}) async {
    if (fileLoading) return;
    fileLoading = true;
    notifyListeners();
    try {
      final filePath = selectedPath ?? (await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['hap'], allowMultiple: false,
        dialogTitle: '选择要安装的轻启 HAP',
      ))?.files.single.path;
      if (filePath == null) return; // Cancelling preserves the previous selection.
      hapInfo = null;
      quietStartFileName = null;
      final previous = quietStartSelectionDirectory;
      quietStartSelectionDirectory = null;
      if (previous != null && await previous.exists()) await previous.delete(recursive: true);
      notifyListeners();
      if (path.extension(filePath).toLowerCase() != '.hap') {
        throw const FormatException('请选择包含工作模块的轻启主 HAP');
      }
      final selected = await Isolate.run(() {
        final file = File(filePath);
        if (file.lengthSync() > quietstart.maxBytes) {
          throw const FormatException('安装包过大');
        }
        final bytes = file.readAsBytesSync();
        return (package: quietstart.QuietStartPackage.inspect(bytes), bytes: bytes);
      });
      final package = selected.package;
      if (package == null) throw const FormatException('所选文件不是轻启安装包');
      quietStartSelectionDirectory = await Directory.systemTemp.createTemp('quietstart-selection-');
      final snapshot = File(path.join(quietStartSelectionDirectory!.path, path.basename(filePath)));
      await snapshot.writeAsBytes(selected.bytes, flush: true);
      await File(path.join(quietStartSelectionDirectory!.path, 'module.json'))
          .writeAsBytes(package.files['module.json']!, flush: true);
      debugPath = quietStartSelectionDirectory!.path;
      final app = package.main['app'];
      final version = app['versionName'] as String?;
      hapInfo = HapInfo(
        packageName: quietstart.bundleName,
        pathList: [snapshot.path],
        version: '${version == null || version.trim().isEmpty ? "版本名称未提供" : version}（${app["versionCode"]}）',
        deviceType: List<String>.from(package.main['module']['deviceTypes'] ?? []),
      );
      quietStartFileName = path.basename(filePath);
    } on FormatException catch (e) {
      hapInfo = null;
      quietStartFileName = null;
      toask(context, e.message);
    } catch (_) {
      hapInfo = null;
      quietStartFileName = null;
      toask(context, '无法读取安装包，请选择完整的轻启主 HAP');
    } finally {
      fileLoading = false;
      notifyListeners();
    }
  }

  toSelectFile(BuildContext context) async {''')
    replace(view, 'return await cmd.signHap(p, signConfig);', '''return await cmd.signHap(p, signConfig, onProgress: (message) {
              model.updateStep(3, (step) => step.copyWith(loading: true, error: message));
            });''')
    page = app/'lib/pages/index_page.dart'
    guide = app/'lib/pages/user_guide_page.dart'
    replace(guide, "import 'dart:io';", "import 'package:ohos_adapter/ohos_adapter.dart';")
    replace(guide, 'Platform.isOhos', 'ohosAdapter.isOhos')
    replace(page, 'AppInfoBox(name: "小白调试助手",', 'AppInfoBox(name: "小白调试助手 · 轻启整合版",')
    replace(page, '          const DebugSteps(),', '''          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('轻启维护者修改版 · 选择要安装的轻启 HAP，核对版本后开始调试。主包和工作模块会一起重签。'),
          ),
          const DebugSteps(),''')
    replace(page, 'if (model.hapInfo?.packageName == null ||', 'if (model.fileLoading || model.hapInfo?.packageName == null ||')
    replace(page, 'title: model.hapInfo?.packageName == null ? "未选择" : "包名: ${model.hapInfo?.packageName} 支持设备: ${model.hapInfo?.deviceType}",',
            'title: model.hapInfo == null ? "尚未选择轻启版本" : "轻启 ${model.hapInfo?.version ?? \"版本未知\"}",')
    replace(page, 'subTitle: "文件格式: .app,.hap,.hsp",',
            'subTitle: model.hapInfo == null ? "选择或拖入轻启主 HAP" : "${model.quietStartFileName ?? model.hapInfo?.pathList.first}\\n${model.hapInfo?.packageName}",')
    replace(page, 'model.toSelectFile(context);', 'model.selectQuietStartFile(context);')
    replace(page, 'const Text("选择")', 'Text(model.hapInfo == null ? "选择 HAP" : "更换版本")')
    replace(page, 'model.openFile(context, file.path!);', 'model.selectQuietStartFile(context, selectedPath: file.path!);')
    replace(page, 'viewmodel.openFile(context!, url);', 'viewmodel.selectQuietStartFile(context!, selectedPath: url);')
    replace(page, 'viewmodel.openFile(context!, call.arguments["path"]);', 'viewmodel.selectQuietStartFile(context!, selectedPath: call.arguments["path"]);')
    drop = app/'lib/widget/FileDropArea.dart'
    replace(drop, 'setState(() async {', 'setState(() {')
    print('Applied QuietStart integration to', app)

if __name__ == '__main__':
    main()
