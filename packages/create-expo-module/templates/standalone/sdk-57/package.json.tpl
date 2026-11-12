{
  "name": "{{NPM_NAME}}",
  "version": "{{PACKAGE_VERSION}}",
  "license": {{LICENSE_JSON}},
  "main": "build/index.js",
  "types": "build/index.d.ts",
  "exports": {
    ".": {
      "types": "./build/index.d.ts",
      "require": "./build/index.js",
      "default": "./build/index.js"
    }
  },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "harmony:clean": "expo-harmony-module prepare --clean-only",
    "harmony:build": "expo-harmony-module prepare",
    "harmony:inspect": "expo-harmony-module inspect",
    "prepare": "npm run build && expo-harmony-module prepare",
    "prepack": "npm run build && expo-harmony-module prepack"
  },
  "peerDependencies": {
    "@expo-harmony/expo-modules-core": "{{HARMONY_CORE_VERSION}}",
    "expo-modules-core": "{{CORE_VERSION}}",
    "react": "{{REACT_VERSION}}",
    "react-native": "{{REACT_NATIVE_VERSION}}",
    "react-native-worklets": "{{WORKLETS_VERSION}}"
  },
  "devDependencies": {
    "@expo-harmony/expo-module-scripts": "^{{MODULE_SCRIPTS_VERSION}}",
    "@expo-harmony/expo-modules-core": "{{HARMONY_CORE_VERSION}}",
    "expo-modules-core": "{{CORE_VERSION}}",
    "@types/react": "~19.2.2",
    "react": "{{REACT_VERSION}}",
    "react-native": "{{REACT_NATIVE_VERSION}}",
    "react-native-worklets": "{{WORKLETS_VERSION}}",
    "typescript": "^6.0.3"
  },
  "engines": {
    "node": "{{NODE_VERSION}}"
  },
  "publishConfig": {
    "access": "public"
  },
  "description": {{DESCRIPTION_JSON}},
  "author": {{AUTHOR_JSON}},
  "repository": {{REPO_JSON}},
  "files": [
    "build",
    "src",
    "expo-module.config.json",
    "harmony/*.har",
    "harmony/library/oh-package.json5"
  ]
}
