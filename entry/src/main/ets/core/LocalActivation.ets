import { socket } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError, osAccount } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DebugStore, isDebugOnline } from './DebugStore';
import { LocalStore } from './LocalStore';
import { SupervisionStore } from './SupervisionStore';
import { SystemExitStore } from './SystemExitStore';
import { SUPERVISOR_PROGRAM, supervisorCommand } from './SupervisorProgram';
import { bytesField, HdcDecoder, HdcField, hdcFrame, HdcPacket, hdcTlvValue, joinBytes, localDebugPort, numberField, readFields } from './HdcProtocol';

export interface WorkerShell {
  execute(command: string): Promise<string>;
  installWorker(hash: string): Promise<void>;
}

export type PrepareWorker = (shell: WorkerShell, progress: (message: string) => void) => Promise<boolean | void>;

export class ActivationState {
  phase: string = 'connecting';
  port: string = '';
  startedAt: number = 0;
  commandAt: number = 0;
  finishedAt: number = 0;
  success: boolean = false;
  message: string = '';
  commandOutput: string = '';
  installHash: string = '';
  installToken: string = '';
}

class LocalIdentity {
  privateKey: string = '';
  publicKey: string = '';
}

export class LayoutReadTiming {
  startedAt: number = 0;
  reused: boolean = false;
  keyReadyAt: number = 0;
  connectedAt: number = 0;
  authorizedAt: number = 0;
  commandAt: number = 0;
  firstByteAt: number = 0;
  finishedAt: number = 0;
  bytes: number = 0;
}

export class LocalActivation implements WorkerShell {
  private prepare?: PrepareWorker;
  private preparing: boolean = false;
  private commandChannel: number = 200;
  private commandBytes: number[] = [];
  private commandResolve?: (value: string) => void;
  private commandReject?: (error: Error) => void;
  private commandTimer: number = -1;
  private labelBundle: string = '';
  private appCommand: string = '';
  private layoutRead: boolean = false;
  private layoutChannel: number = 100;
  private layoutChunks: Uint8Array[] = [];
  private layoutByteCount: number = 0;
  private layoutSuffix: string = '';
  private layoutIdleAt: number = 0;
  private layoutTiming: LayoutReadTiming = new LayoutReadTiming();

  canReuseLayout(): boolean { return !this.closed; }
  readLayoutTiming(): LayoutReadTiming { return this.layoutTiming; }
  private layoutReject?: (error: Error) => void;
  private labelResolve?: (value: string) => void;
  private labelBytes: number[] = [];
  private directory: string;
  private tcp?: socket.TCPSocket;
  private key?: cryptoFramework.KeyPair;
  private decoder: HdcDecoder = new HdcDecoder();
  private serial: Promise<void> = Promise.resolve();
  private state: ActivationState = new ActivationState();
  private timer: number = -1;
  private sent: boolean = false;
  private authorized: boolean = false;
  private closed: boolean = false;
  private session: number = 0;
  private encoder: util.TextEncoder = new util.TextEncoder();
  private base64: util.Base64Helper = new util.Base64Helper();

  constructor(directory: string, prepare?: PrepareWorker) { this.directory = directory; this.prepare = prepare; }

  async readAppLabel(bundle: string): Promise<string> {
    if (!/^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(bundle) || !fs.accessSync(this.directory + '/local-hdc-identity.json')) { return ''; }
    let port = '';
    try { port = (JSON.parse(fs.readTextSync(this.directory + '/local-activation.json')) as ActivationState).port; } catch (_) {}
    if (!localDebugPort(port)) { return ''; }
    this.labelBundle = bundle;
    const result = new Promise<string>((resolve) => { this.labelResolve = resolve; });
    this.activate(port).catch(() => { this.close(); });
    return result;
  }

  async readInstalledApps(): Promise<string> {
    return this.readAppCommand('bm dump -a -l');
  }

