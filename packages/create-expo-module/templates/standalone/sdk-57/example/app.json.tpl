{
  "expo": {
    "name": "{{MODULE_BASE}} Example",
    "slug": "{{HARMONY_MODULE}}-example",
    "platforms": [
      "harmony"
    ],
    "experiments": {
      "outOfTreePlatforms": true
    },
    "plugins": [
      "@expo-harmony/prebuild-config"
    ],
    "harmony": {
      "bundleName": "{{BUNDLE_NAME}}.example",
      "abiFilters": [
        "arm64-v8a"
      ]
    }
  }
}
