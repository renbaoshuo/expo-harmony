import path from 'node:path';

import {
  withAppJson,
  withHvigorConfig,
  withNativeInputsStamp,
  withProjectBuildProfile,
  withReactNativeConfig,
  withRootHvigor,
  withRootOhPackage,
} from '@expo-harmony/config-plugins';
import { loadConfigAsync as loadReactNativeCliConfigAsync } from '@react-native-community/cli-config';

import {
  createHarmonyBuildDescriptor,
  harmonyModuleSourcePath,
  resolveHarmonyBuildPath,
} from '../buildDescriptor';
import {
  readTemplateSource,
  resolvePackageVersion,
  resolveRnohHvigorPlugin,
  toRelativeDependency,
} from '../dependencies';
import { HarmonyPrebuildError } from '../errors';
import { readRecord, replaceManagedString, upsertManagedNamed, upsertNamed } from '../reconcile';
import * as render from '../renderers';

function hasRnohLinkCommand(config) {
  const names = new Set((config?.commands || []).map(command => command?.name));
  return names.has('link-harmony');
}

async function loadReactNativeConfigAsync(root, file) {
  try {
    return await loadReactNativeCliConfigAsync({ projectRoot: root });
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Cannot load the existing React Native CLI config: ${file}`,
      { cause, file, operation: 'react-native-config' }
    );
  }
}

export function withProjectMods(config, harmony) {
  config = withReactNativeConfig(config, async (mod) => {
    const root = mod.modRequest.projectRoot;
    const request = mod.modRequest as typeof mod.modRequest & {
      modFile: string;
      modFileExists: boolean;
    };
    const file = request.modFile;

    if (request.modFileExists) {
      if (!hasRnohLinkCommand(await loadReactNativeConfigAsync(root, file))) {
        throw new HarmonyPrebuildError(
          'ERR_HARMONY_CONFIG_INVALID',
          'The React Native CLI config must expose the RNOH link-harmony command.',
          { file, operation: 'react-native-config' }
        );
      }

      return mod;
    }

    mod.modResults = render.renderReactNativeConfig();

    return mod;
  });

  config = withAppJson(config, (mod) => {
    const app = mod.modResults.app && typeof mod.modResults.app === 'object'
      ? mod.modResults.app
      : {};

    mod.modResults = {
      ...mod.modResults,
      app: {
        ...app,
        bundleName: harmony.bundleName,
        icon: '$media:app_icon',
        label: '$string:app_name',
        vendor: harmony.vendor,
        versionCode: harmony.versionCode,
        versionName: harmony.versionName,
      },
    };

    return mod;
  });

  config = withProjectBuildProfile(config, (mod) => {
    const build = createHarmonyBuildDescriptor(
      harmony,
      mod._internal?.harmonySigningConfig?.name ?? null
    );
    const { moduleName, productName, targetName } = build.identity;

    const profile = mod.modResults;
    const app = readRecord(profile.app);
    const signing = mod._internal?.harmonySigningConfig;
    const previousSigning = mod._internal?.harmonyPreviousSigningConfigName;
    const previous = mod._internal?.harmonyPreviousManagedIdentity;

    const products = upsertManagedNamed(
      app.products,
      productName,
      previous?.productName,
      'default',
      (existing) => {
        const product = {
          ...existing,
          name: productName,
          compatibleSdkVersion: harmony.compatibleSdkVersionString,
          targetSdkVersion: harmony.targetSdkVersionString,
          runtimeOS: 'HarmonyOS',
          buildOption: { ...(existing.buildOption || {}), nativeCompiler: 'BiSheng' },
          ...(signing ? { signingConfig: signing.name } : {}),
        };

        if (!signing && product.signingConfig === previousSigning) {
          delete product.signingConfig;
        }

        return product;
      },
      'productName'
    );
    const modules = upsertManagedNamed(
      profile.modules,
      moduleName,
      previous?.moduleName,
      'entry',
      existing => ({
        ...existing,
        name: moduleName,
        srcPath: harmonyModuleSourcePath(build),
        targets: upsertNamed(existing.targets, targetName, target => ({
          ...target,
          name: targetName,
          applyToProducts: replaceManagedString(
            target.applyToProducts,
            productName,
            previous?.productName,
            'default'
          ),
        })),
      }),
      'moduleName'
    );

    let configs = app.signingConfigs;

    if (signing) {
      configs = upsertManagedNamed(
        configs,
        signing.name,
        previousSigning,
        '',
        () => signing,
        'signingConfigName'
      );
    } else if (previousSigning) {
      configs = (Array.isArray(configs) ? configs : [])
        .filter(item => item?.name !== previousSigning);
    }

    mod.modResults = {
      ...profile,
      app: {
        ...app,
        products,
        buildModeSet: upsertNamed(
          upsertNamed(app.buildModeSet, 'debug', existing => ({ ...existing, name: 'debug' })),
          'release',
          existing => ({ ...existing, name: 'release' })
        ),
        ...(configs === undefined ? {} : { signingConfigs: configs }),
      },
      modules,
    };

    return mod;
  });

  config = withRootOhPackage(config, (mod) => {
    const version = resolvePackageVersion(
      mod.modRequest.projectRoot,
      '@react-native-oh/react-native-harmony'
    );
    const dependencies = { ...readRecord(mod.modResults.dependencies) };
    const overrides = { ...readRecord(mod.modResults.overrides) };

    mod.modResults = {
      ...mod.modResults,
      name: harmony.bundleName,
      version: harmony.versionName,
      license: mod.modResults.license || 'MIT',
      dependencies: {
        ...dependencies,
        '@rnoh/react-native-openharmony': version,
      },
      overrides: {
        ...overrides,
        '@rnoh/react-native-openharmony': version,
      },
    };

    return mod;
  });

  config = withRootHvigor(config, async (mod) => {
    const build = createHarmonyBuildDescriptor(
      harmony,
      mod._internal?.harmonySigningConfig?.name ?? null
    );
    const relative = path.posix.relative(build.harmonyRoot, build.projectFiles.rootHvigor);
    const source = await readTemplateSource(relative);

    mod.modResults = render.renderRootHvigor(source, build);

    return mod;
  });

  config = withNativeInputsStamp(config, async (mod) => {
    const build = createHarmonyBuildDescriptor(harmony, mod._internal?.harmonySigningConfig?.name ?? null);
    const relative = path.posix.relative(build.harmonyRoot, build.projectFiles.nativeInputsStamp);
    const source = await readTemplateSource(relative);

    mod.modResults = render.renderCanonical(source, build.projectFiles.nativeInputsStamp);

    return mod;
  });

  config = withHvigorConfig(config, (mod) => {
    const root = mod.modRequest.projectRoot;
    const build = createHarmonyBuildDescriptor(harmony, mod._internal?.harmonySigningConfig?.name ?? null);
    const directory = path.dirname(resolveHarmonyBuildPath(root, build.projectFiles.hvigorConfig));
    const plugin = toRelativeDependency(directory, resolveRnohHvigorPlugin(root));

    mod.modResults = {
      ...mod.modResults,
      dependencies: {
        ...readRecord(mod.modResults.dependencies),
        '@rnoh/hvigor-plugin': plugin,
      },
      execution: mod.modResults.execution || {},
      logging: mod.modResults.logging || {},
      debugging: mod.modResults.debugging || {},
      nodeOptions: mod.modResults.nodeOptions || {},
    };

    return mod;
  });

  return config;
}
