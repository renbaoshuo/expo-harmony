{
  "name": "{{HARMONY_MODULE}}-example",
  "version": "1.0.0",
  "private": true,
  "main": "node_modules/expo/AppEntry.js",
  "scripts": {
    "start": "expo-harmony start",
    "prebuild:harmony": "expo-harmony prebuild . --no-install",
    "harmony": "expo-harmony run ."
  },
  "dependencies": {
    "@babel/core": "7.29.7",
    "@expo-harmony/cli": "{{CLI_VERSION}}",
    "@expo-harmony/expo": "{{HARMONY_EXPO_VERSION}}",
    "@expo-harmony/expo-modules-core": "{{HARMONY_CORE_VERSION}}",
    "@expo-harmony/metro-config": "{{METRO_VERSION}}",
    "@expo-harmony/prebuild-config": "{{PREBUILD_VERSION}}",
    "@expo/metro-config": "55.0.27",
    "@expo/metro-runtime": "55.0.12",
    "@react-native-oh/react-native-harmony": "{{RNOH_VERSION}}",
    "@react-native-ohos/react-native-worklets": "1.0.1",
    "expo": "{{EXPO_VERSION}}",
    "expo-modules-core": "{{CORE_VERSION}}",
    "metro": "0.83.3",
    "metro-config": "0.83.7",
    "react": "{{REACT_VERSION}}",
    "react-harmony": "npm:react@19.2.3",
    "react-native": "{{REACT_NATIVE_VERSION}}",
    "react-native-worklets": "{{WORKLETS_VERSION}}"
  }
}
