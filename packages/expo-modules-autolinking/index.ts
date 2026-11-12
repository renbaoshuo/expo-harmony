/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { linkModulesAsync, linkPreparedModulesAsync } from './src/autolinking/link';
import { prepareModulesAsync, prepareRuntimeModulesAsync } from './src/autolinking/prepare';
import { canonicalizeAutolinkingArtifacts } from './src/harmony/persistence/canonicalize';
import { resolveModulesAsync } from './src/autolinking/resolve';
import { searchModulesAsync } from './src/autolinking/search';
import { verifyModulesAsync } from './src/autolinking/verify';
import { normalizeHarmonyModuleMetadata } from './src/metadata/schema';

export {
  canonicalizeAutolinkingArtifacts,
  linkModulesAsync,
  linkPreparedModulesAsync,
  prepareModulesAsync,
  prepareRuntimeModulesAsync,
  normalizeHarmonyModuleMetadata,
  resolveModulesAsync,
  searchModulesAsync,
  verifyModulesAsync,
};

export type {
  BuildType,
  CanonicalizeAutolinkingArtifactsOptions,
  CanonicalizedAutolinkingArtifacts,
  Diagnostic,
  DiagnosticSource,
  ExpoMetadata,
  HostMetadata,
  HarmonyModuleMetadata,
  InlineModulesOptions,
  InlineModulesDescriptor,
  InlineModuleFile,
  LinkOptions,
  LinkResult,
  Logger,
  Manifest,
  ModuleDescriptor,
  ModuleArtifactDescriptor,
  ModuleSource,
  Platform,
  ResolveOptions,
  RnohMetadata,
  SearchOptions,
  SearchRecord,
  SearchResult,
  VerificationResult,
  VerifyOptions,
} from './src/types';

export { createNativeModuleContracts } from './src/harmony/manifest/runtime';
export { GeneratedNativeSources, ManifestArtifact, ModuleBuildOptionsArtifact } from './src/config/constants';
export { localOhpmDependenciesFromManifest, ohpmDependenciesFromManifest } from './src/harmony/manifest';
export { resolveBundledRnohRuntime } from './src/harmony/ohpm/dependencies';
export { resolveRnohCliPackageJsonPath } from './src/harmony/rnoh/cli';
