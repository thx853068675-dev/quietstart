import { RecognitionRule, RecognitionPack, parseRulePack, packLabel } from './RulePack';

export function strategyProblem(rule: RecognitionRule): string {
  if (rule.value.length < 2) { return '请填写至少 2 个字，例如“跳过”或“关闭”。'; }
  if (rule.value.length > 24) { return '要查找的文字最多填写 24 个字。'; }
  if (!Number.isInteger(rule.maxLength) || rule.maxLength < rule.value.length || rule.maxLength > 32) {
    return '按钮总字数上限请填写 ' + rule.value.length + '～32，不能少于要查找的文字。';
  }
  if (rule.exclude.length > 24 || rule.exclude.some((word: string) => word.length > 24)) { return '最多添加 24 个排除词，每个不超过 24 字。'; }
  if (rule.bundles.length > 100 || rule.bundles.some((bundle: string) => !/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/.test(bundle))) {
    return '应用包名格式不正确，例如 com.example.app；多个包名用逗号分隔。';
  }
  const pack = new RecognitionPack(); pack.rules = [rule];
  try { parseRulePack(JSON.stringify(pack)); } catch (_) { return '条件格式不完整，请检查填写内容。'; }
  return '';
}

// Preview the shipped text matcher only; this never learns a rule or sends input.
export function strategyPreview(rule: RecognitionRule, text: string): string {
  const problem = strategyProblem(rule);
  if (problem) { return problem; }
  if (!text.trim()) { return '输入一段按钮文字，看看能否匹配。'; }
  const compact = text.replace(/[\s\u200b\ufeff]/g, '');
  if (compact.length > rule.maxLength) { return '不匹配：文字超过 ' + rule.maxLength + ' 字上限。'; }
  const excluded = rule.exclude.find((word: string) => compact.includes(word));
  if (excluded) { return '不匹配：含有你排除的“' + excluded + '”。'; }
  if (rule.match === 'equals' ? compact !== rule.value : !compact.includes(rule.value)) {
    return rule.match === 'equals' ? '不匹配：需要与“' + rule.value + '”完全相同。' : '不匹配：没有找到“' + rule.value + '”。';
  }
  const pack = new RecognitionPack(); pack.rules = [rule];
  return packLabel(text, rule.field, rule.bundles[0] || 'com.example.preview', pack) ?
    '能匹配这段文字' : '不匹配：基础防误触检查已排除这段文字。';
}
