interface LaunchSkill { actions?: string[]; entities?: string[]; }
interface LaunchAbility { name: string; visible?: boolean; enabled?: boolean; type?: number; skills?: LaunchSkill[]; }
interface LaunchModule { moduleName: string; mainAbility?: string; mainElementName?: string; abilityInfos?: LaunchAbility[]; }
interface LaunchBundle { name: string; entryModuleName?: string; hapModuleInfos?: LaunchModule[]; }

// Resolve the declared native entry, not a guessed EntryAbility or an implicit
// home skill that may also require a URI. Desktop folders do not affect it.
export function nativeLaunchCommand(text: string, bundle: string): string {
  if (!/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/.test(bundle) || text.length > 4 * 1024 * 1024) { return ''; }
  try {
    const info = JSON.parse(text.substring(text.indexOf('{'))) as LaunchBundle;
    if (info.name !== bundle || !Array.isArray(info.hapModuleInfos)) { return ''; }
    const commands: string[] = [];
    for (const module of info.hapModuleInfos) {
      if (!/^[A-Za-z0-9_.]+$/.test(module.moduleName)) { continue; }
      for (const ability of module.abilityInfos ?? []) {
        if (ability.visible !== true || ability.enabled === false || ability.type !== 1 || !/^[A-Za-z0-9_.]+$/.test(ability.name)) { continue; }
        const main = module.moduleName === info.entryModuleName &&
          ability.name === (module.mainElementName || module.mainAbility);
        const home = (ability.skills ?? []).some((skill: LaunchSkill) =>
          (skill.entities ?? []).includes('entity.system.home') &&
          (skill.actions ?? []).some((action: string) => ['action.system.home', 'ohos.want.action.home'].includes(action)));
        if (main || home) {
          const command = 'aa start -b ' + bundle + ' -m ' + module.moduleName + ' -a ' + ability.name;
          if (main) { return command; }
          commands.push(command);
        }
      }
    }
    return commands.length === 1 ? commands[0] : '';
  } catch (_) { return ''; }
}
