import { HarmonyConfigPluginError, type HarmonyConfigPluginErrorOptions } from '@expo-harmony/config-plugins';

export class HarmonyPatchError extends HarmonyConfigPluginError {
  constructor(code: string, message: string, options: HarmonyConfigPluginErrorOptions = {}) {
    super(code, message, { operation: 'patch-project', ...options });

    this.name = 'HarmonyPatchError';
  }
}
