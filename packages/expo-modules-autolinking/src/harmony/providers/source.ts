import { resolveRnohMetadata } from '../rnoh/packageMetadata';

function selectActiveProviders(descriptor, buildType = 'debug') {
  return descriptor.expo.providers.filter(provider => buildType !== 'release' || !provider.debugOnly);
}

function findRnohProviderMapping(descriptor) {
  const providerHar = descriptor.expo.providerHar;
  if (!providerHar || descriptor.rnoh.harPaths.length === 0) return null;

  const primary = resolveRnohMetadata(descriptor).harMappings[0];
  const matches = primary.harPath === providerHar.harPath
    && primary.ohPackageName === providerHar.ohPackageName;
  return matches ? primary : null;
}

function resolveProviderSource(descriptor, buildType = 'debug') {
  if (!descriptor.expo.providerHar || selectActiveProviders(descriptor, buildType).length === 0) {
    return null;
  }

  const rnohMapping = findRnohProviderMapping(descriptor);
  return {
    descriptor,
    harPath: descriptor.expo.providerHar.harPath,
    ohPackageName: descriptor.expo.providerHar.ohPackageName,
    ...(rnohMapping?.version ? { version: rnohMapping.version } : {}),
    rnohManaged: rnohMapping !== null,
  };
}

function resolveProviderSources(descriptors, buildType = 'debug') {
  return descriptors
    .map(descriptor => resolveProviderSource(descriptor, buildType))
    .filter(Boolean)
    .sort((left, right) => left.ohPackageName.localeCompare(right.ohPackageName, 'en')
      || left.descriptor.packageName.localeCompare(right.descriptor.packageName, 'en'));
}

export {
  selectActiveProviders,
  findRnohProviderMapping,
  resolveProviderSource,
  resolveProviderSources,
};
