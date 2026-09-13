import AccessibilityExtensionAbility, { AccessibilityEvent, AccessibilityElement, Rect } from '@ohos.application.AccessibilityExtensionAbility';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalStore, Settings, ServiceStatus } from '../core/LocalStore';
import { OWN_BUNDLE, WINDOW_MS, Bounds, isSkipLabel, isSafePosition, hasCountdown } from '../core/Rules';

// These SDK APIs are deprecated since API 12. Real-device support is unverified.
export default class SkipService extends AccessibilityExtensionAbility {
  private store?: LocalStore;
  private status: ServiceStatus = new ServiceStatus();
  private activeBundle: string = '';
  private windowStarted: number = 0;
  private didAttempt: boolean = false;
  private busy: boolean = false;
  private timer: number = -1;
  private testToken: number = 0;
  private alive: boolean = false;
  private lastScan: number = 0;
  private pendingEvent: boolean = false;

  onConnect(): void {
    this.alive = true;
    this.store = new LocalStore(this.context.filesDir);
    this.status = this.store.readStatus();
    this.status.connected = true;
    this.record('无障碍扩展已连接');
    this.scan();
  }
  onDisconnect(): void {
    this.alive = false;
    this.stopTimer();
    this.status.connected = false;
    this.record('无障碍扩展已断开');
  }
  onAccessibilityEvent(_event: AccessibilityEvent): void {
    this.pendingEvent = true;
    if (this.busy) { return; }
    if (Date.now() - this.lastScan >= 180) { this.scan(); }
    else if (this.timer === -1) {
      this.timer = setTimeout(() => { this.scan(); }, 180);
    }
  }
  private stopTimer(): void {
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
  }
  private record(message: string): void {
    this.status.message = message;
    this.status.history = [new Date().toLocaleTimeString() + '  ' + message, ...this.status.history].slice(0, 20);
    this.store?.saveStatus(this.status);
    hilog.info(0x0010, 'QuietStart', '%{public}s', message);
  }
  private async scan(): Promise<void> {
    if (!this.alive || this.busy || !this.store) { return; }
    this.busy = true;
    this.pendingEvent = false;
    this.lastScan = Date.now();
    this.stopTimer();
    let again: boolean = false;
    try {
      const settings: Settings = this.store.readSettings();
      const root: AccessibilityElement = await this.context.getWindowRootElement();
      const bundle: string = await root.attributeValue('bundleName');
      const now: number = Date.now();
      if (bundle !== this.activeBundle) {
        this.activeBundle = bundle;
        this.windowStarted = now;
        this.didAttempt = false;
        this.status.lastBundle = bundle;
        if (bundle !== OWN_BUNDLE) { this.status.lastExternalBundle = bundle; }
        this.store.saveStatus(this.status);
      }
      const testing: boolean = bundle === OWN_BUNDLE && settings.testUntil > now;
      if (testing && this.testToken !== settings.testUntil) {
        this.testToken = settings.testUntil;
        this.windowStarted = now;
        this.didAttempt = false;
        this.record('开始测试：等待右上角跳过按钮');
      }
      const allowed: boolean = testing || (settings.enabled && bundle !== OWN_BUNDLE && settings.packages.includes(bundle));
      if (!allowed || this.didAttempt || now - this.windowStarted > WINDOW_MS) { return; }
      again = true;
      const rootRect: Rect = await root.attributeValue('screenRect');
      const screen: Bounds = { left: rootRect.left, top: rootRect.top, width: rootRect.width, height: rootRect.height };
      const candidates: AccessibilityElement[] = await root.findElement('content', '跳过');
      candidates.push(...await root.findElement('content', 'Skip'));
      let adMarker: boolean = testing;
      if (!adMarker) {
        const markers: AccessibilityElement[] = await root.findElement('content', '广告');
        for (const marker of markers.slice(0, 12)) {
          if (await marker.attributeValue('bundleName') === bundle && await marker.attributeValue('isVisible') &&
            (await marker.attributeValue('text')).trim() === '广告') { adMarker = true; break; }
        }
      }
      for (const candidate of candidates.slice(0, 24)) {
        if (await candidate.attributeValue('bundleName') !== bundle ||
          !await candidate.attributeValue('isVisible') || !await candidate.attributeValue('clickable') ||
          !await candidate.attributeValue('isEnable')) { continue; }
        const label: string = await candidate.attributeValue('text');
        const accessibleLabel: string = await candidate.attributeValue('accessibilityText');
        if (!isSkipLabel(label) && !isSkipLabel(accessibleLabel)) { continue; }
        if (!adMarker && !hasCountdown(label) && !hasCountdown(accessibleLabel)) { continue; }
        const rect: Rect = await candidate.attributeValue('screenRect');
        const bounds: Bounds = { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
        if (!isSafePosition(bounds, screen) || !(await candidate.actionNames()).includes('click')) { continue; }
        // Fail closed if the user disables the rule or changes apps while reading nodes.
        const latest: Settings = this.store.readSettings();
        const currentRoot: AccessibilityElement = await this.context.getWindowRootElement();
        if (!this.alive || Date.now() - this.windowStarted > WINDOW_MS ||
          await currentRoot.attributeValue('bundleName') !== bundle ||
          !(testing ? latest.testUntil > Date.now() : latest.enabled && latest.packages.includes(bundle))) { return; }
        this.didAttempt = true;
        again = false;
        await candidate.performAction('click');
        this.status.clickCount++;
        this.record('已发送跳过点击 · ' + bundle);
        return;
      }
    } catch (error) {
      const message: string = '读取或点击失败，错误码 ' + (error as BusinessError).code;
      if (this.status.message !== message) { this.record(message); }
      again = false;
    } finally {
      this.busy = false;
      if (this.alive && (this.pendingEvent || (again && Date.now() - this.windowStarted <= WINDOW_MS))) {
        this.timer = setTimeout(() => { this.scan(); }, 300);
      }
    }
  }
}
