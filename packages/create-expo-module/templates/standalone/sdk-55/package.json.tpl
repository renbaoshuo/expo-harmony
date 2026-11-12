{
  "name": "{{NPM_NAME}}",
  "version": "{{PACKAGE_VERSION}}",
  "license": "MIT",
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
    "expo-modules-core": "^55.0.0",
    "react": "*",
    "react-native": "*"
  },
  "devDependencies": {
    "@expo-harmony/expo-module-scripts": "{{MODULE_SCRIPTS_VERSION}}",
    "@expo-harmony/expo-modules-core": "{{HARMONY_CORE_VERSION}}",
    "@types/react": "~19.2.2",
    "expo-modules-core": "{{CORE_VERSION}}",
    "react": "{{REACT_VERSION}}",
    "react-native": "{{REACT_NATIVE_VERSION}}",
    "typescript": "^6.0.3"
  },
  "files": [
    "build",
    "src",
    "expo-module.config.json",
    "harmony/*.har",
    "harmony/library/oh-package.json5"
  ],
  "engines": {
    "node": "{{NODE_VERSION}}"
  },
  "publishConfig": {
    "access": "public"
  }
}
