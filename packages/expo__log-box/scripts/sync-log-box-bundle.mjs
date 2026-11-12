#!/usr/bin/env node
/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'harmony/library/src/main/resources/rawfile/expo_log_box');
const require = createRequire(import.meta.url);
const manifest = require.resolve('@expo/log-box/package.json');
const { version } = require(manifest);
const expectedVersion = require('../package.json').peerDependencies['@expo/log-box'];
if (version !== expectedVersion) {
  throw new Error(`Expected @expo/log-box ${expectedVersion}, found ${version} at ${manifest}.`);
}
const official = path.dirname(manifest);
const source = path.join(official, 'dist/ExpoLogBox.bundle');

await assertOfficialBundle(source);
const parser = require.resolve('stacktrace-parser');
await rm(output, { recursive: true, force: true });
await mkdir(path.dirname(output), { recursive: true });
await cp(source, output, { recursive: true, force: true });
const generated = path.join(root, 'harmony/library/src/main/ets/generated');
await mkdir(generated, { recursive: true });
await writeFile(path.join(generated, 'ExpoLogBoxScripts.ets'),
  `// Generated from stacktrace-parser; see rawfile/expo_log_box/stacktrace-parser.LICENSE.\nexport const STACK_PARSER_SCRIPT: string = ${JSON.stringify(await readFile(parser, 'utf8'))};\n`);
await cp(path.resolve(path.dirname(parser), '../LICENSE'), path.join(output, 'stacktrace-parser.LICENSE'));

async function assertOfficialBundle(directory) {
  const entry = path.join(directory, 'index.html');
  let index;

  try {
    index = await readFile(entry, 'utf8');
  } catch (error) {
    throw new Error(
      `The installed @expo/log-box package does not contain its prebuilt DOM bundle at ${entry}.`,
      { cause: error }
    );
  }

  const references = Array.from(index.matchAll(/\b(?:href|src)=["']([^"']+)["']/g), match => match[1]);
  if (!references.some(reference => reference.endsWith('.js')) || !references.some(reference => reference.endsWith('.css'))) {
    throw new Error(`The @expo/log-box DOM bundle at ${directory} is incomplete.`);
  }

  for (const reference of references) {
    if (/^[a-z][a-z\d+.-]*:/i.test(reference) || reference.startsWith('//') || reference.startsWith('#')) continue;

    const decoded = decodeURIComponent(reference.split(/[?#]/, 1)[0]);
    const resource = path.resolve(directory, decoded);
    const relative = path.relative(directory, resource);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
      throw new Error(`The @expo/log-box DOM bundle contains an invalid resource path: ${reference}`);
    }

    const info = await stat(resource).catch(() => undefined);
    if (!info?.isFile()) {
      throw new Error(`The @expo/log-box DOM bundle is missing the referenced resource: ${reference}`);
    }
  }
}
