// Declarative recognition hints. They never grant click permission or coordinates.
export class RecognitionRule {
  id: string = '';
  field: string = 'text';
  value: string = '';
  match: string = 'equals';
  action: string = 'skip';
  bundles: string[] = [];
  exclude: string[] = [];
  maxLength: number = 12;
}
export class RecognitionPack {
  schema: number = 1;
  id: string = 'quietstart-harmony';
  version: number = 1;
  name: string = '轻启鸿蒙规则';
  rules: RecognitionRule[] = [];
}
export function parseRulePack(text: string): RecognitionPack {
  if (text.length > 131072) { throw new Error('规则文件过大'); }
  const pack = JSON.parse(text) as RecognitionPack;
  if (!pack || pack.schema !== 1 || pack.id !== 'quietstart-harmony' || !Number.isSafeInteger(pack.version) ||
    pack.version < 1 || typeof pack.name !== 'string' || pack.name.length > 40 ||
    !Array.isArray(pack.rules) || pack.rules.length > 128) { throw new Error('不支持的规则格式'); }
  const ids: string[] = [];
  for (const rule of pack.rules) {
    if (!rule || typeof rule.id !== 'string' || !/^[a-z0-9-]{1,60}$/.test(rule.id) || ids.includes(rule.id) ||
      !['text', 'description'].includes(rule.field) || !['equals', 'contains'].includes(rule.match) ||
      !['skip', 'close'].includes(rule.action) || typeof rule.value !== 'string' || rule.value.length < 2 || rule.value.length > 24 ||
      !Number.isInteger(rule.maxLength) || rule.maxLength < rule.value.length || rule.maxLength > 32 ||
      !Array.isArray(rule.bundles) || rule.bundles.length > 100 ||
      rule.bundles.some((bundle: string) => typeof bundle !== 'string' || !/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/.test(bundle)) ||
      !Array.isArray(rule.exclude) || rule.exclude.length > 24 ||
      rule.exclude.some((value: string) => typeof value !== 'string' || value.length < 1 || value.length > 24)) {
      throw new Error('规则条件无效');
    }
    // Unsupported Android fields must not be silently stripped and executed.
    const allowed = ['id', 'field', 'value', 'match', 'action', 'bundles', 'exclude', 'maxLength'];
    if (Object.keys(rule).some((key: string) => !allowed.includes(key))) { throw new Error('包含不支持的规则条件'); }
    ids.push(rule.id);
  }
  if (Object.keys(pack).some((key: string) => !['schema', 'id', 'version', 'name', 'rules'].includes(key))) {
    throw new Error('包含不支持的策略字段');
  }
  return pack;
}
export function packLabel(value: string, field: string, bundle: string, pack?: RecognitionPack): string {
  if (!pack || typeof value !== 'string' || value.length > 64) { return ''; }
  const compact = value.replace(/[\s\u200b\ufeff]/g, '');
  // Never reinterpret video controls, consent or login choices as splash skips.
  if (/片头|片尾|视频|登录|授权|同意|教程|引导|下一步|不跳过|不略过|取消跳过|不可跳过|不能跳过/.test(compact)) { return ''; }
  const matches = pack.rules.filter((rule: RecognitionRule) => rule.field === field &&
    (!rule.bundles.length || rule.bundles.includes(bundle)) && compact.length <= rule.maxLength &&
    !rule.exclude.some((word: string) => compact.includes(word)) &&
    (rule.match === 'equals' ? compact === rule.value : compact.includes(rule.value)));
  if (!matches.length || matches.some((rule: RecognitionRule) => rule.action !== matches[0].action)) { return ''; }
  return matches[0].action === 'skip' ? '跳过' : '关闭';
}
