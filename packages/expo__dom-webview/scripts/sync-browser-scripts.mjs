/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import semver from 'semver';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const upstream = path.dirname(require.resolve('@expo/dom-webview/package.json'));
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
const official = JSON.parse(await readFile(path.join(upstream, 'package.json'), 'utf8'));

const supported = pkg.peerDependencies['@expo/dom-webview'];
if (!semver.satisfies(official.version, supported)) {
  throw new Error(`Expected @expo/dom-webview ${supported}, found ${official.version}.`);
}

const kotlin = await readFile(path.join(upstream,
  'android/src/main/java/expo/modules/webview/DomWebViewBrowserScripts.kt'), 'utf8');

function scopeBrowserGlobals(script) {
  const registry = 'globalThis.expo.sharedObjectRegistry';
  const init = `${registry} ||= new Map(); `;
  if (!script.includes(init)) {
    throw new Error('Upstream DOM WebView SharedObject registry has changed.');
  }

  // The native wrapper supplies the current document's SharedObject registry.
  const scoped = script.replace(init, '')
    .replaceAll(registry, 'expoDomDocument.sharedObjects')
    .replace('typeof arg === "object" && arg.sharedObjectId', 'arg !== null && typeof arg === "object" && arg.sharedObjectId');

  const start = scoped.indexOf('// browserScripts/InstallGlobals/EventEmitterProxy.ts');
  const end = scoped.indexOf('// browserScripts/InstallGlobals/utils.ts');
  if (start < 0 || end < start) {
    throw new Error('Upstream DOM WebView event proxy boundaries have changed.');
  }

  // A single native subscription multiplexes listeners per document, module and event.
  return scoped.slice(0, start) + String.raw`
class EventEmitterProxy {
  constructor(moduleName) {
    this.moduleName = moduleName;
    this.listeners = new Map();
  }

  addListener = (eventName, listener) => {
    let listeners = this.listeners.get(eventName);
    if (!listeners) {
      const module = JSON.stringify(this.moduleName);
      const event = JSON.stringify(eventName);
      const emit = JSON.stringify('window.ExpoDomWebView.eventEmitterProxy[' + module + '].emit(' + event + ', ...');
      window.ExpoDomWebView.eval(
        '(() => {' +
          'const listener = (...args) => globalThis.expo.modules.ExpoDomWebViewModule.evalJsForWebViewAsync(' +
            webViewId + ', ' + emit + ' + JSON.stringify(args) + ")");' +
          'const subscription = globalThis.expo.modules[' + module + '].addListener(' + event + ', listener);' +
          'let events = expoDomDocument.subscriptions.get(' + module + ');' +
          'if (!events) expoDomDocument.subscriptions.set(' + module + ', events = new Map());' +
          'events.set(' + event + ', subscription);' +
        '})()'
      );

      listeners = new Set();
      this.listeners.set(eventName, listeners);
    }

    listeners.add(listener);
    return { remove: () => this.removeListener(eventName, listener) };
  };

  removeListener = (eventName, listener) => {
    const listeners = this.listeners.get(eventName);
    if (!listeners?.has(listener)) return;

    if (listeners.size === 1) this.removeAllListeners(eventName);
    else listeners.delete(listener);
  };

  removeAllListeners = (eventName) => {
    if (!this.listeners.has(eventName)) return;

    const module = JSON.stringify(this.moduleName);
    const event = JSON.stringify(eventName);
    window.ExpoDomWebView.eval(
      '(() => {' +
        'const events = expoDomDocument.subscriptions.get(' + module + ');' +
        'events?.get(' + event + ')?.remove();' +
        'events?.delete(' + event + ');' +
        'if (events?.size === 0) expoDomDocument.subscriptions.delete(' + module + ');' +
      '})()'
    );

    this.listeners.delete(eventName);
  };

  emit = (eventName, ...args) => {
    for (const listener of new Set(this.listeners.get(eventName))) {
      try {
        listener(...args);
      } catch (error) {
        console.error(error);
      }
    }
  };
}

` + scoped.slice(end);
}

const scripts = ['INSTALL_GLOBALS_SCRIPT', 'NATIVE_EVAL_WRAPPER_SCRIPT'].map((name) => {
  const match = kotlin.match(new RegExp(`internal const val ${name}: String = """([\\s\\S]*?)"""`));
  if (!match) throw new Error(`Missing upstream browser script: ${name}`);

  // Kotlin raw strings escape dollars using a character interpolation.
  const script = match[1].replaceAll('${\'$\'}', '$').trim();
  const body = name === 'INSTALL_GLOBALS_SCRIPT' ? scopeBrowserGlobals(script) : script.replace(/;$/, '');

  return `export const ${name}: string = ${JSON.stringify(body)};`;
});

const output = path.join(root, 'harmony/library/src/main/ets/generated');
await mkdir(output, { recursive: true });

await writeFile(path.join(output, 'DomWebViewBrowserScripts.ets'),
  '// Copyright 2015-present 650 Industries. All rights reserved.\n'
  + `// Generated from @expo/dom-webview ${official.version}; run scripts/sync-browser-scripts.mjs.\n`
  + scripts.join('\n') + '\n');
