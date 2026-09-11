export interface ExpoConstantsOptions {
  manifest?: string;
  executionEnvironment?: 'bare' | 'standalone' | 'storeClient';
  appOwnership?: 'expo' | 'guest' | 'standalone' | null;
  linkingUri?: string;
  experienceUrl?: string;
  isHeadless?: boolean;
}

export class ExpoConstantsConfig {
  readonly manifest?: string;
  readonly executionEnvironment: string;
  readonly appOwnership: string | null;
  readonly linkingUri?: string;
  readonly experienceUrl?: string;
  readonly isHeadless: boolean;

  constructor(options: ExpoConstantsOptions = {}) {
    if (options.manifest !== undefined) {
      const manifest: ESObject = JSON.parse(options.manifest);
      if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest)) throw new Error('Expo manifest must be a JSON object.');
      this.manifest = JSON.stringify(manifest);
    }

    this.executionEnvironment = options.executionEnvironment ?? 'bare';
    this.appOwnership = options.appOwnership ?? null;
    this.linkingUri = options.linkingUri;
    this.experienceUrl = options.experienceUrl;
    this.isHeadless = options.isHeadless ?? false;
  }
}
