/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

{
  "app": {
    "products": [
      {
        "name": "default",
        "compatibleSdkVersion": "5.0.1(13)",
        "targetSdkVersion": "6.1.1(24)",
        "runtimeOS": "HarmonyOS"
      }
    ],
    "buildModeSet": [{ "name": "debug" }, { "name": "release" }]
  },
  "modules": [
    {
      "name": "library",
      "srcPath": "./library",
      "targets": [{ "name": "default", "applyToProducts": ["default"] }]
    }
  ]
}
