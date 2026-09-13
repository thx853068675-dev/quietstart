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

  async ensure(shell: WorkerShell, progress: (message: string) => void): Promise<void> {
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
    if (await this.installed(shell, manifest) && remembered === manifest.sha256) {
      progress('工作模块已就绪，正在启动…'); return;
    }
    const bytes = await this.resources.getRawFileContent('quietstart-worker.hap');
    const digest = cryptoFramework.createMd('SHA256'); await digest.update({ data: bytes });
    let hash = '';
    for (const byte of (await digest.digest()).data) { hash += byte.toString(16).padStart(2, '0'); }
    if (bytes.length !== manifest.size || hash !== manifest.sha256) { throw new Error('内置工作模块校验失败，未执行安装。'); }
    const target = '/data/local/tmp/quietstart-worker-' + hash.slice(0, 12);
    // Stable private staging path permits retry after interruption; truncate before transfer.
    await shell.execute('umask 077; mkdir -p ' + target + ' && : > ' + target + '/worker.b64');
    try {
      const encoded = new util.Base64Helper().encodeToStringSync(bytes);
      for (let i = 0; i < encoded.length; i += 16384) {
        await shell.execute("printf '%s' '" + encoded.slice(i, i + 16384) + "' >> " + target + '/worker.b64');
        progress('正在准备工作模块 ' + Math.min(100, Math.round((i + 16384) / encoded.length * 100)) + '%');
      }
      await shell.execute('base64 -d ' + target + '/worker.b64 > ' + target + '/worker.hap');
      const checked = await shell.execute('sha256sum ' + target + '/worker.hap');
      if (checked.split(/\s+/)[0] !== hash) { throw new Error('工作模块传输不完整，请重新连接。'); }
      progress('正在安装工作模块，请稍候…');
      const output = await shell.execute('bm install -p ' + target + '/worker.hap');
      if (!/install bundle successfully/i.test(output) || /fail|error/i.test(output)) {
        throw new Error('工作模块安装失败：' + output.slice(-500));
      }
      if (!await this.installed(shell, manifest)) { throw new Error('系统未确认工作模块版本，请重新连接。'); }
      const file = fs.openSync(receipt + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, hash); } finally { fs.closeSync(file); }
      fs.renameSync(receipt + '.tmp', receipt);
      progress('工作模块已安装，正在启动…');
    } finally {
      await shell.execute('rm -f ' + target + '/worker.b64 ' + target + '/worker.hap; rmdir ' + target).catch(() => {});
    }
  }
}
