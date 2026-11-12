/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { HarmonyNativeModule } from '../runtime';

export type Platform = 'harmony';
export type BuildType = 'debug' | 'release';
export type ModuleSource
  = 'dependency'
    | 'searchPath'
    | 'nativeModulesDir'
    | 'reactNativeProjectConfig'
    | 'inlineModules';

export interface InlineModulesOptions {
  readonly watchedDirectories: ReadonlyArray<string>;
  readonly targets?: ReadonlyArray<string>;
}

export interface InlineModuleFile {
  readonly path: string;
  readonly modules: ReadonlyArray<{ readonly name: string; readonly default: boolean }>;
}

export interface InlineModulesDescriptor {
  readonly watchedDirectories: ReadonlyArray<string>;
  readonly files: ReadonlyArray<InlineModuleFile>;
}

export interface ArkTsModulePackage {
  readonly harPath: string;
  readonly ohPackageName: string;
  readonly builtHarPath?: string;
}

export interface HostMetadata {
  readonly rootViewComponents: ReadonlyArray<string>;
  readonly appLifecycleSubscribers: ReadonlyArray<string>;
  readonly abilityLifecycleSubscribers: ReadonlyArray<string>;
  readonly reactNativeHostHandlers: ReadonlyArray<string>;
  readonly reactActivityHandlers: ReadonlyArray<string>;
  readonly runtimeBindings: ReadonlyArray<string>;
}

export type ExpoMetadata = HostMetadata;

export interface RnohMetadata {
  readonly ohPackageName?: string | ReadonlyArray<{
    readonly harName: string;
    readonly packageName: string;
    readonly version?: string;
  }>;
  readonly mainHarPath?: string;
  readonly harPaths: ReadonlyArray<string>;
  readonly etsPackageClassName?: string;
  readonly etsPackageImport?: 'default' | 'named';
  readonly etsPackageScope?: 'shared' | 'ui' | 'host';
  readonly cppPackageClassName?: string;
  readonly cmakeLibraryTargetName?: string;
}

export interface HarmonyModuleMetadata extends HostMetadata {
  readonly buildOptionsFile?: string;
  readonly modules: ReadonlyArray<string>;
  readonly services: ReadonlyArray<string>;
}

export interface FixedHvigorBuildDescriptor {
  readonly executable: 'hvigorw';
  readonly cwd: string;
  readonly args: ReadonlyArray<string>;
}

export type ModuleArtifactDescriptor = {
  readonly kind: 'bundled';
  readonly harPaths: ReadonlyArray<string>;
} | {
  readonly kind: 'local-source';
  readonly outputPath: string;
  readonly materialized: false;
  readonly build: FixedHvigorBuildDescriptor;
};

export interface ModuleDescriptor {
  readonly packageName: string;
  readonly packageVersion: string;
  readonly packageRoot: string;
  readonly packageLinkPath: string;
  readonly source: ModuleSource;
  readonly expo: ExpoMetadata;
  readonly rnoh: RnohMetadata;
  readonly harmony: HarmonyModuleMetadata;
  readonly arkTs?: ArkTsModulePackage;
  readonly artifact: ModuleArtifactDescriptor;
  readonly inlineModules?: InlineModulesDescriptor;
}

export interface SearchRecord {
  readonly packageName: string;
  readonly packageVersion: string;
  readonly packageRoot: string;
  readonly source: ModuleSource;
  readonly supportsHarmony: boolean;
  readonly expoModuleConfig: Readonly<Record<string, unknown>> | null;
  readonly rnohMetadata: unknown;
  readonly inlineModules?: InlineModulesDescriptor;
  readonly revision: {
    readonly depth: number | null;
    readonly originPath: string;
  };
}

export interface SearchResult {
  readonly platform: Platform;
  readonly modules: ReadonlyArray<SearchRecord>;
  readonly duplicates: ReadonlyArray<{
    readonly packageName: string;
    readonly revisions: ReadonlyArray<{ readonly version: string; readonly path: string }>;
  }>;
  readonly missingIncludes: ReadonlyArray<string>;
  readonly options: {
    readonly projectRoot: string;
    readonly searchPaths: ReadonlyArray<string>;
    readonly nativeModulesDir: string | null;
    readonly exclude: ReadonlyArray<string>;
    readonly include: ReadonlyArray<string>;
    readonly buildType: BuildType;
  };
}

