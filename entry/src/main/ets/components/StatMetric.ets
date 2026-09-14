@Component
export struct StatMetric {
  @Prop value: string = '';
  @Prop label: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.value).fontSize(23).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
        .width('100%').textAlign(TextAlign.Center)
      Text(this.label).fontSize(11).fontColor($r('app.color.muted')).width('100%').textAlign(TextAlign.Center)
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
  }
}
