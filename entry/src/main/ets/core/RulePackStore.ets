import { fileIo as fs } from '@kit.CoreFileKit';
import { RecognitionPack, RecognitionRule, parseRulePack } from './RulePack';
import { builtinRulePack } from './BuiltinRulePack';
export class RecognitionPreferences {
  localVersion: number = 1;
  rules?: RecognitionRule[];
}
class LegacyRecognitionState {
  current: string = '';
  previous: string = '';
}
export class RulePackStore {
  private directory: string;
  private cached?: RecognitionPack;
  private nextReadAt: number = 0;
  constructor(directory: string) { this.directory = directory; }
  preferences(): RecognitionPreferences {
    let stored: RecognitionPreferences = new RecognitionPreferences();
    let migrated: boolean = false;
    try {
      stored = JSON.parse(fs.readTextSync(this.directory + '/recognition-preferences.json')) as RecognitionPreferences;
      migrated = stored.localVersion === 1;
      if (stored.rules !== undefined) {
        const pack = new RecognitionPack(); pack.rules = stored.rules; parseRulePack(JSON.stringify(pack));
      }
    } catch (_) { stored = new RecognitionPreferences(); migrated = false; }
    if (migrated) { return stored; }
    const pref = new RecognitionPreferences();
    // Keep personal edits first, otherwise preserve the previously active conditions locally.
    pref.rules = stored.rules;
    if (pref.rules === undefined) {
      try {
        const legacy = JSON.parse(fs.readTextSync(this.directory + '/recognition-pack.json')) as LegacyRecognitionState;
        try { pref.rules = parseRulePack(legacy.current).rules; }
        catch (_) { pref.rules = parseRulePack(legacy.previous).rules; }
      } catch (_) {}
    }
    this.write(pref);
    return pref;
  }
  setLocalRules(rules: RecognitionRule[]): void {
    const pack = new RecognitionPack(); pack.rules = rules; parseRulePack(JSON.stringify(pack));
    const pref = new RecognitionPreferences(); pref.rules = rules; this.write(pref);
  }
  resetLocalRules(): void { this.write(new RecognitionPreferences()); }
  read(): RecognitionPack {
    if (this.cached && Date.now() < this.nextReadAt) { return this.cached; }
    const pref = this.preferences();
    this.cached = builtinRulePack();
    if (pref.rules !== undefined) { this.cached.rules = pref.rules; }
    this.nextReadAt = Date.now() + 2000;
    return this.cached;
  }
  private write(pref: RecognitionPreferences): void {
    const path = this.directory + '/recognition-preferences.json';
    const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, JSON.stringify(pref)); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path); this.cached = undefined; this.nextReadAt = 0;
    // Remove obsolete remote metadata only after the local replacement is committed.
    try { fs.unlinkSync(this.directory + '/recognition-pack.json'); } catch (_) {}
  }
}
