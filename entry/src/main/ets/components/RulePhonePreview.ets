import { PreviewGeometry, previewGeometry } from '../core/PreviewGeometry';
import { LearnedRule } from '../core/LearningStore';
import { ProfileLayer, RecognitionProfile, profileForRule } from '../core/RecognitionProfile';
import { ButtonSample } from './ButtonSample';
import { buttonSampleLayout } from '../core/ButtonPreviewLayout';

@Component
export struct RulePhonePreview {
  @StorageLink('quietstartForeground') @Watch('syncPulse') foreground: boolean = true;
  private areaVisible: boolean = false;
  private syncPulse(): void { this.setPulsing(this.areaVisible && this.foreground); }
  @Prop rule: LearnedRule = new LearnedRule();
  @Prop positionLabel: string = '';
  @State private markerOpacity: number = 1;
  private pulsing: boolean = false;

  private setPulsing(visible: boolean): void {
    if (visible === this.pulsing) { return; }
    this.pulsing = visible;
    // Native rendering animation; no timer or work in the recognition loop.
    this.getUIContext().animateTo({ duration: 0, iterations: 1 }, () => { this.markerOpacity = 1; });
    if (visible) {
      this.getUIContext().animateTo({ duration: 950, curve: Curve.EaseInOut,
        iterations: -1, playMode: PlayMode.Alternate }, () => { this.markerOpacity = 0.25; });
    }
  }

  aboutToDisappear(): void { this.setPulsing(false); }

