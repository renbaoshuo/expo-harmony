import { HarmonyAutolinkingError } from './src/errors';
import { writeProviderArtifactsAsync } from './src/harmony/providers/artifacts';
import { linkModulesAsync } from './src/autolinking/link';
import { localOhpmDependenciesFromManifest, ohpmDependenciesFromManifest, readManifestAsync, validateManifest } from './src/harmony/manifest';
import { resolveModulesAsync } from './src/autolinking/resolve';
import { searchModulesAsync } from './src/autolinking/search';
import { verifyModulesAsync } from './src/autolinking/verify';

export {
  HarmonyAutolinkingError,
  writeProviderArtifactsAsync,
  linkModulesAsync,
  localOhpmDependenciesFromManifest,
  ohpmDependenciesFromManifest,
  readManifestAsync,
  resolveModulesAsync,
  searchModulesAsync,
  validateManifest,
  verifyModulesAsync,
};

export type {
  AutolinkingErrorJson,
  BuildType,
  Diagnostic,
  DiagnosticSource,
  ExpoMetadata,
  HostMetadata,
  LinkOptions,
  LinkResult,
  Logger,
  Manifest,
  ModuleDescriptor,
  ModuleSource,
  Platform,
  ProviderDescriptor,
  ProviderHar,
  ProviderWriteOptions,
  ProviderWriteResult,
  ResolveOptions,
  RnohMetadata,
  SearchOptions,
  SearchRecord,
  SearchResult,
  VerificationResult,
  VerifyOptions,
} from './src/types';
