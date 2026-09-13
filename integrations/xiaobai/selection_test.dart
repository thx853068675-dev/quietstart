import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hap_installer/EcoViewModel.dart';
import 'package:hap_installer/hdc/CmdService.dart';
import 'package:quietstart_signing/quietstart_signing.dart' as q;

void main() {
  testWidgets(
      'select any matching version; reject bad replacements without stale selection',
      (tester) async {
    final source = Platform.environment['QUIETSTART_TEST_HAP'];
    expect(source, isNotNull, reason: 'Use the real bundled HAP');
    final model = EcoViewModel();
    late BuildContext context;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    await tester.runAsync(() async {
      final directory =
          await Directory.systemTemp.createTemp('quietstart-selector-test-');
      try {
        expect(model.hapInfo, isNull); // Never preselect an embedded version.
        final original = await File(source!).readAsBytes();
        final originalPackage = q.QuietStartPackage.inspect(original)!;
        final first = File('${directory.path}/renamed.hap');
        await first.writeAsBytes(original);
        await model.selectQuietStartFile(context, selectedPath: first.path);
        expect(model.hapInfo!.version,
            contains(originalPackage.main['app']['versionName']));
        expect(model.hapInfo!.version,
            contains('${originalPackage.main['app']['versionCode']}'));
        expect(model.quietStartFileName, 'renamed.hap');
        final oldSnapshot = model.hapInfo!.pathList.first;
        expect(oldSnapshot, isNot(first.path));
        await first.writeAsString('source replaced after selection');
        expect(await File(oldSnapshot).readAsBytes(), original);

        // A future version with the same supported structure needs no new assistant.
        final main = originalPackage.main;
        final worker = originalPackage.worker;
        for (final module in [main, worker]) {
          module['app']['versionName'] = '1.2.3';
          module['app']['versionCode'] = 123000;
        }
        final inner = q.repack(originalPackage.files[q.workerPath]!, {
          'module.json': utf8.encode(jsonEncode(worker)),
        });
        final manifest = originalPackage.manifest
          ..['versionCode'] = 123000
          ..['size'] = inner.length
          ..['sha256'] = sha256.convert(inner).toString();
        final future = File('${directory.path}/another-name.hap');
        await future.writeAsBytes(q.repack(original, {
          'module.json': utf8.encode(jsonEncode(main)),
          q.workerPath: inner,
          q.manifestPath: utf8.encode(jsonEncode(manifest)),
        }));
        await model.selectQuietStartFile(context, selectedPath: future.path);
        expect(model.hapInfo!.version, '1.2.3（123000）');
        expect(model.quietStartFileName, 'another-name.hap');
        final profileModule = await cmd.readModuleInfo(model.debugPath);
        expect(profileModule.app!.versionName, '1.2.3');
        expect(profileModule.app!.bundleName, q.bundleName);
        expect(await File(oldSnapshot).exists(), isFalse);

        main['app']['versionCode'] = 1;
        final broken = File('${directory.path}/broken.hap');
        await broken.writeAsBytes(q.repack(await future.readAsBytes(), {
          'module.json': utf8.encode(jsonEncode(main)),
        }));
        await model.selectQuietStartFile(context, selectedPath: broken.path);
        expect(model.hapInfo, isNull);
        expect(model.quietStartFileName, isNull);
        expect(model.fileLoading, isFalse);
      } finally {
        final snapshot = model.quietStartSelectionDirectory;
        if (snapshot != null && await snapshot.exists())
          await snapshot.delete(recursive: true);
        await directory.delete(recursive: true);
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('轻启主包、工作模块的名称或版本不一致'), findsOneWidget);
    model.dispose();
  });
}
