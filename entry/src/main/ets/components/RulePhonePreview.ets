import { PreviewGeometry, previewGeometry } from '../core/PreviewGeometry';
import { LearnedRule } from '../core/LearningStore';

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

  private geometry(): PreviewGeometry { return previewGeometry(this.rule.aspect, this.rule.left, this.rule.top, this.rule.right, this.rule.bottom); }
  private ringSize(): number { return Math.max(10, Math.min(18, Math.max(this.geometry().markerWidth, this.geometry().markerHeight))); }
  private ringLabel(): string { return /关闭/.test(this.rule.label) ? '关闭' : this.rule.label === '×' ? '×' : /skip/i.test(this.rule.label) ? 'Skip' : '跳过'; }
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
    const start = ui.vp2px(this.labelOnRight() ? g.labelX - 3 : g.labelX + g.labelWidth + 3);
    const labelCenter = ui.vp2px(this.labelY() + 13);
    const middle = (start + x) / 2;
    return 'M ' + x + ' ' + y + ' C ' + middle + ' ' + y + ' ' + middle + ' ' + labelCenter + ' ' + start + ' ' + labelCenter;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.TopStart }) {
          Rect().width('72%').height(3).fill($r('app.color.line')).radius(2).position({ x: '14%', y: '34%' })
          Rect().width('48%').height(3).fill($r('app.color.line')).radius(2).position({ x: '14%', y: '42%' })
          if (this.rule.progressStyle === 'ring') {
            Progress({ value: 72, total: 100, type: ProgressType.Ring })
              .width(this.ringSize()).height(this.ringSize()).color($r('app.color.accent'))
              .backgroundColor($r('app.color.line')).style({ strokeWidth: 2 })
              .opacity(this.markerOpacity).position({ x: this.ringLeft(), y: this.ringTop() })
              .id('quietstart-ad-marker-' + this.rule.key)
          } else {
          Rect().width(this.geometry().markerWidth).height(this.geometry().markerHeight)
            .fill($r('app.color.accent')).radius(2).opacity(this.markerOpacity)
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
      if (this.rule.progressStyle === 'ring') {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(37).height(37).fill($r('app.color.soft'))
          Progress({ value: 72, total: 100, type: ProgressType.Ring }).width(40).height(40)
            .color($r('app.color.accent')).backgroundColor($r('app.color.line')).style({ strokeWidth: 2 })
          Text(this.ringLabel()).fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent')).textAlign(TextAlign.Center).width(32).maxLines(1)
            .id('quietstart-ad-label-' + this.rule.key)
        }.width(40).height(40).position({
          x: this.labelOnRight() ? this.geometry().labelX : this.geometry().labelX + this.geometry().labelWidth - 40,
          y: this.labelY() - 7
        })
      } else {
      Row({ space: 4 }) {
        Text(this.rule.example || this.rule.label).id('quietstart-ad-label-' + this.rule.key)
          .fontSize(11).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent')).textAlign(TextAlign.Center)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: this.geometry().labelWidth }).height(26)
          .padding({ left: 9, right: 9 }).borderRadius(13).border({ width: 0.5, color: $r('app.color.line') })
          .backgroundColor($r('app.color.soft'))
      }.width(this.geometry().labelWidth).height(26).justifyContent(this.labelOnRight() ? FlexAlign.Start : FlexAlign.End)
        .position({ x: this.geometry().labelX, y: this.labelY() })
      }
      Text('广告位置').id('quietstart-ad-caption-' + this.rule.key).fontSize(10).fontColor($r('app.color.muted'))
        .width(72).height(16).textAlign(TextAlign.Center).position({ x: 104, y: 134 })
    }.width(280).height(154)
      .onVisibleAreaChange([0], (visible: boolean) => { this.areaVisible = visible; this.syncPulse(); })
  }
}
