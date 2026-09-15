import { captureLayout } from './LayoutCapture';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Driver } from '@kit.TestKit';
import { RecognitionPack } from '../../../main/ets/core/RulePack';
import { LearnedRule, sameRuleGeometry } from '../../../main/ets/core/LearningStore';
import { readImageAd } from './ImageAdEvidence';
import { imageLayoutSignature, discoverSnapshot, SnapshotCandidate, ScanReport, AdMarkerEvidence } from './LearningWorker';

// Owns bounded visual evidence acquisition and persistent structural memory.
// It never approves a rule or sends input; SkipWorker retains those decisions.
class VisualMemory {
  region: string = '';
  key: string = '';
  signature: string = '';
}
export class VisualRecognition {
  private visualMemories?: VisualMemory[];
  private visualSession: string = '';
  private visualReads: number = 0;
  private broadReads: number = 0;
  private visualCursor: number = 0;
  private sessionProofs: string[] = [];
  private directory: string;
  constructor(directory: string) { this.directory = directory; }

  private imageMemories(): VisualMemory[] {
    if (!this.visualMemories) {
      try {
        const path = this.directory + '/image-layout-memory.json';
        const raw = fs.readTextSync(path);
        const entries = raw.length <= 8 * 1024 * 1024 ? JSON.parse(raw) as VisualMemory[] : [];
        this.visualMemories = Array.isArray(entries) ? entries.filter((item: VisualMemory) =>
          item && typeof item.region === 'string' && typeof item.key === 'string' && typeof item.signature === 'string' &&
          item.signature.length > 0 && item.signature.length <= 64000).slice(-128) : [];
      } catch (_) { this.visualMemories = []; }
    }
    return this.visualMemories;
  }

  private rememberImage(candidate: SnapshotCandidate, layout: string): void {
    const signature = imageLayoutSignature(layout, candidate.adMarker?.bounds);
    if (!signature) { return; }
    this.sessionProofs.push(candidate.rule.key + signature);
    const memories = this.imageMemories();
    if (memories.some((item: VisualMemory) => item.key === candidate.rule.key && item.signature === signature)) { return; }
    const memory = new VisualMemory(); memory.key = candidate.rule.key; memory.signature = signature; memory.region = JSON.stringify(candidate.adMarker?.bounds);
    this.visualMemories = memories.concat([memory]).slice(-128);
    try {
      const path = this.directory + '/image-layout-memory.json';
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, JSON.stringify(this.visualMemories)); } finally { fs.closeSync(file); }
    } catch (_) {}
  }

  async discover(driver: Driver, bundle: string, layout: string, path: string, report: ScanReport,
    pack: RecognitionPack, session: string, approved: (rule: LearnedRule) => boolean): Promise<SnapshotCandidate | undefined> {
    let candidate: SnapshotCandidate | undefined;
      const visualSession = session;
      if (this.visualSession !== visualSession) { this.visualSession = visualSession; this.visualReads = 0; this.broadReads = 0; this.visualCursor = 0; this.sessionProofs = []; }
      if (!candidate && report.imageRegions.length) {
        for (const region of report.imageRegions) {
          const signature = imageLayoutSignature(layout, region);
          const memories = signature ? this.imageMemories().filter((item: VisualMemory) =>
            item.signature === signature && item.region === JSON.stringify(region)) : [];
          if (!memories.length) { continue; }
          report.imageMarker = new AdMarkerEvidence('广告', 'image-memory', region);
          const known = discoverSnapshot(layout, bundle, report, pack);
          if (known && memories.some((item: VisualMemory) => item.key === known.rule.key) &&
            (approved(known.rule) || this.sessionProofs.includes(known.rule.key + signature))) {
            candidate = known; break;
          }
          report.imageMarker = undefined;
        }
      }
      if (!candidate && report.imageRegions.length && this.visualReads < 6) {
        const regions = report.imageRegions.slice();
        for (let i = 0; i < Math.min(2, regions.length); i++) {
          const region = regions[this.visualCursor++ % regions.length];
          if (this.visualReads >= 6) { break; }
          const broad = (region.right - region.left) * (region.bottom - region.top) > 160000;
          if (broad && this.broadReads >= 1) { continue; }
          if (broad) { this.broadReads++; }
          this.visualReads++;
          try {
            const imageAt = Date.now();
            if (await readImageAd(driver, this.directory, region) && Date.now() - imageAt <= 1500) {
              report.imageMarker = new AdMarkerEvidence('广告', 'image-ocr', region);
              const pictured = discoverSnapshot(layout, bundle, report, pack);
              // OCR proves advertising text in the layer, never the coordinates used for input.
              // Re-read geometry after OCR and require the same target/window in both trees.
              report.coordinateReadAt = Date.now();
              const currentLayout = await captureLayout(driver, path) ? fs.readTextSync(path) : '';
              const current = currentLayout ? discoverSnapshot(currentLayout, bundle, report, pack) : undefined;
              const signature = imageLayoutSignature(layout, region);
              if (pictured && current && signature && signature === imageLayoutSignature(currentLayout, region) && Date.now() - imageAt <= 1500 && pictured.windowId === current.windowId &&
                sameRuleGeometry(pictured.rule, current.rule) &&
                pictured.bounds.left === current.bounds.left && pictured.bounds.top === current.bounds.top &&
                pictured.bounds.right === current.bounds.right && pictured.bounds.bottom === current.bounds.bottom &&
                pictured.window.left === current.window.left && pictured.window.top === current.window.top &&
                pictured.window.right === current.window.right && pictured.window.bottom === current.window.bottom) { candidate = current; this.rememberImage(current, currentLayout); }
              else { report.reason = '图片广告标记复核：识别超时或当前窗口、按钮结构已变化，重新检查'; }
              break;
            }
          } catch (error) { report.reason += '；图片标记识别不可用：' + String((error as Error).message).slice(0, 80); }
        }
      }
    if (!candidate && this.visualReads >= 6) { report.reason += '；本次启动图片检查已达上限（6 个区域）'; }
    return candidate;
  }
}
