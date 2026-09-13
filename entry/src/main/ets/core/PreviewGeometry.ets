export class PreviewGeometry {
  width: number = 66;
  height: number = 104;
  x: number = 104;
  y: number = 16;
  markerWidth: number = 5.28;
  markerHeight: number = 3.12;
  markerLeft: number = 0;
  markerTop: number = 0;
  labelRight: boolean = true;
  labelWidth: number = 90;
  labelX: number = 190;
  labelY: number = 0;
}

export function previewGeometry(aspect: number, left: number, top: number, right: number, bottom: number): PreviewGeometry {
  const g = new PreviewGeometry();
  const ratio = Number.isFinite(aspect) && aspect > 0 && aspect < 5 ? aspect : 66 / 104;
  g.width = Math.min(132, 104 * ratio); g.height = g.width / ratio;
  g.x = (280 - g.width - 6) / 2; g.y = 16 + (104 - g.height) / 2;
  // Enlarge tiny targets around their actual centre, then keep the whole mark on screen.
  const cx = Math.max(0, Math.min(1, (left + right) / 2));
  const cy = Math.max(0, Math.min(1, (top + bottom) / 2));
  g.markerWidth = Math.min(g.width, Math.max(5.28, g.width * Math.max(0.08, right - left)));
  g.markerHeight = Math.min(g.height, Math.max(3.12, g.height * Math.max(0.03, bottom - top)));
  g.markerLeft = Math.max(0, Math.min(g.width - g.markerWidth, cx * g.width - g.markerWidth / 2));
  g.markerTop = Math.max(0, Math.min(g.height - g.markerHeight, cy * g.height - g.markerHeight / 2));
  g.labelRight = cx >= 0.5;
  g.labelWidth = Math.min(90, g.x - 10);
  g.labelX = g.labelRight ? g.x + g.width + 16 : g.x - 10 - g.labelWidth;
  g.labelY = Math.max(0, Math.min(106, g.y + 3 + g.markerTop + g.markerHeight / 2 - 13));
  return g;
}
