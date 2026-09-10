export { defineExpoHarmonyConfig } from './config';
export { createRunOncePlugin, withPlugins, withRunOnce, withStaticPlugin } from './composition';
export type { HarmonyPluginReference, HarmonyStaticPlugin } from './composition';
export { compileHarmonyModsAsync } from './compiler';
export type { HarmonyCompileOptions } from './compiler';
export { createHarmonyFileMod, withHarmonyJsonFile } from './customFiles';
export type { HarmonyFileModOptions, HarmonyJsonFileOptions } from './customFiles';
export type {
  ExpoConfigWithHarmony,
  ExpoHarmonyPlatform,
  ExpoKnownPlatform,
  HarmonyConfig,
  HarmonyDeviceType,
  HarmonyOrientation,
  HarmonyPermission,
  HarmonyPlatform,
  HarmonySkill,
  HarmonySkillUri,
} from './config';
export { HarmonyConfigPluginError } from './errors';
export type { HarmonyConfigPluginErrorOptions } from './errors';
export { atomicWrite, stableJson as stableHarmonyJson } from './files';
export { normalizeHarmonyConfig } from './normalizeConfig';
export type { HarmonyExpoConfig, NormalizedHarmonyConfig } from './normalizeConfig';
export {
  HarmonyModNames as HARMONY_MOD_NAMES,
  recordManagedFile,
  withAppJson,
  withArkTSPackageProvider,
  withCMakeLists,
  withColors,
  withCppPackageProvider,
  withEntryAbility,
  withEntryBuildProfile,
  withEntryHvigor,
  withEntryOhPackage,
  withHarmonyAutolinking,
  withHarmonyBaseMods,
  withHarmonyDangerousMod,
  withHarmonyMod,
  withHarmonyResources,
  withHvigorConfig,
  withIndexPage,
  withMedia,
  withModuleJson,
  withProfiles,
  withProjectBuildProfile,
  withReactNativeConfig,
  withRootHvigor,
  withRootOhPackage,
  withStrings,
  withWorker,
} from './mods';
export type {
  HarmonyJson,
  HarmonyMediaDescriptor,
  HarmonyMediaMap,
  HarmonyModName,
  HarmonyResourceMap,
} from './mods';
export { registerHarmonyConfigPlugin } from './ownership';
export type { HarmonyConfigPluginOwnership } from './ownership';
export { HarmonyPaths } from './paths';
export type {
  HarmonyManagedPaths,
  HarmonyPathsApi,
  HarmonyProjectPathCandidates,
  HarmonyProjectPaths,
  HarmonyResourcePaths,
} from './paths';

export type { HarmonyConfigPlugin, HarmonyModAction, HarmonyModConfig } from './pluginTypes';
export * as HarmonyManifest from './manifest';
export * as HarmonyResources from './resources';
export type { HarmonyAbility, HarmonyExtensionAbility, HarmonyMetadata, HarmonyModule, HarmonyModuleJson } from './manifest';
export type { HarmonyResourceFile, HarmonyResourceItem } from './resources';
export { withHarmonyGeneratedFiles, withRawfile } from './generatedFiles';
export type { HarmonyFileDescriptor, HarmonyFileMap, HarmonyGeneratedFilesOptions } from './generatedFiles';
export { HarmonyPermissions, withHarmonyPermissions } from './permissions';