  async readAppEntry(bundle: string): Promise<string> {
    if (!/^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(bundle)) { throw new Error('Invalid application'); }
    return this.readAppCommand('bm dump -n ' + bundle);
  }

  async startAppEntry(bundle: string, command: string): Promise<string> {
    if (!/^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(bundle) || !command.startsWith('aa start -b ' + bundle + ' ') ||
      !/^aa start -b [A-Za-z0-9_.]+ (?:-m [A-Za-z0-9_.]+ -a [A-Za-z0-9_.]+|-A (?:ohos.want.action.home|action.system.home) -e entity.system.home)$/.test(command)) {
      throw new Error('Invalid application entry');
    }
    return this.readAppCommand(command);
  }

  private async readAppCommand(command: string): Promise<string> {
    if (this.closed || this.labelResolve || !fs.accessSync(this.directory + '/local-hdc-identity.json')) { throw new Error('本机连接尚未就绪'); }
    let port = '';
    try { port = (JSON.parse(fs.readTextSync(this.directory + '/local-activation.json')) as ActivationState).port; } catch (_) {}
    if (!localDebugPort(port)) { throw new Error('无线调试端口无效'); }
    this.labelBundle = 'app-command'; this.appCommand = command;
    const result = new Promise<string>((resolve) => { this.labelResolve = resolve; });
    this.activate(port).catch(() => { this.close(); });
    return result;
  }

  async readCurrentLayout(): Promise<string> {
    if (this.closed) { throw new Error('本机布局连接已关闭'); }
    if (this.labelResolve) { throw new Error('本机布局请求尚未完成'); }
    if (!fs.accessSync(this.directory + '/local-hdc-identity.json')) { return ''; }
    let port = '';
    try { port = (JSON.parse(fs.readTextSync(this.directory + '/local-activation.json')) as ActivationState).port; } catch (_) {}
    if (!localDebugPort(port)) { return ''; }
    if (this.authorized && Number(this.state.port) !== localDebugPort(port)) {
      this.close(); throw new Error('无线调试端口已变更，请重试读取');
    }
    // A socket carries only sequential read-only layout requests. Each gets a
    // fresh channel; late output/close packets can never satisfy the next read.
    this.layoutRead = true; this.labelBundle = 'layout'; this.labelBytes = [];
    this.layoutChunks = []; this.layoutByteCount = 0; this.layoutSuffix = '';
    this.layoutChannel++;
    this.layoutTiming = new LayoutReadTiming();
    this.layoutTiming.startedAt = Date.now(); this.layoutTiming.reused = this.authorized;
    const result = new Promise<string>((resolve, reject) => { this.labelResolve = resolve; this.layoutReject = reject; });
    if (this.authorized) { this.sendLayout().catch((error: Error) => { this.fail(error.message); }); }
    else { this.activate(port).catch(() => { this.close(); }); }
    return result;
  }

  private async sendLayout(): Promise<void> {
    this.sent = true;
    this.layoutTiming.commandAt = Date.now();
    const temp = '/data/local/tmp/quietstart-layout-' + this.session + '-' + this.layoutChannel + '.json';
    const command = 'umask 077; /bin/timeout -k 1 2 uitest dumpLayout -p ' + temp + ' >' + temp + '.log 2>&1; ' +
      'qs_layout_code=$?; if [ "$qs_layout_code" -eq 0 ] && [ -s ' + temp + ' ]; then cat ' + temp +
      '; else echo "Layout CLI failed: exit=$qs_layout_code"; head -c 512 ' + temp + '.log; fi; ' +
      'rm -f ' + temp + ' ' + temp + '.log; echo __QuietStartLabelEnd__';
    await this.send(this.layoutChannel, 1001, this.encoder.encodeInto(command));
  }

