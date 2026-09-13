import { socket } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DebugStore, isDebugOnline } from './DebugStore';
import { LocalStore } from './LocalStore';
import { bytesField, HdcDecoder, HdcField, hdcFrame, HdcPacket, hdcTlvValue, joinBytes, localDebugPort, numberField, readFields } from './HdcProtocol';

export interface WorkerShell {
  execute(command: string): Promise<string>;
}

export type PrepareWorker = (shell: WorkerShell, progress: (message: string) => void) => Promise<void>;

export class ActivationState {
  phase: string = 'connecting';
  port: string = '';
  startedAt: number = 0;
  commandAt: number = 0;
  finishedAt: number = 0;
  success: boolean = false;
  message: string = '';
  commandOutput: string = '';
}

class LocalIdentity {
  privateKey: string = '';
  publicKey: string = '';
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

  readState(): ActivationState {
    try {
      const state = JSON.parse(fs.readTextSync(this.directory + '/local-activation.json')) as ActivationState;
      if (state.startedAt > 0 && state.finishedAt === 0) {
        const status = new DebugStore(this.directory).readStatus();
        if (isDebugOnline(status) && status.startedAt >= state.startedAt) {
          state.success = true;
          state.finishedAt = Date.now();
          state.message = '本机激活成功，已验证新会话心跳。调试连接已关闭。';
          this.write('local-activation.json', JSON.stringify(state));
        } else if (Date.now() - (state.commandAt || state.startedAt) > (state.commandAt ? 35000 : (state.phase === 'installing' ? 180000 : 95000))) {
          state.finishedAt = Date.now();
          state.message = '上次激活未收到新会话心跳，请检查无线调试后重试。';
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
      this.session = new DataView(cryptoFramework.createRandom().generateRandomSync(4).data.buffer).getUint32(0) || 1;
      this.tcp = socket.constructTCPSocketInstance();
      this.tcp.on('message', (info: socket.SocketMessageInfo) => {
        this.serial = this.serial.then(async () => {
          if (this.closed) { return; }
          for (const packet of this.decoder.push(new Uint8Array(info.message))) { await this.receive(packet); }
        }).catch((error: Error) => { this.fail(error.message); });
      });
      this.tcp.on('error', (error: BusinessError) => {
        if (!this.sent) { this.fail('本机调试连接失败（' + error.code + '），请检查无线调试开关和端口。'); }
      });
      this.tcp.on('close', () => {
        if (!this.closed && !this.sent) { this.fail('系统关闭了调试连接，请重新开启无线调试后再试。'); }
      });
      this.save('正在连接本机无线调试端口…');
      // Loopback is intentional: no LAN/cloud host receives debug traffic or keys.
      await this.tcp.connect({ address: { address: '127.0.0.1', family: 1, port: port }, timeout: 5000 });
      if (this.closed) { return; }
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
    hilog.info(0, 'QuietStartLocal', 'send channel=%{public}d command=%{public}d bytes=%{public}d', channel, command, frame.length);
    await this.tcp.send({ data: frame.buffer as ArrayBuffer });
    hilog.info(0, 'QuietStartLocal', 'sent channel=%{public}d command=%{public}d', channel, command);
  }

  private text(data: Uint8Array): string { return new util.TextDecoder('utf-8').decodeToString(data); }

  private async receive(packet: HdcPacket): Promise<void> {
    hilog.info(0, 'QuietStartLocal', 'recv channel=%{public}d command=%{public}d bytes=%{public}d', packet.channel, packet.command, packet.data.length);
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
    } else if (packet.channel === 101 && (packet.command === 10 || packet.command === 9)) {
      if (this.labelBundle) {
        for (const byte of packet.data) { this.labelBytes.push(byte); }
        if (this.labelBytes.length > 4096) { this.close(); return; }
        const output = this.text(new Uint8Array(this.labelBytes));
        const end = output.indexOf('__QuietStartLabelEnd__');
        if (end >= 0) {
          const value = output.slice(0, end).trim();
          const valid = value.length > 0 && value.length <= 80 && !/[\r\n]/.test(value) &&
            !/^(error|failed|usage|permission|\[fail\])/i.test(value) && value !== this.labelBundle;
          this.labelResolve?.(valid ? value : ''); this.labelResolve = undefined; this.close();
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

  private async prepareAndLaunch(): Promise<void> {
    if (this.sent || this.preparing || this.closed) { return; }
    if (!this.labelBundle && this.prepare) {
      this.preparing = true; this.state.phase = 'installing';
      this.save('正在检查本机工作模块…');
      await this.prepare(this, (message: string) => { this.save(message); });
      this.preparing = false;
    }
    if (!this.closed) { await this.launchWorker(); }
  }

  private async launchWorker(): Promise<void> {
    if (this.sent || this.closed || !this.authorized) { return; }
    if (this.labelBundle) {
      this.sent = true;
      // Bundle is strictly validated; query ONLY the foreground app's display label.
      await this.send(101, 1001, this.encoder.encodeInto('bm dump -n ' + this.labelBundle + ' -l; echo __QuietStartLabelEnd__'));
      return;
    }
    const store = new LocalStore(this.directory);
    const settings = store.readSettings();
    settings.stopRequested = false;
    store.saveSettings(settings);
    this.sent = true;
    this.state.phase = 'starting';
    this.state.commandAt = Date.now();
    this.save('本机认证成功，轻启将重新打开并启动会话…');
    // This detached task survives the restart of this app and its TCP socket.
    // The fixed command accepts no user-controlled shell text.
    const command = "/bin/nohup /bin/setsid /bin/sh -c 'echo QuietStartChildReady; sleep 2; " +
      "aa force-stop com.tonghongxiang.quietstart; echo QuietStartOldProcessStopped; " +
      "aa test -b com.tonghongxiang.quietstart -m entry_test -s unittest OpenHarmonyTestRunner -s mode skip -s seconds 0 -w 3; " +
      "echo QuietStartCommandFinished' </dev/null & " +
      'echo QuietStartLocalScheduled; wait';
    await this.send(101, 1001, this.encoder.encodeInto(command));
  }

  private checkProgress(): void {
    if (this.closed) { return; }
    if (this.labelBundle) { if (Date.now() - this.state.startedAt > 10000) { this.close(); } return; }
    const status = new DebugStore(this.directory).readStatus();
    if (isDebugOnline(status) && status.startedAt >= this.state.startedAt) {
      this.state.success = true;
      this.state.finishedAt = Date.now();
      this.save('本机激活成功，已验证新会话心跳。调试连接已关闭。');
      this.close();
    } else if (Date.now() - (this.state.commandAt || this.state.startedAt) > (this.sent ? 30000 : (this.preparing ? 180000 : 90000))) {
      this.fail(this.sent ? '未收到新会话心跳：' + this.state.commandOutput.slice(-500) : '等待授权超时，请确认无线调试和端口后重试。');
    }
  }

  private fail(message: string): void {
    if (this.closed) { return; }
    this.state.phase = 'error';
    this.state.finishedAt = Date.now();
    this.save(message);
    this.close();
  }

  close(): void {
    this.closed = true;
    clearTimeout(this.commandTimer);
    const reject = this.commandReject; this.commandReject = undefined; this.commandResolve = undefined;
    reject?.(new Error(this.state.message || '本机连接已关闭'));
    this.labelResolve?.(''); this.labelResolve = undefined;
    clearInterval(this.timer);
    this.tcp?.close().catch(() => {});
    this.key = undefined;
  }
}
