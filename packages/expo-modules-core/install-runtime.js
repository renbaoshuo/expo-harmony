const expoModulesCore = global.__turboModuleProxy?.('ExpoModulesCore')
  ?? global.nativeModuleProxy?.ExpoModulesCore;

if (typeof expoModulesCore?.installModules !== 'function') {
  throw new Error('ExpoModulesCore is not linked into the RNOH runtime.');
}
expoModulesCore.installModules();
