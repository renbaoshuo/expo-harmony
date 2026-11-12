{
  "name": "{{NPM_NAME}}",
  "version": "{{PACKAGE_VERSION}}",
  "private": true,
  "main": "src/index.ts",
  "types": "src/index.ts",
  "scripts": {
    "harmony:clean": "expo-harmony-module prepare --clean-only",
    "harmony:build": "expo-harmony-module prepare",
    "harmony:inspect": "expo-harmony-module inspect"
  },
  "peerDependencies": {
    "@expo-harmony/expo-modules-core": "{{HARMONY_CORE_VERSION}}",
    "expo-modules-core": "{{CORE_VERSION}}",
    "react": "{{REACT_VERSION}}",
    "react-native": "{{REACT_NATIVE_VERSION}}",
    "react-native-worklets": "{{WORKLETS_VERSION}}"
  },
  "devDependencies": {
    "@expo-harmony/expo-module-scripts": "^{{MODULE_SCRIPTS_VERSION}}"
  },
  "engines": {
    "node": "{{NODE_VERSION}}"
  }
}
