import { ButtonPart, ProfileBox, RecognitionProfile } from './RecognitionProfile';
export class SampleBox { x: number = 0; y: number = 0; width: number = 0; height: number = 0; }
export class SamplePart extends SampleBox { role: string = ''; text: string = ''; fontSize: number = 11; }
export class ButtonSampleLayout {
  frame: SampleBox = new SampleBox(); parts: SamplePart[] = [];
}
// Native text bounds include invisible vertical padding. Compact a single text
// row only in the enlarged sample; retain the captured positions and hit bounds.
function isTextRow(profile: RecognitionProfile): boolean {
  if (['circle', 'ellipse'].includes(profile.shape) || profile.parts.length === 0 ||
    profile.parts.some((p: ButtonPart) => !['text', 'countdown'].includes(p.role) || !p.text || /[\r\n]/.test(p.text))) { return false; }
  const commonTop = Math.max(...profile.parts.map((p: ButtonPart) => p.top));
  const commonBottom = Math.min(...profile.parts.map((p: ButtonPart) => p.bottom));
  const minHeight = Math.min(...profile.parts.map((p: ButtonPart) => p.bottom - p.top));
  return commonBottom - commonTop >= minHeight * 0.5;
}
// Keep one transform for all parts so order and overlay relationships survive.
export function buttonSampleLayout(profile: RecognitionProfile, aspect: number, width: number, height: number): ButtonSampleLayout {
  const result = new ButtonSampleLayout();
  const ratio = Number.isFinite(aspect) && aspect > 0 ? aspect : 0.62;
  const boxes: ProfileBox[] = [profile.button, ...profile.parts];
  const left = Math.min(...boxes.map((b: ProfileBox) => b.left)); const top = Math.min(...boxes.map((b: ProfileBox) => b.top));
  const right = Math.max(...boxes.map((b: ProfileBox) => b.right)); const bottom = Math.max(...boxes.map((b: ProfileBox) => b.bottom));
  const spanX = Math.max(0.001, (right - left) * ratio); const spanY = Math.max(0.001, bottom - top);
  const scale = Math.min((width - 12) / spanX, (height - 12) / spanY,
    36 / spanY, 56 / spanX);
  const scaleY = isTextRow(profile) ? Math.min(scale, 18 / spanY) : scale;
  const offsetX = (width - spanX * scale) / 2; const offsetY = (height - spanY * scaleY) / 2;
  const project = (box: ProfileBox): SampleBox => ({ x: offsetX + (box.left - left) * ratio * scale,
    y: offsetY + (box.top - top) * scaleY, width: (box.right - box.left) * ratio * scale, height: (box.bottom - box.top) * scaleY });
  result.frame = project({ left: left, top: top, right: right, bottom: bottom });
  result.parts = profile.parts.map((part: ButtonPart): SamplePart => {
    const box = project(part);
    const size = Math.max(6, Math.min(11, box.height * 0.8, (box.width + 2) / Math.max(1, part.text.length)));
    return { x: box.x, y: box.y, width: box.width, height: box.height, role: part.role, text: part.text, fontSize: size };
  });
  return result;
}
