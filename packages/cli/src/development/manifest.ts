import crypto from 'node:crypto';
import { createRequire } from 'node:module';

import { resolveExpoCli } from '../expo';
import { resolveHarmonyBuildPlanAsync } from '../native/project';
import { resolveRuntimeRequirementsAsync } from '../runtime/contract';
import { canonicalHarmonyManifestURL, createHarmonyLaunchLink, HarmonyManifestPath } from './protocol';

async function createManifestResponseAsync(middleware, options, require: NodeRequire) {
  const { ExpoGoManifestHandlerMiddleware: Manifest, ResponseContentType: Types } = require('./build/src/start/server/middleware/ExpoGoManifestHandlerMiddleware');
  const { getCodeSigningInfoAsync, signManifestString } = require('./build/src/utils/codesigning');
  const { serializeDictionary } = require('structured-headers');
  const { exp, expoGoConfig, bundleUrl, hostUri } = await middleware._resolveProjectSettingsAsync(options);
  const requirements = await resolveRuntimeRequirementsAsync(middleware.projectRoot);
  const signing = await getCodeSigningInfoAsync(exp, options.expectSignature, middleware.options.privateKeyPath);
  const scope = await Manifest.getScopeKeyAsync({ slug: exp.slug, codeSigningInfo: signing });

  const bundle = new URL(bundleUrl);
  bundle.searchParams.set('transform.engine', 'hermes');
  bundle.searchParams.set('transform.bytecode', '0');
  bundle.searchParams.set('unstable_transformProfile', 'hermes-stable');
  bundle.searchParams.set('lazy', 'false');

  const name = exp.harmony?.bundleName || (await resolveHarmonyBuildPlanAsync(middleware.projectRoot)).bundleName;
  const id = exp.extra?.eas?.projectId;
  const address = canonicalHarmonyManifestURL(`${bundle.origin}${options.harmonyManifestPath ?? `${HarmonyManifestPath}?platform=harmony`}`);
  const manifest = JSON.stringify({
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    runtimeVersion: requirements.runtimeVersion,
    launchAsset: { key: 'bundle', contentType: 'application/javascript', url: bundle.toString() },
    assets: [],
    metadata: {},
    extra: {
      eas: { projectId: id ?? undefined },
      expoClient: { ...exp, hostUri },
      expoGo: expoGoConfig,
      scopeKey: scope,
      harmony: {
        projectId: id || `@${exp.owner || 'anonymous'}/${exp.slug}/${name}`,
        manifestUrl: address,
        launchLink: createHarmonyLaunchLink(address),
        requirements,
      },
    },
  });
  const signature = signing
    ? serializeDictionary(new Map(Object.entries({
        keyid: signing.keyId,
        sig: signManifestString(manifest, signing),
        alg: 'rsa-v1_5-sha256',
      }).map(([key, value]) => [key, [value, new Map()]])))
    : undefined;

  if (options.responseContentType === Types.MULTIPART_MIXED) {
    return middleware.encodeFormDataAsync({
      stringifiedManifest: manifest,
      manifestPartHeaders: signature ? { 'expo-signature': signature } : undefined,
      certificateChainBody: signing?.certificateChainForResponse.join('\n') ?? null,
    });
  }

  const headers = middleware.getDefaultResponseHeaders();
  headers.set('content-type', Manifest.getContentTypeForResponseContentType(options.responseContentType));
  if (signature) headers.set('expo-signature', signature);

  return new Response(manifest, { headers });
}

export function installHarmonyManifest(root: string) {
  const expo = createRequire(resolveExpoCli(root).cliPath);
  const require = createRequire(expo.resolve('@expo/cli/package.json'));

  const { BundlerDevServer } = require('./build/src/start/server/BundlerDevServer');
  const { parsePlatformHeader } = require('./build/src/start/server/middleware/resolvePlatform');
  const create = BundlerDevServer.prototype.getManifestMiddlewareAsync;

  // Reuse Expo's terminal QR renderer and dev-session publishing with our
  // registered link, rather than emitting a second, incompatible QR code.
  const nativeURL = BundlerDevServer.prototype.getNativeRuntimeUrl;
  const redirectURL = BundlerDevServer.prototype.getRedirectUrl;
  BundlerDevServer.prototype.getNativeRuntimeUrl = function (options = {}) {
    const address = this.getUrlCreator().constructUrl({ ...options, scheme: 'http' });
    if (!address) return nativeURL.call(this, options);
    const manifest = new URL(HarmonyManifestPath, address);
    manifest.searchParams.set('platform', 'harmony');
    return createHarmonyLaunchLink(manifest.toString());
  };
  BundlerDevServer.prototype.getRedirectUrl = function (platform = null) {
    return platform === null || platform === 'harmony'
      ? this.getNativeRuntimeUrl()
      : redirectURL.call(this, platform);
  };

  // Expo installs the manifest before Metro's enhancer; adapt only the created instance.
  BundlerDevServer.prototype.getManifestMiddlewareAsync = async function (this: object, ...args) {
    const middleware = await create.apply(this, args);
    const parse = middleware.getParsedHeaders;
    const respond = middleware._getManifestResponseAsync;

    middleware.getParsedHeaders = (request) => {
      if (parsePlatformHeader(request) !== 'harmony') return parse.call(middleware, request);

      // Bypass only the upstream platform assertion without changing the actual request.
      const url = new URL(request.url, 'http://localhost');
      url.searchParams.delete('platform');
      url.searchParams.append('platform', 'harmony');
      const manifest = new URL(canonicalHarmonyManifestURL(url.toString()));
      const harmonyManifestPath = manifest.pathname + manifest.search;
      url.searchParams.set('platform', 'ios');
      const copy = Object.create(request);
      copy.url = url.pathname + url.search;

      return { ...parse.call(middleware, copy), platform: 'harmony', harmonyManifestPath };
    };
    middleware._getManifestResponseAsync = options => options.platform === 'harmony'
      ? createManifestResponseAsync(middleware, options, require)
      : respond.call(middleware, options);

    return middleware;
  };
}
