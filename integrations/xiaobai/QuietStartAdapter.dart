// Copyright QuietStart contributors. SPDX-License-Identifier: MIT
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:quietstart_signing/quietstart_signing.dart';
import 'package:hap_installer/models/SignConfig.dart';

/// Returns false only for a different bundle. A broken QuietStart package
/// throws: it must never fall back to signing only the outer HAP.
Future<bool> signQuietStart(String source, String destination,
    SignConfig config, String signerDirectory, SignProgress progress) async {
  final input = File(source);
  if (await input.length() > maxBytes) {
    throw const FormatException('安装包过大');
  }
  final bytes = await input.readAsBytes();
  if (QuietStartPackage.inspect(bytes) == null) return false;
  final work = await Directory.systemTemp.createTemp('quietstart-identity-');
  final output = File(destination);
  try {
    // Freeze one identity for both signatures even if profile reset is pressed.
    final cert = await File(config.certPath).copy(path.join(work.path, 'chain.cer'));
    final profile = await File(config.profilePath).copy(path.join(work.path, 'profile.p7b'));
    final key = await File(config.keystoreFile).copy(path.join(work.path, 'key.pem'));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', work.path]);
      await Process.run('chmod', ['600', key.path]);
    }
    final pem = await key.readAsString();
    // XiaoBai's own key is an unencrypted PEM; reject a different key type
    // instead of putting a user's password on the process command line.
    if (!pem.contains('-----BEGIN PRIVATE KEY-----') &&
        !pem.contains('-----BEGIN EC PRIVATE KEY-----') ||
        pem.contains('ENCRYPTED')) {
      throw const FormatException('请使用小白生成的 PEM 私钥配置重新签名');
    }
    if (path.equals(path.absolute(source), path.absolute(destination))) {
      throw const FormatException('不能覆盖原包');
    }
    // getOutPath is XiaoBai's generated cache output, never the original HAP.
    if (await output.exists()) await output.delete();
    await resignQuietStart(input: bytes, output: output,
      profile: await profile.readAsBytes(), progress: progress,
      sign: (input, target, minimum) async {
        final executable = path.join(signerDirectory,
            Platform.isWindows ? 'signer.exe' : 'signer');
        final process = await Process.start(executable, [
          'sign-app', '-mode', 'localSign', '-keyAlias', 'xiaobai',
          '-appCertFile', cert.path, '-profileFile', profile.path,
          '-keystoreFile', key.path,
          '-keystorePwd', 'unused-for-unencrypted-pem',
          '-keyPwd', 'unused-for-unencrypted-pem',
          '-signAlg', 'SHA256withECDSA', '-compatibleVersion', '$minimum',
          '-signCode', '1', '-inFile', input.path, '-outFile', target.path,
        ]);
        // Drain both pipes without writing signing diagnostics/private paths
        // into the app history. Some native signer failures still exit zero.
        final stdoutDone = process.stdout.drain<void>();
        final stderrDone = process.stderr.drain<void>();
        int code;
        try {
          code = await process.exitCode.timeout(const Duration(seconds: 120));
        } catch (_) {
          process.kill();
          await process.exitCode;
          rethrow;
        } finally {
          await Future.wait([stdoutDone, stderrDone]);
        }
        if (code != 0 || !await target.exists() || await target.length() < 1024) {
          throw const FormatException('签名器未生成安装包，请检查小白的证书与 Profile');
        }
        // resignQuietStart checks actual output bytes and signed Profile.
        // Native verify-app is deliberately not used: it reports success
        // even for invalid input in the upstream native signer.
      });
    return true;
  } finally {
    await work.delete(recursive: true);
  }
}
