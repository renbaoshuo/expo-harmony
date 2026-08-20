const ProjectPackages = Object.freeze({
  expo: 'expo',
  expoAutolinking: '@expo-harmony/expo-modules-autolinking',
  hermesCompiler: 'hermes-compiler',
  reactNative: 'react-native',
  rnohCli: '@react-native-oh/react-native-harmony-cli',
  rnohRuntime: '@react-native-oh/react-native-harmony',
});

const RequiredProjectPackages = Object.freeze([
  ProjectPackages.rnohRuntime,
  ProjectPackages.rnohCli,
  ProjectPackages.expoAutolinking,
]);

const PublicCliOptions = Object.freeze({
  expoExportEmbed: Object.freeze([
    '--assets-dest',
    '--bundle-output',
    '--bytecode',
    '--dev',
    '--entry-file',
    '--minify',
    '--platform',
    '--sourcemap-output',
    '--sourcemap-sources-root',
    '--unstable-transform-profile',
  ]),
  rnohLinkHarmony: Object.freeze([
    '--cmake-autolink-path-relative-to-harmony',
    '--cpp-rnoh-packages-factory-path-relative-to-harmony',
    '--ets-rnoh-packages-factory-path-relative-to-harmony',
    '--harmony-project-path',
    '--node-modules-path',
    '--oh-package-path-relative-to-harmony',
  ]),
  rnohRunHarmony: Object.freeze([
    '--ability',
    '--build-mode',
    '--harmony-project-path',
    '--module',
    '--no-packager',
    '--port',
    '--product',
    '--simulator',
  ]),
});

const HermesCompilerPaths = Object.freeze({
  darwin: 'hermesc/osx-bin/hermesc',
  linux: 'hermesc/linux64-bin/hermesc',
  win32: 'hermesc/win64-bin/hermesc.exe',
});

export {
  HermesCompilerPaths,
  ProjectPackages,
  PublicCliOptions,
  RequiredProjectPackages,
};
