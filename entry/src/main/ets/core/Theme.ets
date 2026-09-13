import { ConfigurationConstant } from '@kit.AbilityKit';

export function themeColorMode(mode: string): ConfigurationConstant.ColorMode {
  if (mode === 'light') { return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT; }
  if (mode === 'dark') { return ConfigurationConstant.ColorMode.COLOR_MODE_DARK; }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}

export function themeIsDark(mode: string, effectiveMode?: number): boolean {
  if (mode === 'light') { return false; }
  if (mode === 'dark') { return true; }
  return effectiveMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
}