export interface DiagnosticSource {
  readonly packageName: string;
  readonly packageVersion: string;
  readonly packageRoot: string;
  readonly field?: string;
}

export interface Diagnostic {
  readonly severity: 'error' | 'warning';
  readonly code: string;
  readonly message: string;
  readonly packageName?: string;
  readonly stage: string;
  readonly sources?: ReadonlyArray<DiagnosticSource>;
}

export interface VerificationResult {
  readonly valid: boolean;
  readonly diagnostics: ReadonlyArray<Diagnostic>;
  readonly modules: ReadonlyArray<ModuleDescriptor>;
}

export interface Manifest {
  readonly schemaVersion: 4;
  readonly runtimeModules?: readonly HarmonyNativeModule[];
  readonly platform: 'harmony';
  readonly buildType: BuildType;
  readonly modules: ReadonlyArray<ModuleDescriptor>;
  readonly managedArtifacts: ReadonlyArray<string>;
}

export interface CanonicalizeAutolinkingArtifactsOptions {
  readonly manifestSource: string;
  readonly ohPackageSource: string;
  readonly generatedProjectRoot: string;
  readonly canonicalProjectRoot: string;
  readonly harmonyProjectPath?: string;
}

export interface CanonicalizedAutolinkingArtifacts {
  readonly manifest: Manifest;
  readonly manifestSource: string;
  readonly ohPackageSource: string;
}

export interface Logger {
  debug?(message: string, details?: unknown): void;
  info?(message: string, details?: unknown): void;
  warn?(message: string, details?: unknown): void;
  error?(message: string, details?: unknown): void;
}

export interface SearchOptions {
  projectRoot?: string;
  platform?: Platform;
  searchPaths?: ReadonlyArray<string>;
  nativeModulesDir?: string | null;
  exclude?: ReadonlyArray<string>;
  include?: ReadonlyArray<string>;
  buildType?: BuildType;
  logger?: Logger;
  inlineModules?: InlineModulesOptions | null | false;
}

export interface ResolveOptions extends SearchOptions {
  searchResult?: SearchResult;
}

export interface VerifyOptions extends ResolveOptions {
  modules?: ReadonlyArray<ModuleDescriptor>;
}

export interface LinkOptions extends VerifyOptions {
  projectRoot: string;
  harmonyProjectPath: string;
  /** Effective Expo experiment supplied by prebuild. Null represents a disabled experiment. */
  expoInlineModules?: InlineModulesOptions | null;
  moduleBuilds?: Record<string, Record<string, string | number | boolean>>;
  moduleBuildSettings?: { compatibleSdkVersion: string; targetSdkVersion: string; abiFilters: string[] };
  nodeModulesPath?: string;
  reactNativeExecutable?: string;
  rnohCliPackageJsonPath?: string;
  timeoutMs?: number;
  outputLimit?: number;
  env?: NodeJS.ProcessEnv;
}

export interface MaterializeLocalSourceOptions {
  readonly dependencies?: ReadonlyArray<ModuleDescriptor>;
  readonly projectRoot: string;
  readonly module: ModuleDescriptor;
  readonly timeoutMs?: number;
  readonly outputLimit?: number;
  readonly env?: NodeJS.ProcessEnv;
}

export interface MaterializedLocalSource {
  readonly packageName: string;
  readonly harPath: string;
  readonly builtHarPath: string;
}

export interface LinkResult {
  readonly platform: Platform;
  readonly modules: ReadonlyArray<ModuleDescriptor>;
  readonly buildType: BuildType;
  readonly managedArtifacts: ReadonlyArray<string>;
  readonly changedArtifacts: ReadonlyArray<string>;
  readonly unchangedArtifacts: ReadonlyArray<string>;
  readonly diagnostics: ReadonlyArray<Diagnostic>;
  readonly warnings: ReadonlyArray<Diagnostic>;
}

export interface AutolinkingErrorJson {
  readonly name: 'HarmonyAutolinkingError';
  readonly code: string;
  readonly message: string;
  readonly stage: string;
  readonly packageName?: string;
  readonly diagnostics?: ReadonlyArray<Diagnostic>;
  readonly details?: unknown;
}
