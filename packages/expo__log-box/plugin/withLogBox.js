/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const path = require('node:path');

/** Keep Expo's inspector/parser; adapt only its DOM host on Harmony. */
function withLogBox(config) {
  const enabled = ['1', 'true'].includes(process.env.EXPO_UNSTABLE_LOG_BOX?.toLowerCase());
  if (!enabled) return config;

  const resolve = config.resolver?.resolveRequest;
  const harmonyRuntime = resolve?.harmonyRuntime;
  const runtimeRoot = harmonyRuntime?.harmonyPackageRoot ?? path.dirname(require.resolve('react-native/package.json'));
  const inspectorFile = path.join(runtimeRoot, 'Libraries/LogBox/LogBoxInspectorContainer.js');
  const runtimeParser = path.join(runtimeRoot, 'Libraries/LogBox/Data/parseLogBoxLog.js');
  const root = path.dirname(require.resolve('@expo/log-box/package.json'));
  const inspector = path.join(root, 'swap-rn-logbox.js');
  const parser = path.join(root, 'swap-rn-logbox-parser.js');
  const nativeInspector = path.join(root, 'src/logbox-rn-polyfill.tsx');
  const dom = path.join(root, 'src/logbox-dom-polyfill.tsx');
  return {
    ...config,
    resolver: {
      ...config.resolver,
      resolveRequest: Object.assign(function resolveRequest(context, name, platform) {
        const result = (resolve ?? context.resolveRequest)(context, name, platform);
        if (platform !== 'harmony' || result.type !== 'sourceFile') return result;

        if (result.filePath === inspectorFile) {
          return { type: 'sourceFile', filePath: inspector };
        }
        if (result.filePath === runtimeParser) {
          return { type: 'sourceFile', filePath: parser };
        }
        if (context.originModulePath === nativeInspector && result.filePath === dom) {
          return { type: 'sourceFile', filePath: path.join(__dirname, '../src/LogBoxDOMView.tsx') };
        }

        return result;
      }, { harmonyRuntime }),
    },
  };
}

module.exports = { withLogBox };
