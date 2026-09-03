const ProjectPackages = Object.freeze({
  expo: 'expo',
  expoAutolinking: '@expo-harmony/expo-modules-autolinking',
  reactNative: 'react-native',
  rnohCli: '@react-native-oh/react-native-harmony-cli',
  rnohRuntime: '@react-native-oh/react-native-harmony',
});

const RequiredProjectPackages = Object.freeze([
  ProjectPackages.rnohRuntime,
  ProjectPackages.rnohCli,
  ProjectPackages.expoAutolinking,
]);

export {
  ProjectPackages,
  RequiredProjectPackages,
};
