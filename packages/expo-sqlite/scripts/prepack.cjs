/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });

  if (result.error) throw new Error(`${command} could not start: ${result.error.message}`, { cause: result.error });
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.signal})`);
}

run(process.execPath, [path.join(__dirname, 'prepare-native.cjs')]);

const generated = path.join(root, 'harmony/generated');
const manifest = JSON.parse(fs.readFileSync(path.join(generated, 'manifest.json'), 'utf8'));

const required = [
  'vendor/sqlite3.c', 'vendor/sqlite3.h',
  'vendor/sqlcipher/sqlite3.c', 'vendor/sqlcipher/sqlite3.h',
  'vendor/libsql/libsql.h',
  'vendor/sqlite-vec/sqlite-vec.c', 'vendor/sqlite-vec/sqlite-vec.h',
  'vendor/sqlite-vec/sqlite3.h', 'vendor/sqlite-vec/sqlite3ext.h',
  'licenses/libsql-dependencies/index.json',
];

for (const abi of ['arm64-v8a', 'x86_64']) {
  required.push(`prebuilt/${abi}/libsql_experimental.a`, `prebuilt/${abi}/openssl/lib/libcrypto.a`);
}

for (const file of required) {
  if (!manifest.files[file]) throw new Error(`Missing publisher dependency: ${file}`);
}

for (const [relative, expected] of Object.entries(manifest.files)) {
  const file = path.resolve(generated, relative);
  if (!file.startsWith(generated + path.sep)) throw new Error(`Invalid generated path: ${relative}`);

  const actual = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  if (actual !== expected) throw new Error(`Generated checksum mismatch: ${relative}. Rebuild native inputs.`);
}
