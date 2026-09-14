import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkerShell } from './LocalActivation';

class WorkerManifest {
  bundleName: string = '';
  moduleName: string = '';
  versionCode: number = 0;
  sha256: string = '';
  size: number = 0;
}
class InstalledModule { moduleName: string = ''; versionCode: number = 0; }
class InstalledBundle { hapModuleInfos: InstalledModule[] = []; }

// Only the signed module embedded by our build is accepted; no URL or arbitrary file input.
export class WorkerInstaller {
  private resources: resourceManager.ResourceManager;
  private directory: string;
  constructor(resources: resourceManager.ResourceManager, directory: string) { this.resources = resources; this.directory = directory; }

  private async installed(shell: WorkerShell, manifest: WorkerManifest): Promise<boolean> {
    const output = await shell.execute('bm dump -n com.tonghongxiang.quietstart');
    const start = output.indexOf('{');
    if (start < 0) { throw new Error('无法读取轻启安装信息，请重新连接。'); }
    const bundle = JSON.parse(output.slice(start)) as InstalledBundle;
    return Array.isArray(bundle.hapModuleInfos) && bundle.hapModuleInfos.some((item: InstalledModule) =>
      item.moduleName === manifest.moduleName && item.versionCode === manifest.versionCode);
  }

  private remember(hash: string): void {
    const receipt = this.directory + '/installed-worker.sha256';
    const file = fs.openSync(receipt + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, hash); } finally { fs.closeSync(file); }
    fs.renameSync(receipt + '.tmp', receipt);
  }

  async ensure(shell: WorkerShell, progress: (message: string) => void, resumeHash: string = ''): Promise<boolean> {
    let manifest: WorkerManifest;
    try {
      manifest = JSON.parse(new util.TextDecoder('utf-8').decodeToString(
        await this.resources.getRawFileContent('quietstart-worker.json'))) as WorkerManifest;
    } catch (_) { throw new Error('安装包缺少工作模块，请安装完整的轻启单包版本。'); }
    if (manifest.bundleName !== 'com.tonghongxiang.quietstart' || manifest.moduleName !== 'entry_test' ||
      !Number.isInteger(manifest.versionCode) || manifest.versionCode <= 0 || !/^[a-f0-9]{64}$/.test(manifest.sha256) ||
      !Number.isInteger(manifest.size) || manifest.size < 1024 || manifest.size > 16777216) {
      throw new Error('内置工作模块信息无效，请重新安装轻启。');
    }
    const receipt = this.directory + '/installed-worker.sha256';
    let remembered = '';
    try { remembered = fs.readTextSync(receipt); } catch (_) {}
    const target = '/data/local/tmp/quietstart-worker-' + manifest.sha256.slice(0, 12);
    const installed = await this.installed(shell, manifest);
    if (installed && remembered === manifest.sha256) {
      progress('工作模块已就绪，正在启动…'); return true;
    }
    const completed = await shell.execute('cat ' + target + '/installed.sha256 2>/dev/null || true');
    if (installed && completed.trim() === manifest.sha256) {
      this.remember(manifest.sha256);
      progress('已核验工作模块安装结果，继续连接…'); return true;
    }
    if (resumeHash) {
      if (resumeHash !== manifest.sha256) { throw new Error('安装包已更新，请重新连接以准备对应的工作模块。'); }
      const log = await shell.execute('tail -c 500 ' + target + '/install.log 2>/dev/null || true');
      throw new Error('工作模块安装未完成：' + (log.trim() || '系统安装未返回成功结果，请重试连接。'));
    }
    const bytes = await this.resources.getRawFileContent('quietstart-worker.hap');
    const digest = cryptoFramework.createMd('SHA256'); await digest.update({ data: bytes });
    let hash = '';
    for (const byte of (await digest.digest()).data) { hash += byte.toString(16).padStart(2, '0'); }
    if (bytes.length !== manifest.size || hash !== manifest.sha256) { throw new Error('内置工作模块校验失败，未执行安装。'); }
    // Stable private staging path permits retry after interruption; truncate before transfer.
    await shell.execute('umask 077; mkdir -p ' + target + ' && : > ' + target + '/worker.b64');
    let handedOff = false;
    try {
      const encoded = new util.Base64Helper().encodeToStringSync(bytes);
      for (let i = 0; i < encoded.length; i += 16384) {
        await shell.execute("printf '%s' '" + encoded.slice(i, i + 16384) + "' >> " + target + '/worker.b64');
        progress('正在准备工作模块 ' + Math.min(100, Math.round((i + 16384) / encoded.length * 100)) + '%');
      }
      await shell.execute('base64 -d ' + target + '/worker.b64 > ' + target + '/worker.hap');
      const checked = await shell.execute('sha256sum ' + target + '/worker.hap');
      if (checked.split(/\s+/)[0] !== hash) { throw new Error('工作模块传输不完整，请重新连接。'); }
      handedOff = true;
      await shell.installWorker(hash);
      return false;
    } finally {
      if (!handedOff) {
        await shell.execute('rm -f ' + target + '/worker.b64 ' + target + '/worker.hap; rmdir ' + target).catch(() => {});
      }
    }
  }
}
