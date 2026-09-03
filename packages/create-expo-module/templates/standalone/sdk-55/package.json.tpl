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
    "@expo-harmony/expo-modules-core": "^55.0.25-harmony.1",
    "expo-modules-core": "^55.0.0",
    "react": "*",
    "react-native": "*"
  },
  "devDependencies": {
    "@expo-harmony/expo-module-scripts": "^55.0.0-harmony.0",
    "typescript": "^6.0.3"
  },
  "engines": {
    "node": ">=20"
  },
  "publishConfig": {
    "access": "public"
  }
}
