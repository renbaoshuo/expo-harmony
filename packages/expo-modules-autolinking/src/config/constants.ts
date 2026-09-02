import { readFileSync } from 'node:fs';
import path from 'node:path';

const Platform = 'harmony';
const RnohCliPackage = '@react-native-oh/react-native-harmony-cli';
const ToolVersion = JSON.parse(readFileSync(path.resolve(__dirname, '../../../package.json'), 'utf8')).version;
const ManifestSchemaVersion = 3;

const RnohArtifacts = Object.freeze({
  etsFactory: 'entry/src/main/ets/RNOHPackagesFactory.ets',
  cppFactory: 'entry/src/main/cpp/RNOHPackagesFactory.h',
  cmake: 'entry/src/main/cpp/autolinking.cmake',
  ohPackage: 'oh-package.json5',
});

const ExpoArtifacts = Object.freeze({
  hostProvider: 'entry/src/main/ets/generated/ExpoHarmonyHostProvider.ets',
});

const ManifestArtifact = '.expo/harmony/autolinking.json';

function managedArtifactsForHarmonyRoot(harmonyRoot) {
  const prefix = String(harmonyRoot).replace(/\\/g, '/').replace(/^\.\//, '').replace(/\/$/, '');

  const withinHarmony = [
    ...Object.values(RnohArtifacts),
    ...Object.values(ExpoArtifacts),
  ].map(relative => prefix ? `${prefix}/${relative}` : relative);

  return Object.freeze([...withinHarmony, ManifestArtifact]);
}

const ManagedArtifacts = managedArtifactsForHarmonyRoot('harmony');

export {
  ExpoArtifacts,
  ManagedArtifacts,
  ManifestArtifact,
  ManifestSchemaVersion,
  managedArtifactsForHarmonyRoot,
  Platform,
  RnohArtifacts,
  RnohCliPackage,
  ToolVersion,
};
