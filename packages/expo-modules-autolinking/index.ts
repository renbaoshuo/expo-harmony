import { linkModulesAsync } from './src/autolinking/link';
import { canonicalizeAutolinkingArtifacts } from './src/harmony/persistence/canonicalize';
import { resolveModulesAsync } from './src/autolinking/resolve';
import { searchModulesAsync } from './src/autolinking/search';
import { verifyModulesAsync } from './src/autolinking/verify';
import { normalizeHarmonyModuleMetadata } from './src/metadata/schema';

export {
  canonicalizeAutolinkingArtifacts,
  linkModulesAsync,
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
