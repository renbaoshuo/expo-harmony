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
const scripts = ['INSTALL_GLOBALS_SCRIPT', 'NATIVE_EVAL_WRAPPER_SCRIPT'].map((name) => {
  const match = kotlin.match(new RegExp(`internal const val ${name}: String = """([\\s\\S]*?)"""`));
  if (!match) throw new Error(`Missing upstream browser script: ${name}`);

  // Kotlin raw strings escape dollars using a character interpolation.
  return `export const ${name}: string = ${JSON.stringify(match[1].replaceAll('${\'$\'}', '$'))};`;
});

const output = path.join(root, 'harmony/library/src/main/ets/generated');
await mkdir(output, { recursive: true });

await writeFile(path.join(output, 'DomWebViewBrowserScripts.ets'),
  '// Copyright 2015-present 650 Industries. All rights reserved.\n'
  + `// Generated from @expo/dom-webview ${official.version}; run scripts/sync-browser-scripts.mjs.\n`
  + scripts.join('\n') + '\n');
