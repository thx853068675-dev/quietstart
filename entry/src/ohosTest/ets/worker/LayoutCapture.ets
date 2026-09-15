import { Driver, abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LocalActivation } from '../../../main/ets/core/LocalActivation';

export const LAYOUT_READ_INTERRUPTED: number = 90057001;
class LayoutReadError extends Error { code: number = LAYOUT_READ_INTERRUPTED; }
let layoutConnection: LocalActivation | undefined;
export function closeLayoutConnection(): void { layoutConnection?.close(); layoutConnection = undefined; }

// API 26 uses the native layout API. API 24 uses the already authorized local
// HDC connection; shell output crosses the sandbox through that loopback socket.
export async function captureLayout(driver: Driver, path: string): Promise<boolean> {
  try { fs.unlinkSync(path); } catch (_) {}
  if (deviceInfo.sdkApiVersion >= 26) { return await driver.dumpLayout(path); }
  const directory = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
  if (!layoutConnection?.canReuseLayout()) { layoutConnection = new LocalActivation(directory); }
  let text = '';
  try { text = await layoutConnection.readCurrentLayout(); }
  catch (error) { closeLayoutConnection(); const problem = error as Error;
    const wrapped = new LayoutReadError(problem.message); wrapped.stack = problem.stack; throw wrapped; }
  const timing = layoutConnection.readLayoutTiming();
  hilog.info(0, 'QuietStartLayout', 'capture %{public}s', JSON.stringify(timing));
  if (!text) { throw new Error('本机布局读取失败：请确认无线调试仍开启，端口与本机连接一致'); }
  JSON.parse(text);
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd, text); } finally { fs.closeSync(file.fd); }
  return true;
}
