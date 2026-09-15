// Fault injection is available only in this isolated test build, for the current
// explicitly supplied session token. Release builds never arm or consume it.
import { bundleManager, Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { process } from '@kit.ArkTS';
import { SupervisionStore } from './SupervisionStore';

class StressRequest {
  token: string = '';
  kind: string = '';
  at: number = 0;
}
export function stressBuild(): boolean {
  try { return bundleManager.getBundleInfoForSelfSync(0).versionName === '0.9.60-test'; } catch (_) { return false; }
}
export function armSupervisionStress(directory: string, want: Want): void {
  if (!stressBuild()) { return; }
  const kind = want.parameters?.['quietstartStress'];
  const token = want.parameters?.['quietstartStressToken'];
  if (typeof kind !== 'string' || (kind !== 'exit' && kind !== 'stall-rpc' && kind !== 'throw-error') || typeof token !== 'string' || !new SupervisionStore(directory).allows(token)) { return; }
  const request = new StressRequest(); request.kind = kind; request.token = token; request.at = Date.now() + 4000;
  const path = directory + '/supervision-stress.json';
  const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try { fs.writeSync(f.fd, JSON.stringify(request)); } finally { fs.closeSync(f.fd); }
}
export async function consumeSupervisionStress(directory: string, token: string): Promise<void> {
  let request: StressRequest;
  const path = directory + '/supervision-stress.json';
  try {
    request = JSON.parse(fs.readTextSync(path)) as StressRequest;
    if (Date.now() < request.at) { return; }
    fs.unlinkSync(path);
  } catch (_) { return; }
  if (!stressBuild() || request.token !== token || !new SupervisionStore(directory).allows(token) ||
    Date.now() - request.at > 10000) { return; }
  if (request.kind === 'throw-error') { throw new Error('QuietStart diagnostic capture probe'); }
  if (request.kind === 'exit') { process.exit(77); }
  if (request.kind === 'stall-rpc') {
    // Suspend the scanning await, not the JS heartbeat, without busy looping.
    // Even if supervision is unavailable this resolves after 70 seconds.
    await new Promise<void>((resolve) => { setTimeout(resolve, 70000); });
  }
}
