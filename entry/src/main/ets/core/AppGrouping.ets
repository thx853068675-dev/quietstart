import { LearnedRule, RuleDecision, ruleState } from './LearningStore';
import { AdFreeEntry } from './AdFreeStore';

// Each app belongs to exactly one group. Global connection/power switches do
// not move apps between groups; these describe the user's per-app configuration.
export function appGroup(bundle: string, allowed: string[], ignored: string[], rules: LearnedRule[],
  decisions: RuleDecision[], quietEntries: AdFreeEntry[], automaticQuiet: boolean, now: number): number {
  if (ignored.includes(bundle)) { return 2; }
  const ownRules = rules.filter((rule: LearnedRule) => rule.bundle === bundle);
  if (automaticQuiet && ownRules.length === 0 && quietEntries.some((entry: AdFreeEntry) =>
    entry.bundle === bundle && entry.updatedAt <= now && entry.pausedUntil > now)) { return 2; }
  if (allowed.includes(bundle) && ownRules.some((rule: LearnedRule) => ruleState(rule, decisions) === 'approved')) { return 0; }
  return 1;
}
