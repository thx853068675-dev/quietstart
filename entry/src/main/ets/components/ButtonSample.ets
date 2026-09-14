import { RecognitionProfile } from '../core/RecognitionProfile';
import { ButtonSampleLayout, SamplePart, buttonSampleLayout } from '../core/ButtonPreviewLayout';

@Component
export struct ButtonSample {
  @Prop profile: RecognitionProfile = new RecognitionProfile();
  @Prop aspect: number = 0.62;
  @Prop sampleWidth: number = 84;
  @Prop sampleHeight: number = 58;
  private layout(): ButtonSampleLayout { return buttonSampleLayout(this.profile, this.aspect, this.sampleWidth, this.sampleHeight); }
  private radius(): number {
    if (this.profile.shape === 'rectangle') { return 0; }
    if (['circle', 'ellipse', 'capsule'].includes(this.profile.shape)) { return Math.max(this.layout().frame.width, this.layout().frame.height); }
    return Math.min(7, this.layout().frame.height / 3);
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.profile.shape === 'ellipse' || this.profile.shape === 'circle') {
        Ellipse().width(this.layout().frame.width + 8).height(this.layout().frame.height + 8)
          .position({ x: this.layout().frame.x - 4, y: this.layout().frame.y - 4 })
          .fill($r('app.color.soft')).stroke($r('app.color.line')).strokeWidth(0.6)
      } else {
      Row().width(this.layout().frame.width + 8).height(this.layout().frame.height + 8)
        .position({ x: this.layout().frame.x - 4, y: this.layout().frame.y - 4 })
        .borderRadius(this.radius()).backgroundColor(this.profile.shape === 'borderless' ? Color.Transparent : $r('app.color.soft'))
        .border({ width: this.profile.shape === 'borderless' ? 0 : 0.6, color: $r('app.color.line'),
          style: BorderStyle.Solid })
      }
      ForEach(this.layout().parts, (part: SamplePart) => {
        if (part.role === 'outline') {
          Circle().width(part.width).height(part.height).position({ x: part.x, y: part.y })
            .fill(Color.Transparent).stroke($r('app.color.accent')).strokeWidth(1.5)
        } else if (part.role === 'progress') {
          Progress({ value: 72, total: 100, type: part.text === 'ring' ? ProgressType.Ring : ProgressType.Linear })
            .width(part.width).height(part.height).position({ x: part.x, y: part.y })
            .color($r('app.color.accent')).backgroundColor($r('app.color.line')).style({ strokeWidth: 1.5 })
        } else if (part.role === 'icon' && !part.text) {
          // An unknown image remains a schematic image, never a fabricated ×.
          Rect().width(Math.min(12, part.width)).height(Math.min(12, part.height)).radius(2)
            .stroke($r('app.color.accent')).strokeWidth(1).fill(Color.Transparent)
            .position({ x: part.x + (part.width - Math.min(12, part.width)) / 2, y: part.y + (part.height - Math.min(12, part.height)) / 2 })
        } else {
          Text(part.text).fontSize(part.fontSize).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent'))
            .textAlign(TextAlign.Center).width(part.width + 2).height(part.height + 2).maxLines(1)
            .position({ x: part.x - 1, y: part.y - 1 })
        }
      })
    }.width(this.sampleWidth).height(this.sampleHeight).hitTestBehavior(HitTestMode.None)
  }
}
