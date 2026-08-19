import path from 'node:path';

import {
  withAppJson, withHvigorConfig, withProjectBuildProfile,
  withReactNativeConfig, withRootHvigor, withRootOhPackage,
} from '@expo-harmony/config-plugins';
import { loadConfigAsync as loadReactNativeCliConfigAsync } from '@react-native-community/cli-config';

import { readTemplateSource, resolvePackageVersion, resolveRnohHvigorPlugin, toRelativeDependency } from '../dependencies';
import { HarmonyPrebuildError } from '../errors';
import { readRecord, replaceManagedString, upsertManagedNamed, upsertNamed } from '../reconcile';
import * as render from '../renderers';

function hasRnohLinkCommand(config) {
  const names = new Set((config?.commands || []).map(command => command?.name));
  return names.has('link-harmony');
}

async function loadReactNativeConfigAsync(projectRoot, file) {
  try {
    return await loadReactNativeCliConfigAsync({ projectRoot });
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', `Cannot load the existing React Native CLI config: ${file}`, { cause, file, operation: 'react-native-config' });
  }
}

export function withProjectMods(config, normalized) {
  config = withReactNativeConfig(config, async (value) => {
    const projectRoot = value.modRequest.projectRoot;
    const request = value.modRequest as typeof value.modRequest & {
      modFile: string;
      modFileExists: boolean;
    };
    const configFile = request.modFile;
    if (request.modFileExists) {
      if (!hasRnohLinkCommand(await loadReactNativeConfigAsync(projectRoot, configFile))) {
        throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', 'The React Native CLI config must expose the RNOH link-harmony command.', { file: configFile, operation: 'react-native-config' });
      }
      return value;
    }

    value.modResults = render.renderReactNativeConfig();
    return value;
  });

  config = withAppJson(config, (value) => {
    const app = value.modResults.app && typeof value.modResults.app === 'object' ? value.modResults.app : {};
    value.modResults = {
      ...value.modResults,
      app: {
        ...app,
        bundleName: normalized.bundleName,
        icon: '$media:app_icon',
        label: '$string:app_name',
        vendor: normalized.vendor,
        versionCode: normalized.versionCode,
        versionName: normalized.versionName,
      },
    };
    return value;
  });

  config = withProjectBuildProfile(config, (value) => {
    const profile = value.modResults;
    const app = readRecord(profile.app);
    const signingConfig = value._internal?.harmonySigningConfig;
    const previousSigningConfigName = value._internal?.harmonyPreviousSigningConfigName;
    const previousIdentity = value._internal?.harmonyPreviousManagedIdentity;
    const products = upsertManagedNamed(
      app.products,
      normalized.productName,
      previousIdentity?.productName,
      'default',
      (existing) => {
        const product = {
          ...existing,
          name: normalized.productName,
          compatibleSdkVersion: normalized.compatibleSdkVersionString,
          targetSdkVersion: normalized.targetSdkVersionString,
          runtimeOS: 'HarmonyOS',
          buildOption: { ...(existing.buildOption || {}), nativeCompiler: 'BiSheng' },
          ...(signingConfig ? { signingConfig: signingConfig.name } : {}),
        };
        if (!signingConfig && product.signingConfig === previousSigningConfigName) {
          delete product.signingConfig;
        }
        return product;
      },
      'productName'
    );
    const modules = upsertManagedNamed(
      profile.modules,
      normalized.moduleName,
      previousIdentity?.moduleName,
      'entry',
      existing => ({
        ...existing,
        name: normalized.moduleName,
        srcPath: './entry',
        targets: upsertNamed(existing.targets, 'default', target => ({
          ...target,
          name: 'default',
          applyToProducts: replaceManagedString(
            target.applyToProducts,
            normalized.productName,
            previousIdentity?.productName,
            'default'
          ),
        })),
      }),
      'moduleName'
    );

    let signingConfigs = app.signingConfigs;
    if (signingConfig) {
      signingConfigs = upsertManagedNamed(
        signingConfigs,
        signingConfig.name,
        previousSigningConfigName,
        '',
        () => signingConfig,
        'signingConfigName'
      );
    } else if (previousSigningConfigName) {
      signingConfigs = (Array.isArray(signingConfigs) ? signingConfigs : [])
        .filter(item => item?.name !== previousSigningConfigName);
    }

    value.modResults = {
      ...profile,
      app: {
        ...app,
        products,
        buildModeSet: upsertNamed(
          upsertNamed(app.buildModeSet, 'debug', existing => ({ ...existing, name: 'debug' })),
          'release',
          existing => ({ ...existing, name: 'release' })
        ),
        ...(signingConfigs === undefined ? {} : { signingConfigs }),
      },
      modules,
    };
    return value;
  });

  config = withRootOhPackage(config, (value) => {
    const rnohVersion = resolvePackageVersion(value.modRequest.projectRoot, '@react-native-oh/react-native-harmony');
    const dependencies = { ...readRecord(value.modResults.dependencies) };
    const overrides = { ...readRecord(value.modResults.overrides) };
    value.modResults = {
      ...value.modResults,
      name: normalized.bundleName,
      version: normalized.versionName,
      license: value.modResults.license || 'MIT',
      dependencies: {
        ...dependencies,
        '@rnoh/react-native-openharmony': rnohVersion,
      },
      overrides: {
        ...overrides,
        '@rnoh/react-native-openharmony': rnohVersion,
      },
    };
    return value;
  });

  config = withRootHvigor(config, async (value) => {
    value.modResults = render.renderRootHvigor(
      await readTemplateSource('hvigorfile.ts'),
      normalized
    );
    return value;
  });

  config = withHvigorConfig(config, (value) => {
    const projectRoot = value.modRequest.projectRoot;
    const hvigorDirectory = path.join(projectRoot, 'harmony/hvigor');
    const hvigorPlugin = toRelativeDependency(hvigorDirectory, resolveRnohHvigorPlugin(projectRoot));
    value.modResults = {
      ...value.modResults,
      dependencies: {
        ...readRecord(value.modResults.dependencies),
        '@rnoh/hvigor-plugin': hvigorPlugin,
      },
      execution: value.modResults.execution || {},
      logging: value.modResults.logging || {},
      debugging: value.modResults.debugging || {},
      nodeOptions: value.modResults.nodeOptions || {},
    };
    return value;
  });

  return config;
}
