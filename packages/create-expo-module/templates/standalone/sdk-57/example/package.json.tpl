{
  "name": "{{HARMONY_MODULE}}-example",
  "version": "1.0.0",
  "private": true,
  "main": "index.ts",
  "scripts": {
    "start": "expo-harmony start",
    "prebuild:harmony": "expo-harmony prebuild --no-install",
    "check:harmony": "expo-harmony prebuild --check",
    "build:harmony": "expo-harmony build",
    "harmony": "expo-harmony run"
  },
  "dependencies": {
    "@babel/core": "7.29.7",
    "@expo-harmony/cli": "{{CLI_VERSION}}",
    "@expo-harmony/expo": "{{HARMONY_EXPO_VERSION}}",
    "@expo-harmony/expo-modules-core": "{{HARMONY_CORE_VERSION}}",
    "@expo-harmony/metro-config": "{{METRO_VERSION}}",
    "@expo-harmony/prebuild-config": "{{PREBUILD_VERSION}}",
    "@expo/metro-runtime": "57.0.17",
    "@react-native/metro-config": "{{REACT_NATIVE_VERSION}}",
    "expo": "{{EXPO_VERSION}}",
    "expo-modules-core": "{{CORE_VERSION}}",
    "metro": "0.84.3",
    "metro-config": "0.84.3",
    "react": "{{REACT_VERSION}}",
    "react-native": "{{REACT_NATIVE_VERSION}}",
    "react-native-worklets": "{{WORKLETS_VERSION}}"
  },
  "devDependencies": {
    "@types/react": "~19.2.2",
    "typescript": "^6.0.3"
  },
  "engines": {
    "node": "{{NODE_VERSION}}"
  }
}
