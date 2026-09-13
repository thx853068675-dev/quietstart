// HDC wire format follows OpenHarmony developtools_hdc (Apache-2.0),
// src/common/session.h and serial_struct.h. Only loopback activation is exposed.
export class HdcField {
  id: number = 0;
  number: number = 0;
  data: Uint8Array = new Uint8Array(0);
}

export class HdcPacket {
  channel: number = 0;
  command: number = 0;
  data: Uint8Array = new Uint8Array(0);
}

export function joinBytes(parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((size: number, part: Uint8Array) => size + part.length, 0));
  let offset = 0;
  parts.forEach((part: Uint8Array) => { result.set(part, offset); offset += part.length; });
  return result;
}

function varint(value: number): Uint8Array {
  if (!Number.isSafeInteger(value) || value < 0 || value > 0xFFFFFFFF) { throw new Error('Invalid HDC integer'); }
  const result: number[] = [];
  do {
    const byte = value % 128;
    value = Math.floor(value / 128);
    result.push(byte + (value ? 128 : 0));
  } while (value > 0);
  return new Uint8Array(result);
}

export function numberField(id: number, value: number): Uint8Array {
  return joinBytes([varint(id * 8), varint(value)]);
}

export function bytesField(id: number, data: Uint8Array): Uint8Array {
  return joinBytes([varint(id * 8 + 2), varint(data.length), data]);
}

export function readFields(data: Uint8Array): HdcField[] {
  let offset = 0;
  const read = (): number => {
    let value = 0;
    let factor = 1;
    for (let i = 0; i < 5; i++) {
      if (offset >= data.length) { throw new Error('Truncated HDC field'); }
      const byte = data[offset++];
      value += (byte & 127) * factor;
      if (value > 0xFFFFFFFF) { throw new Error('Oversized HDC integer'); }
      if ((byte & 128) === 0) { return value; }
      factor *= 128;
    }
    throw new Error('Invalid HDC varint');
  };
  const fields: HdcField[] = [];
  while (offset < data.length) {
    const tag = read();
    const field = new HdcField();
    field.id = Math.floor(tag / 8);
    if (field.id === 0 || fields.length >= 64) { throw new Error('Invalid HDC fields'); }
    if (tag % 8 === 0) { field.number = read(); }
    else if (tag % 8 === 2) {
      const length = read();
      if (length > data.length - offset) { throw new Error('Truncated HDC bytes'); }
      field.data = data.slice(offset, offset + length);
      offset += length;
    } else { throw new Error('Unsupported HDC field'); }
    fields.push(field);
  }
  return fields;
}

export function hdcFrame(channel: number, command: number, data: Uint8Array): Uint8Array {
  if (data.length > 1048576) { throw new Error('Oversized HDC payload'); }
  const protect = joinBytes([numberField(1, channel), numberField(2, command), numberField(3, 0), numberField(4, 9)]);
  const header = new Uint8Array(11);
  header.set([72, 87, 0, 0, 1]);
  const view = new DataView(header.buffer);
  view.setUint16(5, protect.length, false);
  view.setUint32(7, data.length, false);
  return joinBytes([header, protect, data]);
}

export class HdcDecoder {
  private pending: Uint8Array = new Uint8Array(0);

  push(chunk: Uint8Array): HdcPacket[] {
    if (chunk.length + this.pending.length > 2097152) { throw new Error('Oversized HDC receive buffer'); }
    this.pending = joinBytes([this.pending, chunk]);
    const packets: HdcPacket[] = [];
    while (this.pending.length >= 11) {
      const view = new DataView(this.pending.buffer);
      if (this.pending[0] !== 72 || this.pending[1] !== 87 || this.pending[4] !== 1) {
        throw new Error('此端口不是兼容的 HDC 调试服务');
      }
      const headSize = view.getUint16(5, false);
      const dataSize = view.getUint32(7, false);
      if (headSize === 0 || headSize > 1024 || dataSize > 1048576) { throw new Error('Invalid HDC frame size'); }
      const size = 11 + headSize + dataSize;
      if (this.pending.length < size) { break; }
      const fields = readFields(this.pending.slice(11, 11 + headSize));
      if (fields.find((f: HdcField) => f.id === 4)?.number !== 9) { throw new Error('Invalid HDC verification code'); }
      const packet = new HdcPacket();
      packet.channel = fields.find((f: HdcField) => f.id === 1)?.number ?? 0;
      packet.command = fields.find((f: HdcField) => f.id === 2)?.number ?? 0;
      packet.data = this.pending.slice(11 + headSize, size);
      const checksum = fields.find((f: HdcField) => f.id === 3)?.number ?? 0;
      if (checksum && checksum !== packet.data.reduce((sum: number, byte: number) => (sum + byte) & 255, 0)) {
        throw new Error('Invalid HDC checksum');
      }
      packets.push(packet);
      this.pending = this.pending.slice(size);
    }
    return packets;
  }
}

export function localDebugPort(input: string): number {
  // Accept the Settings IP:port text for convenience; never connect to that IP.
  const value = input.trim();
  if (!/^(?:\d{1,3}(?:\.\d{1,3}){3}:)?\d{1,5}$/.test(value)) { return 0; }
  const port = Number(value.slice(value.lastIndexOf(':') + 1));
  return Number.isInteger(port) && port >= 1024 && port <= 65535 ? port : 0;
}

export function hdcTlvValue(input: string, wanted: string): string {
  let offset = 0;
  while (offset + 32 <= input.length) {
    const tag = input.slice(offset, offset + 16).trim();
    const lengthText = input.slice(offset + 16, offset + 32).trim();
    if (!/^\d+$/.test(lengthText)) { return ''; }
    const size = Number(lengthText);
    offset += 32;
    if (size > input.length - offset) { return ''; }
    if (tag === wanted) { return input.slice(offset, offset + size); }
    offset += size;
  }
  return '';
}