  readState(): ActivationState {
    try {
      const state = JSON.parse(fs.readTextSync(this.directory + '/local-activation.json')) as ActivationState;
      if (state.startedAt > 0 && state.finishedAt === 0) {
        const status = new DebugStore(this.directory).readStatus();
        if (isDebugOnline(status) && status.startedAt >= state.startedAt) {
          state.success = true;
          state.finishedAt = Date.now();
          state.message = '本机激活成功，已验证会话心跳和接口响应。调试连接已关闭。';
          this.write('local-activation.json', JSON.stringify(state));
        } else if (Date.now() - (state.commandAt || state.startedAt) > (state.installToken ? 90000 : state.commandAt ? 35000 : (state.phase === 'installing' ? 180000 : 95000))) {
          state.finishedAt = Date.now();
          state.phase = 'error';
          state.message = state.installToken ? '未能恢复工作模块安装结果，请重新连接；已完成的安装会先核验，不重复覆盖。' : '上次激活未收到新会话心跳，请检查无线调试后重试。';
          this.write('local-activation.json', JSON.stringify(state));
        }
      }
      return state;
    }
    catch (_) { return new ActivationState(); }
  }

  private save(message: string): void {
    if (this.closed || this.labelBundle) { return; }
    this.state.message = message;
    this.write('local-activation.json', JSON.stringify(this.state));
  }

