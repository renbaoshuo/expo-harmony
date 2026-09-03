{
  "name": "{{NPM_NAME}}",
  "version": "{{PACKAGE_VERSION}}",
  "private": true,
  "main": "index.ts",
  "types": "index.ts",
  "scripts": {
    "harmony:clean": "expo-harmony-module prepare --clean-only",
    "harmony:build": "expo-harmony-module prepare",
    "harmony:inspect": "expo-harmony-module inspect",
    "prepare": "expo-harmony-module prepare"
  },
  "peerDependencies": {
    "@expo-harmony/expo-modules-core": "^55.0.25-harmony.0",
    "expo-modules-core": "^55.0.0",
    "react": "*",
    "react-native": "*"
  },
  "devDependencies": {
    "@expo-harmony/expo-module-scripts": "^55.0.0-harmony.0"
  },
  "engines": {
    "node": ">=20"
  }
}
