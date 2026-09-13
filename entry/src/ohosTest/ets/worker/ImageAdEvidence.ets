import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Driver, Rect } from '@kit.TestKit';

// Only strict standalone advertising labels qualify, never a substring of page copy.
function hasAdLabel(result: textRecognition.TextRecognitionResult): boolean {
  const matches = (value: string): boolean => /^(广告|ad|ads|advertisement)$/i.test(value.replace(/[\s\u200b\ufeff]/g, ''));
  return matches(result.value) || (result.blocks ?? []).some((block: textRecognition.TextBlock) =>
    matches(block.value) || (block.lines ?? []).some((line: textRecognition.TextLine) => matches(line.value)));
}

// A bounded crop within a candidate splash layer, including large artwork fallback.
export async function readImageAd(driver: Driver, directory: string, bounds: Rect): Promise<boolean> {
  const path = directory + '/ad-marker-crop.png';
  let source: image.ImageSource | undefined;
  let pixels: image.PixelMap | undefined;
  try {
    if (!await driver.screenCapture(path, bounds)) { return false; }
    source = image.createImageSource(path);
    const scale = Math.min(2, 1280 / Math.max(bounds.right - bounds.left, bounds.bottom - bounds.top));
    pixels = await source.createPixelMap({ desiredSize: { width: Math.round((bounds.right - bounds.left) * scale),
      height: Math.round((bounds.bottom - bounds.top) * scale) }, editable: true, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    try {
      const result = await textRecognition.recognizeText({ pixelMap: pixels });
      if (hasAdLabel(result)) { return true; }
    } catch (_) {}
    // A pale bitmap badge can be legible to people but fail the default OCR pass.
    // One bounded local contrast pass; no additional screenshot or cloud request.
    const info = await pixels.getImageInfo();
    const buffer = new ArrayBuffer(info.size.width * info.size.height * 4);
    await pixels.readPixelsToBuffer(buffer);
    const data = new Uint8Array(buffer);
    let low = 255; let high = 0; let total = 0;
    for (let i = 0; i < data.length; i += 4) {
      const alpha = data[i + 3] / 255;
      const gray = Math.round((data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) * alpha + 255 * (1 - alpha));
      data[i] = gray; low = Math.min(low, gray); high = Math.max(high, gray); total += gray;
    }
    if (high - low < 3) { return false; }
    const invert = (total / (data.length / 4) - low) / (high - low) < 0.5;
    for (let i = 0; i < data.length; i += 4) {
      const value = Math.round((data[i] - low) * 255 / (high - low));
      const gray = invert ? 255 - value : value;
      data[i] = gray; data[i + 1] = gray; data[i + 2] = gray; data[i + 3] = 255;
    }
    await pixels.writeBufferToPixels(buffer);
    const enhanced = await textRecognition.recognizeText({ pixelMap: pixels });
    return hasAdLabel(enhanced);
  } finally {
    try { if (pixels) { await pixels.release(); } } catch (_) {}
    try { if (source) { source.release(); } } catch (_) {}
    try { fs.unlinkSync(path); } catch (_) {}
  }
}
