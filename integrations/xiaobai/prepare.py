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
    text = file.read_text()
    if text.count(old) != 1:
        raise ValueError(f'Upstream changed; refusing ambiguous patch: {file.name}')
    file.write_text(text.replace(old, new))

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
    (app / 'assets/quietstart').mkdir(exist_ok=True)
    shutil.copyfile(args.hap, app / 'assets/quietstart/quietstart.hap')
    for file in [app/'pubspec.yaml', app/'plugins/native_core/pubspec.yaml']:
        replace(file, 'sdk: ^2.19.6', "sdk: '>=3.6.0 <4.0.0'")
    replace(app/'plugins/ohos_adapter/pubspec.yaml', "sdk: '>=2.19.6 <3.0.0'", "sdk: '>=3.6.0 <4.0.0'")
    replace(app/'pubspec.yaml', '\ndependencies:\n', '\ndependencies:\n  quietstart_signing:\n    path: packages/quietstart_signing\n')
    replace(app/'pubspec.yaml', '    - assets/store/\n', '    - assets/quietstart/\n    - assets/store/\n')
    service = app/'lib/hdc/CmdService.dart'
    replace(service, "import 'dart:convert';", "import 'dart:convert';\nimport 'QuietStartAdapter.dart';")
    replace(service, 'Future<String?> signHap(String inPath, SignConfig signConfig) async {',
            'Future<String?> signHap(String inPath, SignConfig signConfig, {void Function(String)? onProgress}) async {')
    replace(service, '    final outPath = await getOutPath(inPath);\n    var cmd = "";', '''    final outPath = await getOutPath(inPath);
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        if (await signQuietStart(inPath, outPath, signConfig, await getHdcDir(),
            onProgress ?? (_) {})) return null;
      } on FormatException catch (e) {
        return e.message;
      } catch (_) {
        return '轻启内外模块重签失败，请检查证书、Profile 和签名器';
      }
    }
    var cmd = "";''')
    view = app/'lib/EcoViewModel.dart'
    replace(view, '  toSelectFile(BuildContext context) async {', '''  selectBundledQuietStart(BuildContext context) async {
    if (fileLoading) return;
    fileLoading = true;
    notifyListeners();
    try {
      final data = await rootBundle.load('assets/quietstart/quietstart.hap');
      final file = File(path.join(await getTempDir(), 'quietstart-bundled.hap'));
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      hapInfo = await _loadApp(context, file.path);
    } catch (_) {
      toask(context, '无法读取内置轻启，请重新解压完整整合包');
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
    replace(page, 'AppInfoBox(name: "小白调试助手",', 'AppInfoBox(name: "小白调试助手 · 轻启整合版",')
    replace(page, '          const DebugSteps(),', '''          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('轻启维护者修改版 · 基于小白调试助手。登录账号、连接手机后，选择内置轻启并开始调试。主包和工作模块会一起重签。'),
          ),
          Consumer<EcoViewModel>(builder: (context, model, _) => Center(
            child: FilledButton.tonalIcon(
              onPressed: model.fileLoading ? null : () => model.selectBundledQuietStart(context),
              icon: const Icon(Icons.install_mobile),
              label: const Text('选择内置轻启 0.9.43'),
            ),
          )),
          const DebugSteps(),''')
    print('Applied QuietStart integration to', app)

if __name__ == '__main__':
    main()
