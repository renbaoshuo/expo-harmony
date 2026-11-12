/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

const Platform = 'harmony';
const ReactNativeCommunityCliPackage = '@react-native-community/cli';
const RnohCliPackage = '@react-native-oh/react-native-harmony-cli';
const ToolVersion = JSON.parse(readFileSync(path.resolve(__dirname, '../../../package.json'), 'utf8')).version;
const ManifestSchemaVersion = 4;
const ArkTsLibraryHarPath = 'harmony/library.har';
const ArkTsLibraryManifestPath = 'harmony/library/oh-package.json5';

const RnohArtifacts = Object.freeze({
  etsFactory: 'entry/src/main/ets/RNOHPackagesFactory.ets',
  cppFactory: 'entry/src/main/cpp/RNOHPackagesFactory.h',
  cmake: 'entry/src/main/cpp/autolinking.cmake',
  ohPackage: 'oh-package.json5',
});

const ExpoArtifacts = Object.freeze({
  hostProvider: 'entry/src/main/ets/generated/ExpoHarmonyHostProvider.ets',
  workerFactory: 'entry/src/main/ets/RNOHWorkerPackagesFactory.ets',
});

const InlineModulesRoot = path.posix.join(path.posix.dirname(ExpoArtifacts.hostProvider), 'inline');
const GeneratedNativeSources = Object.freeze({
  files: [RnohArtifacts.etsFactory, RnohArtifacts.cppFactory, RnohArtifacts.cmake, ...Object.values(ExpoArtifacts)],
  directories: [InlineModulesRoot],
});

const ManifestArtifact = '.expo/harmony/autolinking.json';
const ModuleBuildOptionsArtifact = '.expo/harmony/module-build-options.json';

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
  ArkTsLibraryHarPath,
  ArkTsLibraryManifestPath,
  ExpoArtifacts,
  GeneratedNativeSources,
  InlineModulesRoot,
  ManagedArtifacts,
  ManifestArtifact,
  ManifestSchemaVersion,
  ModuleBuildOptionsArtifact,
  managedArtifactsForHarmonyRoot,
  Platform,
  ReactNativeCommunityCliPackage,
  RnohArtifacts,
  RnohCliPackage,
  ToolVersion,
};
