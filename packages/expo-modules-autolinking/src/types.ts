export type Platform = 'harmony';
export type BuildType = 'debug' | 'release';
export type ModuleSource
  = 'dependency'
    | 'searchPath'
    | 'nativeModulesDir'
    | 'reactNativeProjectConfig';

export interface ProviderDescriptor {
  readonly identifier: string;
  readonly header: string;
  readonly className: string;
  readonly cmakeTargetName: string;
  readonly debugOnly: boolean;
}

export interface ProviderHar {
  /** Package-relative HAR that exports every declared Provider header and CMake target. */
  readonly harPath: string;
  /** OH package name under which the Provider HAR is installed. */
  readonly ohPackageName: string;
}

export interface HostMetadata {
  readonly abilityLifecycleSubscribers: ReadonlyArray<string>;
  readonly reactInstanceLifecycleListeners: ReadonlyArray<string>;
  readonly rootViewComponents: ReadonlyArray<string>;
}

export type ExpoMetadata = HostMetadata & {
  readonly providerHar?: undefined;
  readonly providers: readonly [];
} | HostMetadata & {
  readonly providerHar: ProviderHar;
  readonly providers: readonly [ProviderDescriptor, ...ProviderDescriptor[]];
};

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
  readonly cppPackageClassName?: string;
  readonly cmakeLibraryTargetName?: string;
}

export interface ModuleDescriptor {
  readonly packageName: string;
  readonly packageVersion: string;
  readonly packageRoot: string;
  /** Reachable npm package path used for build-time local HAR fallback. */
  readonly packageLinkPath: string;
  readonly source: ModuleSource;
  /** Provider arrays are non-empty only when their source HAR and SPI are present. */
  readonly expo: ExpoMetadata;
  readonly rnoh: RnohMetadata;
}

export interface SearchRecord {
  readonly packageName: string;
  readonly packageVersion: string;
  readonly packageRoot: string;
  readonly source: ModuleSource;
  readonly supportsHarmony: boolean;
  readonly expoModuleConfig: Readonly<Record<string, unknown>> | null;
  readonly rnohMetadata: unknown;
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
  readonly schemaVersion: 3;
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
}

export interface ResolveOptions extends SearchOptions {
  searchResult?: SearchResult;
}

export interface VerifyOptions extends ResolveOptions {
  modules?: ReadonlyArray<ModuleDescriptor>;
}

export interface ProviderWriteOptions extends VerifyOptions {
  target: string;
  packages?: ReadonlyArray<string>;
}

export interface ProviderWriteResult {
  readonly sourcePath: string;
  readonly cmakePath: string;
  readonly providerCount: number;
  readonly buildType: BuildType;
}

export interface LinkOptions extends VerifyOptions {
  projectRoot: string;
  harmonyProjectPath: string;
  nodeModulesPath?: string;
  reactNativeExecutable?: string;
  rnohCliPackageJsonPath?: string;
  timeoutMs?: number;
  outputLimit?: number;
  env?: NodeJS.ProcessEnv;
}

export interface LinkResult {
  readonly platform: Platform;
  readonly modules: ReadonlyArray<ModuleDescriptor>;
  readonly providerCount: number;
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