  private geometry(): PreviewGeometry {
    const box = this.profile().button;
    return previewGeometry(this.rule.aspect, box.left, box.top, box.right, box.bottom);
  }
  private profile(): RecognitionProfile { return profileForRule(this.rule); }
  private ringSize(): number { return Math.max(10, Math.min(18, Math.max(this.geometry().markerWidth, this.geometry().markerHeight))); }
  private ringLeft(): number { const g = this.geometry(); return Math.max(0, Math.min(g.width - this.ringSize(), g.markerLeft + g.markerWidth / 2 - this.ringSize() / 2)); }
  private ringTop(): number { const g = this.geometry(); return Math.max(0, Math.min(g.height - this.ringSize(), g.markerTop + g.markerHeight / 2 - this.ringSize() / 2)); }
  private markerX(): number { const g = this.geometry(); return g.x + 3 + (this.rule.progressStyle === 'ring' ? this.ringLeft() + this.ringSize() / 2 : g.markerLeft + g.markerWidth / 2); }
  private markerY(): number { const g = this.geometry(); return g.y + 3 + (this.rule.progressStyle === 'ring' ? this.ringTop() + this.ringSize() / 2 : g.markerTop + g.markerHeight / 2); }
  private labelOnRight(): boolean { return this.geometry().labelRight; }
  private labelY(): number { return this.geometry().labelY; }
  private pointer(): string {
    // Path commands use physical pixels; layout and learned coordinates use vp.
    const ui = this.getUIContext();
    const x = ui.vp2px(this.markerX()); const y = ui.vp2px(this.markerY());
    const g = this.geometry();
    const sample = buttonSampleLayout(this.profile(), this.rule.aspect, g.labelWidth, 54);
    const edge = this.labelOnRight() ? Math.min(sample.frame.x - 4, ...sample.parts.map((part) => part.x)) - 3 :
      Math.max(sample.frame.x + sample.frame.width + 4, ...sample.parts.map((part) => part.x + part.width)) + 3;
    const start = ui.vp2px(g.labelX + edge);
    const labelCenter = ui.vp2px(this.labelY() - 14 + sample.frame.y + sample.frame.height / 2);
    const middle = (start + x) / 2;
    return 'M ' + x + ' ' + y + ' C ' + middle + ' ' + y + ' ' + middle + ' ' + labelCenter + ' ' + start + ' ' + labelCenter;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.profile().layers.filter((layer: ProfileLayer) => ['container', 'ad-layer', 'image'].includes(layer.role)).slice(0, 5), (layer: ProfileLayer) => {
            Rect().width((layer.right - layer.left) * this.geometry().width).height((layer.bottom - layer.top) * this.geometry().height)
              .position({ x: layer.left * this.geometry().width, y: layer.top * this.geometry().height })
              .stroke($r('app.color.line')).strokeWidth(0.5).fill(layer.role === 'image' ? $r('app.color.line') : Color.Transparent).radius(1).opacity(0.6)
          })
          // Decorative page structure remains visible even when captured layers
          // contain only the small button area. The marker is always drawn last.
          Rect().width('72%').height(3).fill($r('app.color.line')).radius(2).position({ x: '14%', y: '34%' })
            .id('quietstart-phone-skeleton-title-' + this.rule.key).hitTestBehavior(HitTestMode.None)
          Rect().width('48%').height(3).fill($r('app.color.line')).radius(2).position({ x: '14%', y: '42%' })
            .id('quietstart-phone-skeleton-body-' + this.rule.key).hitTestBehavior(HitTestMode.None)
          if (this.rule.progressStyle === 'ring') {
            Progress({ value: 72, total: 100, type: ProgressType.Ring })
              .width(this.ringSize()).height(this.ringSize()).color($r('app.color.accent'))
              .backgroundColor($r('app.color.line')).style({ strokeWidth: 2 })
              .opacity(this.markerOpacity).position({ x: this.ringLeft(), y: this.ringTop() })
              .id('quietstart-ad-marker-' + this.rule.key)
          } else if (['circle', 'ellipse'].includes(this.profile().shape)) {
            Ellipse().width(this.geometry().markerWidth).height(this.geometry().markerHeight)
              .fill($r('app.color.accent')).opacity(this.markerOpacity)
              .position({ x: this.geometry().markerLeft, y: this.geometry().markerTop })
              .id('quietstart-ad-marker-' + this.rule.key)
          } else {
          Rect().width(this.geometry().markerWidth).height(this.geometry().markerHeight)
            .fill($r('app.color.accent')).radius(this.profile().shape === 'rectangle' ? 0 : this.profile().shape === 'capsule' ? 12 : 2).opacity(this.markerOpacity)
            .position({ x: this.geometry().markerLeft, y: this.geometry().markerTop })
            .id('quietstart-ad-marker-' + this.rule.key)
          }
        }.width(this.geometry().width).height(this.geometry().height).position({ x: 3, y: 3 }).backgroundColor($r('app.color.soft')).borderRadius(9).clip(true)
        Circle().width(4).height(4).fill($r('app.color.ink')).position({ x: (this.geometry().width + 6) / 2 - 2, y: 6 })
          .id('quietstart-phone-camera-' + this.rule.key)
        Rect().width(22).height(2).fill($r('app.color.muted')).radius(1).position({ x: (this.geometry().width + 6 - 22) / 2, y: this.geometry().height - 2 })
      }.id('quietstart-phone-preview-' + this.rule.key).width(this.geometry().width + 6).height(this.geometry().height + 6).position({ x: this.geometry().x, y: this.geometry().y })
        .border({ width: 2, color: $r('app.color.ink') }).borderRadius(13)
        .accessibilityText('按画面比例绘制的位置示意，闪动标记为屏幕' + this.positionLabel + '的广告按钮')
      Path().commands(this.pointer()).width(280).height(154).stroke($r('app.color.muted')).strokeWidth(0.65)
        .opacity(0.55).fill(Color.Transparent).hitTestBehavior(HitTestMode.None)
      Circle().width(3).height(3).fill($r('app.color.accent'))
        .position({ x: this.markerX() - 1.5, y: this.markerY() - 1.5 }).hitTestBehavior(HitTestMode.None)
      ButtonSample({ profile: this.profile(), aspect: this.rule.aspect, sampleWidth: this.geometry().labelWidth, sampleHeight: 54 })
        .id('quietstart-ad-label-' + this.rule.key)
        .position({ x: this.geometry().labelX, y: this.labelY() - 14 })
      Text('广告位置').id('quietstart-ad-caption-' + this.rule.key).fontSize(10).fontColor($r('app.color.muted'))
        .width(72).height(16).textAlign(TextAlign.Center).position({ x: 104, y: 134 })
    }.width(280).height(154)
      .onVisibleAreaChange([0], (visible: boolean) => { this.areaVisible = visible; this.syncPulse(); })
  }
}