  private write(name: string, text: string): void {
    const path = this.directory + '/' + name;
    const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, text); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path);
  }

  async activate(input: string): Promise<void> {
    const port = localDebugPort(input);
    if (!port) { throw new Error('请填写无线调试页面显示的端口，或完整 IP 地址和端口。'); }
    if (!this.labelBundle && isDebugOnline(new DebugStore(this.directory).readStatus())) { return; }
    if (!this.labelBundle) { new SupervisionStore(this.directory).setNotice(''); }
    this.state = new ActivationState();
    this.state.port = port.toString();
    this.state.startedAt = Date.now();
    this.save('正在准备本机调试身份…');
    this.timer = setInterval(() => { this.checkProgress(); }, 500);
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('RSA3072');
      const path = this.directory + '/local-hdc-identity.json';
      if (fs.accessSync(path)) {
        const identity = JSON.parse(fs.readTextSync(path)) as LocalIdentity;
        this.key = await generator.convertKey({ data: this.base64.decodeSync(identity.publicKey) },
          { data: this.base64.decodeSync(identity.privateKey) });
      } else {
        this.key = await generator.generateKeyPair();
        const identity = new LocalIdentity();
        identity.privateKey = this.base64.encodeToStringSync(this.key.priKey.getEncoded().data);
        identity.publicKey = this.base64.encodeToStringSync(this.key.pubKey.getEncoded().data);
        this.write('local-hdc-identity.json', JSON.stringify(identity));
      }
      if (this.closed) { return; }
      this.layoutTiming.keyReadyAt = Date.now();
      this.session = new DataView(cryptoFramework.createRandom().generateRandomSync(4).data.buffer).getUint32(0) || 1;
      this.tcp = socket.constructTCPSocketInstance();
      this.tcp.on('message', (info: socket.SocketMessageInfo) => {
        this.serial = this.serial.then(async () => {
          if (this.closed) { return; }
          for (const packet of this.decoder.push(new Uint8Array(info.message))) { await this.receive(packet); }
        }).catch((error: Error) => { this.fail(error.message); });
      });
      this.tcp.on('error', (error: BusinessError) => {
        if (this.layoutRead || !this.sent) { this.fail('本机调试连接失败（' + error.code + '），请检查无线调试开关和端口。'); }
      });
      this.tcp.on('close', () => {
        if (!this.closed && (this.layoutRead || !this.sent)) { this.fail('系统关闭了调试连接，请重新开启无线调试后再试。'); }
      });
      this.save('正在连接本机无线调试端口…');
      // Loopback is intentional: no LAN/cloud host receives debug traffic or keys.
      await this.tcp.connect({ address: { address: '127.0.0.1', family: 1, port: port }, timeout: 5000 });
      if (this.closed) { return; }
      this.layoutTiming.connectedAt = Date.now();
      this.save('正在认证；若系统询问，请信任“轻启本机激活”。');
      await this.handshake(0, 'authtype'.padEnd(16) + '1'.padEnd(16) + '1');
    } catch (error) {
      const problem = error as BusinessError;
      this.fail('本机激活失败：' + (problem.message || String(problem.code)));
    }
  }

  private async handshake(type: number, body: string): Promise<void> {
    const data = joinBytes([
      bytesField(1, this.encoder.encodeInto('OHOS HDC')), numberField(2, type), numberField(3, this.session),
      bytesField(4, this.encoder.encodeInto('127.0.0.1:' + this.state.port)),
      bytesField(5, this.encoder.encodeInto(body)), bytesField(6, this.encoder.encodeInto('Ver: 3.2.0b'))
    ]);
    await this.send(0, 1, data);
  }

  private async send(channel: number, command: number, data: Uint8Array): Promise<void> {
    if (this.closed || !this.tcp) { return; }
    const frame = hdcFrame(channel, command, data);
    if (!this.layoutRead) { hilog.info(0, 'QuietStartLocal', 'send channel=%{public}d command=%{public}d bytes=%{public}d', channel, command, frame.length); }
    await this.tcp.send({ data: frame.buffer as ArrayBuffer });
    if (!this.layoutRead) { hilog.info(0, 'QuietStartLocal', 'sent channel=%{public}d command=%{public}d', channel, command); }
  }

  private text(data: Uint8Array): string { return new util.TextDecoder('utf-8').decodeToString(data); }

  private async receive(packet: HdcPacket): Promise<void> {
    if (!this.layoutRead) { hilog.info(0, 'QuietStartLocal', 'recv channel=%{public}d command=%{public}d bytes=%{public}d', packet.channel, packet.command, packet.data.length); }
    if (packet.command === 1 && packet.channel === 0) {
      const fields = readFields(packet.data);
      const banner = this.text(fields.find((f: HdcField) => f.id === 1)?.data ?? new Uint8Array(0));
      if (banner !== 'OHOS HDC') { throw new Error('本机端口返回了未知的调试协议'); }
      const type = fields.find((f: HdcField) => f.id === 2)?.number ?? 0;
      const body = fields.find((f: HdcField) => f.id === 5)?.data ?? new Uint8Array(0);
      if (type === 3 && this.key) {
        if (hdcTlvValue(this.text(body), 'authtype') !== '1') { throw new Error('系统未提供支持的 RSA 认证方式'); }
        const encoded = this.base64.encodeToStringSync(this.key.pubKey.getEncoded().data);
        const lines: string[] = [];
        for (let i = 0; i < encoded.length; i += 64) { lines.push(encoded.slice(i, i + 64)); }
        await this.handshake(3, '轻启本机激活\f-----BEGIN PUBLIC KEY-----\n' + lines.join('\n') + '\n-----END PUBLIC KEY-----\n');
      } else if (type === 2 && this.key) {
        const signer = cryptoFramework.createSign('RSA3072|PSS|SHA512|MGF1_SHA512');
        await signer.init(this.key.priKey);
        signer.setSignSpec(cryptoFramework.SignSpecItem.PSS_SALT_LEN_NUM, 64);
        const signature = await signer.sign({ data: body });
        await this.handshake(2, this.base64.encodeToStringSync(signature.data));
      } else if (type === 4) {
        const status = hdcTlvValue(this.text(body), 'daemonauthstatus');
        const reason = hdcTlvValue(this.text(body), 'emgmsg');
        if (status === 'SUCCESS' && !this.sent) {
          this.authorized = true;
          this.layoutTiming.authorizedAt = Date.now();
          this.save('本机认证成功，正在完成调试连接…');
        } else if (reason.includes('E000002')) {
          this.save('请在系统弹窗中选择“始终信任”：轻启本机激活。');
        } else if (reason.length > 0) { throw new Error('系统未授权本机激活：' + reason.slice(0, 240)); }
      } else if (type === 5 || type === 6) { throw new Error('系统拒绝认证或要求尚未支持的加密协议'); }
    } else if (packet.command === 2 && packet.data.length === 1) {
      if (packet.channel === 0) {
        // In HDC, close(0) means ClearOwnTasks(session, 0): cancel ALL tasks.
        // Drain the authentication close before launching channel 101; never
        // acknowledge a duplicate close(0) once work has started.
        if (this.sent || this.preparing) { return; }
        if (packet.data[0] > 0) { await this.send(0, 2, new Uint8Array([packet.data[0] - 1])); }
        if (this.authorized && !this.closed) {
          // Do not block the receive queue: installation needs replies on this same socket.
          this.prepareAndLaunch().catch((error: Error) => { this.fail(error.message); });
        }
      } else if (packet.data[0] > 0) {
        await this.send(packet.channel, 2, new Uint8Array([packet.data[0] - 1]));
      }
    } else if (packet.channel === this.commandChannel && this.commandResolve && (packet.command === 10 || packet.command === 9)) {
      for (const byte of packet.data) { this.commandBytes.push(byte); }
      if (this.commandBytes.length > 131072) { this.fail('工作模块检查返回内容过大，请重试。'); return; }
      const output = this.text(new Uint8Array(this.commandBytes));
      const match = /__QuietStartExec_([0-9]+)__/.exec(output);
      if (match) {
        const resolve = this.commandResolve; const reject = this.commandReject;
        this.commandResolve = undefined; this.commandReject = undefined; clearTimeout(this.commandTimer);
        if (Number(match[1]) !== 0) { reject?.(new Error('工作模块准备失败：' + output.slice(0, match.index).slice(-500))); }
        else { resolve(output.slice(0, match.index).trim()); }
      }
    } else if (packet.channel === (this.layoutRead ? this.layoutChannel : 101) && (packet.command === 10 || packet.command === 9)) {
      if (this.layoutRead) { this.receiveLayout(packet.data); return; }
      if (this.labelBundle) {
        for (const byte of packet.data) { this.labelBytes.push(byte); }
        if (this.labelBytes.length > (this.layoutRead || this.appCommand ? 4194304 : 4096)) { this.close(); return; }
        const output = this.text(new Uint8Array(this.labelBytes));
        const end = output.indexOf('__QuietStartLabelEnd__');
        if (end >= 0) {
          const value = output.slice(0, end).trim();

          const valid = value.length > 0 && value.length <= 80 && !/[\r\n]/.test(value) &&
            !/^(error|failed|usage|permission|\[fail\])/i.test(value) && value !== this.labelBundle;
          this.labelResolve?.(this.appCommand ? value : valid ? value : ''); this.labelResolve = undefined; this.close();
        }
        return;
      }
      this.state.commandOutput = (this.state.commandOutput + this.text(packet.data)).slice(-2000);
      if (this.state.commandOutput.includes('error:') || this.state.commandOutput.includes('Error:') ||
        this.state.commandOutput.includes('[Fail]')) {
        this.fail('系统启动会话失败：' + this.state.commandOutput.slice(-500));
      } else { this.save(this.state.message); }
    }
  }

  private receiveLayout(data: Uint8Array): void {
    if (!this.labelResolve) { return; }
    if (!this.layoutTiming.firstByteAt) { this.layoutTiming.firstByteAt = Date.now(); }
    this.layoutByteCount += data.length;
    if (this.layoutByteCount > 4194304) { this.fail('本机布局响应超过 4 MiB'); return; }
    this.layoutChunks.push(data);
    // The sentinel is ASCII. Scan only the suffix until complete, then join and
    // decode UTF-8 once (including code points split across transport packets).
    let tail = '';
    for (let i = Math.max(0, data.length - 64); i < data.length; i++) { tail += String.fromCharCode(data[i]); }
    this.layoutSuffix = (this.layoutSuffix + tail).slice(-128);
    if (!this.layoutSuffix.includes('__QuietStartLabelEnd__')) { return; }
    const output = this.text(joinBytes(this.layoutChunks));
    const value = output.slice(0, output.indexOf('__QuietStartLabelEnd__')).trim();
    if (!value.startsWith('{')) { this.fail('布局命令未返回 JSON：' + value.slice(0, 200)); return; }
    this.layoutTiming.finishedAt = Date.now(); this.layoutTiming.bytes = this.layoutByteCount;
    this.layoutIdleAt = Date.now(); this.layoutChunks = []; this.layoutSuffix = '';
    const resolve = this.labelResolve; this.layoutReject = undefined; this.labelResolve = undefined;
    resolve(value);
  }

  async execute(command: string): Promise<string> {
    if (this.closed || !this.authorized || !this.preparing || this.commandResolve) { throw new Error('本机安装连接尚未就绪'); }
    this.commandChannel++; this.commandBytes = [];
    const result = new Promise<string>((resolve, reject) => {
      this.commandResolve = resolve; this.commandReject = reject;
      this.commandTimer = setTimeout(() => { this.fail('工作模块准备超时，请检查无线调试后重试。'); }, 30000);
    });
    this.send(this.commandChannel, 1001, this.encoder.encodeInto(command + '; echo __QuietStartExec_$?__'))
      .catch((error: Error) => { this.fail(error.message); });
    return result;
  }

  async installWorker(hash: string): Promise<void> {
    if (!/^[a-f0-9]{64}$/.test(hash) || this.closed || !this.authorized || !this.preparing || this.sent) {
      throw new Error('工作模块安装尚未就绪');
    }
    const target = '/data/local/tmp/quietstart-worker-' + hash.slice(0, 12);
    this.state.installHash = hash; this.state.installToken = this.state.startedAt.toString();
    new SupervisionStore(this.directory).stop();
    new SystemExitStore(this.directory).markExpected('module-install');
    this.state.commandAt = Date.now(); this.sent = true;
    this.save('正在安装工作模块，完成后将自动返回并继续连接…');
    // bm may kill this app even on a same-version replacement. The detached
    // job owns its result and reopens the UI; a new HDC connection verifies it.
    // bm can return zero on failure and loses its output when stdout is a
    // regular file. Pipe it through cat, retaining timeout's status separately.
    const body = 'sleep 1; rm -f ' + target + '/installed.sha256 ' + target + '/install.exit; ' +
      '{ /bin/timeout 45 bm install -p ' + target + '/worker.hap; echo $? > ' + target + '/install.exit; } 2>&1 | cat > ' + target + '/install.log; ' +
      'result=$(cat ' + target + '/install.exit); ' +
      'if [ "$result" = 0 ] && grep -qi "install bundle successfully" ' + target + '/install.log && ' +
      '! grep -qiE "fail|error" ' + target + '/install.log; then ' +
      'echo ' + hash + ' > ' + target + '/installed.tmp; mv ' + target + '/installed.tmp ' + target + '/installed.sha256; fi; ' +
      'rm -f ' + target + '/worker.b64 ' + target + '/worker.hap; ' +
      'aa start -b com.tonghongxiang.quietstart -a EntryAbility --ps quietstartInstallResume ' + this.state.installToken;
    await this.send(101, 1001, this.encoder.encodeInto('/bin/nohup /bin/setsid /bin/sh -c \' ' + body +
      ' \' </dev/null > ' + target + '/job.log 2>&1 & echo QuietStartInstallScheduled; wait'));
  }

  private async prepareAndLaunch(): Promise<void> {
    if (this.sent || this.preparing || this.closed) { return; }
    if (!this.labelBundle && this.prepare) {
      this.preparing = true; this.state.phase = 'installing';
      this.save('正在检查本机工作模块…');
      const ready = await this.prepare(this, (message: string) => { this.save(message); });
      this.preparing = false;
      if (ready === false) { return; }
    }
    if (!this.closed) { await this.launchWorker(); }
  }

  private async launchWorker(): Promise<void> {
    if (this.sent || this.closed || !this.authorized) { return; }
    if (this.labelBundle) {
      this.sent = true;
      if (this.layoutRead) {
        await this.sendLayout(); return;
      }
      // Bundle is strictly validated; query ONLY the foreground app's display label.
      await this.send(101, 1001, this.encoder.encodeInto(this.appCommand ?
        '/bin/timeout 5 ' + this.appCommand + '; echo __QuietStartLabelEnd__' :
        'bm dump -n ' + this.labelBundle + ' -l; echo __QuietStartLabelEnd__'));
      return;
    }
    const account = await osAccount.getAccountManager().getOsAccountLocalId();
    if (this.closed || this.sent) { return; }
    const store = new LocalStore(this.directory);
    const settings = store.readSettings();
    settings.stopRequested = false;
    // An explicit new connection enables skipping. Automatic supervisor
    // recovery does not use this path and preserves the user's pause switch.
    settings.enabled = true;
    store.saveSettings(settings);
    new SystemExitStore(this.directory).markExpected('activation');
    const token = this.state.startedAt.toString();
    new SupervisionStore(this.directory).start(token);
    new SupervisionStore(this.directory).setNotice('');
    this.sent = true;
    this.state.phase = 'starting';
    this.state.commandAt = Date.now();
    this.save('本机认证成功，轻启将重新打开并启动会话…');
    const command = supervisorCommand(token, this.base64.encodeToStringSync(this.encoder.encodeInto(SUPERVISOR_PROGRAM)), account);
    await this.send(101, 1001, this.encoder.encodeInto(command));
  }

  private checkProgress(): void {
    if (this.closed) { return; }
    if (this.layoutRead) {
      if (this.labelResolve && Date.now() - this.layoutTiming.startedAt > 5000) { this.fail('本机布局读取超过 5 秒'); }
      else if (!this.labelResolve && Date.now() - this.layoutIdleAt > 15000) { this.close(); }
      return;
    }
    if (this.labelBundle) { if (Date.now() - this.state.startedAt > 10000) { this.close(); } return; }
    const status = new DebugStore(this.directory).readStatus();
    if (isDebugOnline(status) && status.startedAt >= this.state.startedAt) {
      this.state.success = true;
      this.state.finishedAt = Date.now();
      this.save('本机激活成功，已验证会话心跳和接口响应。调试连接已关闭。');
      this.close();
    } else if (Date.now() - (this.state.commandAt || this.state.startedAt) > (this.state.installToken ? 90000 : this.sent ? 30000 : (this.preparing ? 180000 : 90000))) {
      this.fail(this.sent ? '未收到新会话心跳：' + this.state.commandOutput.slice(-500) : '等待授权超时，请确认无线调试和端口后重试。');
    }
  }

  private fail(message: string): void {
    if (this.closed) { return; }
    this.state.phase = 'error';
    this.state.finishedAt = Date.now();
    if (this.layoutRead) { this.layoutReject?.(new Error(message)); this.layoutReject = undefined; }
    this.save(message);
    this.close();
  }

  close(): void {
    this.closed = true;
    this.layoutChunks = []; this.layoutSuffix = "";
    this.layoutReject?.(new Error('本机布局连接结束：超时、响应过大或连接中断')); this.layoutReject = undefined;
    clearTimeout(this.commandTimer);
    const reject = this.commandReject; this.commandReject = undefined; this.commandResolve = undefined;
    reject?.(new Error(this.state.message || '本机连接已关闭'));
    this.labelResolve?.(''); this.labelResolve = undefined;
    clearInterval(this.timer);
    this.tcp?.close().catch(() => {});
    this.key = undefined;
  }
}
