{
  "name": "{{HARMONY_MODULE}}-example",
  "version": "1.0.0",
  "private": true,
  "main": "node_modules/expo/AppEntry.js",
  "scripts": {
    "start": "expo start --dev-client",
    "prebuild:harmony": "expo-harmony prebuild . --no-install",
    "harmony": "expo-harmony run ."
  },
  "dependencies": {
    "@expo-harmony/cli": "^55.0.26-harmony.1",
    "@expo-harmony/expo-modules-core": "^55.0.25-harmony.1",
    "@expo-harmony/prebuild-config": "^55.0.0-harmony.0",
    "@react-native-oh/react-native-harmony": "0.84.1",
    "{{NPM_NAME}}": "file:..",
    "expo": "^55.0.0",
    "expo-modules-core": "^55.0.0",
    "react": "19.2.3",
    "react-native": "0.84.1"
  }
}
