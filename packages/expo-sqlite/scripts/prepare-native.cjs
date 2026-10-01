#!/usr/bin/env node
// Maintainer/CI preparation. Never runs during consumer installation or app builds.
//
// Requires Node >= 20, Git, the Harmony SDK (OHOS_NDK_HOME or DEVECO_SDK_HOME),
// Rust 1.85.1 via rustup (with the OHOS targets below), plus perl, make and tclsh
// for the sqlite/openssl steps. On Windows those POSIX tools must be on PATH
// (MSYS2 or Git for Windows work); tar.exe ships with Windows 10+.
'use strict';

const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const os = require('node:os');
const { isDeepStrictEqual } = require('node:util');
const { spawnSync } = require('node:child_process');

const PACKAGE = path.resolve(__dirname, '..');
const SOURCES = path.join(PACKAGE, 'third-party');
const OUTPUT = path.join(PACKAGE, 'harmony', 'generated');
const RUST = '1.85.1';
const ABIS = [
  ['arm64-v8a', 'aarch64-unknown-linux-ohos', 'aarch64-linux-ohos', 'linux-aarch64'],
  ['x86_64', 'x86_64-unknown-linux-ohos', 'x86_64-linux-ohos', 'linux-x86_64'],
];
const WINDOWS = process.platform === 'win32';

function compare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function isFile(file) {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

function resolvePath(file) {
  try {
    return fs.realpathSync(file);
  } catch {
    return path.resolve(file);
  }
}

function relativePosix(from, to) {
  return path.relative(from, to).split(path.sep).join('/');
}

function walkFiles(root) {
  const files = [];
  const visit = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile()) files.push(relativePosix(root, full));
    }
  };
  visit(root);
  return files.sort(compare);
}

function run(command, options = {}) {
  const result = spawnSync(String(command[0]), command.slice(1).map(String), {
    cwd: options.cwd ?? PACKAGE,
    env: options.env,
    stdio: ['inherit', options.capture ? 'pipe' : 'inherit', 'inherit'],
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw new Error(`${command[0]} could not start: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`${command.join(' ')} failed (${result.status ?? result.signal})`);
  return result.stdout ?? '';
}

function digest(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function copy(source, target) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

// SDK binaries are .exe on Windows; keep the suffix on every use so spawn and
// env-derived invocations (AR_*, CC_*) resolve identically.
function sdkTool(sdk, relative) {
  const file = path.join(sdk, relative);
  return WINDOWS ? `${file}.exe` : file;
}

// MSYS perl cannot resolve a Windows-style $0: FindBin falls back to the
// working directory, so OpenSSL's `use lib "$FindBin::Bin/util/perl"` points
// at the build dir and Configure cannot find its OpenSSL/fallback.pm.
//
// MSYS sh also strips backslashes as escapes, and OpenSSL's Configure copies
// unknown options (--sysroot=) and CC/AR/RANLIB from the environment straight
// into the generated Makefile. Every path that MSYS consumes must therefore be
// POSIX form (D:\a\b -> /d/a/b); the MSYS runtime converts it back to a Windows
// path when it execs the native clang/ar/ranlib binaries.
function posixPath(file) {
  if (!WINDOWS) return file;
  const full = path.resolve(file);
  return `/${full[0].toLowerCase()}/${full.slice(3).replaceAll('\\', '/')}`;
}

// MSYS make and sh split unquoted compiler paths on spaces, and OpenSSL's
// generated Makefile carries CC/AR/RANLIB and --sysroot as plain words, so a
// SDK under "Program Files" cannot be used directly. Windows junctions need no
// privileges and resolve transparently, so expose a space-free alias instead of
// quoting every path through Configure, configdata and Makefile.
function sdkAlias(sdk, cache) {
  if (!WINDOWS || !sdk.includes(' ')) return sdk;

  const link = path.join(cache, 'sdk');
  // A junction inside a spaced repository path would defeat the purpose.
  if (link.includes(' ')) {
    throw new Error(`SDK alias still contains a space: ${link}. Move the repository to a path without spaces.`);
  }

  fs.mkdirSync(cache, { recursive: true });
  if (!fs.existsSync(link)) {
    try {
      fs.symlinkSync(sdk, link, 'junction');
    } catch (error) {
      // A concurrent build may have created it first; fall through and verify.
      if (!fs.existsSync(link)) throw error;
    }
  }

  // Never remove the existing link: a mistake here would delete the SDK.
  if (resolvePath(link) !== resolvePath(sdk)) return sdk;
  return link;
}

function submodules(root) {
  const gitmodules = path.join(root, '.gitmodules');
  const entries = run(
    ['git', 'config', '-f', gitmodules, '--get-regexp', '^submodule\\.expo-sqlite-.+\\.path$'],
    { capture: true }
  );
  if (!entries.trim()) throw new Error('No expo-sqlite submodules found in .gitmodules');

  const found = [];
  for (const entry of entries.trim().split(/\r?\n/)) {
    const at = entry.indexOf(' ');
    const key = entry.slice(0, at);
    const relative = entry.slice(at + 1);
    const name = key.slice('submodule.expo-sqlite-'.length, -'.path'.length);
    const url = run(['git', 'config', '-f', gitmodules, '--get', `submodule.expo-sqlite-${name}.url`], {
      capture: true,
    }).trim();
    const stage = run(['git', 'ls-files', '--stage', relative], { cwd: root, capture: true })
      .trim()
      .split(/\s+/);
    if (stage.length < 2 || stage[0] !== '160000') {
      throw new Error(`Submodule is not pinned in the index: ${relative}`);
    }
    found.push({ name, relative, url, commit: stage[1] });
  }
  return found;
}

function prepareSubmodules() {
  const root = run(['git', 'rev-parse', '--show-toplevel'], { capture: true }).trim();
  const metadata = run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], {
    capture: true,
  }).trim();
  const pins = {};

  for (const { name, relative, url, commit } of submodules(root)) {
    const source = path.join(SOURCES, name);
    if (resolvePath(path.join(root, relative)) !== resolvePath(source)) {
      throw new Error(`Unexpected submodule path: ${relative}`);
    }
    pins[name] = commit;

    if (!fs.existsSync(path.join(source, '.git'))) {
      if (fs.existsSync(source) && fs.readdirSync(source).length > 0) {
        throw new Error(`Refusing to replace nonempty source directory: ${source}`);
      }

      const module = path.join(metadata, 'modules', `expo-sqlite-${name}`);
      if (fs.existsSync(module)) {
        fs.mkdirSync(source, { recursive: true });
        // git expects a forward-slash gitdir pointer on every platform.
        fs.writeFileSync(path.join(source, '.git'), `gitdir: ${module.split(path.sep).join('/')}\n`);
        run(['git', '--git-dir', module, 'config', 'core.worktree', source]);
      } else {
        fs.mkdirSync(path.dirname(module), { recursive: true });
        run([
          'git', 'clone', '--depth', '1', '--no-checkout', '--filter=blob:none',
          '--separate-git-dir', module, url, source,
        ]);
      }

      run(['git', 'fetch', '--depth', '1', 'origin', commit], { cwd: source });
      // Only this newly created, empty worktree may be populated forcibly.
      run(['git', 'checkout', '--force', '--detach', commit], { cwd: source });
    }

    const head = run(['git', 'rev-parse', 'HEAD'], { cwd: source, capture: true }).trim();
    if (head !== commit) {
      throw new Error(`${name}: expected ${commit}, found ${head}; check out the locked commit`);
    }
    if (run(['git', 'status', '--porcelain'], { cwd: source, capture: true }).trim()) {
      throw new Error(`${name}: submodule has local changes; refusing to build or modify them`);
    }
  }

  return pins;
}

function snapshot(name, commit, work) {
  const dest = path.join(work, name);
  fs.mkdirSync(dest);

  const archive = path.join(work, `${name}.tar`);
  run(['git', 'archive', '--format=tar', '-o', archive, commit], { cwd: path.join(SOURCES, name) });
  run(['tar', '-xf', archive, '-C', dest]);
  fs.unlinkSync(archive);

  const patches = fs
    .readdirSync(path.join(PACKAGE, 'patches'))
    .filter((file) => file.startsWith(`${name}-`) && file.endsWith('.patch'))
    .sort(compare);
  for (const patch of patches.map((file) => path.join(PACKAGE, 'patches', file))) {
    run(['git', 'apply', '--check', patch], { cwd: dest });
    run(['git', 'apply', patch], { cwd: dest });
  }

  return dest;
}

function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function prefixSqlite(directory) {
  // Expo MIT scripts/replace_symbols.ts: retain precisely its API/struct symbol set.
  const header = fs.readFileSync(path.join(directory, 'sqlite3.h'), 'utf8');
  const symbols = new Set();
  for (const match of header.matchAll(/(SQLITE_API .+? \*?)(ex)?((sqlite3_|sqlite3session_|sqlite3changeset_).+?)\(/g)) {
    symbols.add(match[3]);
  }
  for (const match of header.matchAll(/\bstruct\s+?(ex)?(sqlite3_\w+)/g)) {
    symbols.add(match[2]);
  }
  const pattern = new RegExp(`\\b(?:${[...symbols].sort(compare).map(escapeRegex).join('|')})\\b`, 'g');

  for (const name of ['sqlite3.c', 'sqlite3.h']) {
    const file = path.join(directory, name);
    fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replace(pattern, (match) => 'ex' + match));
  }
}

// Python string.Template.substitute semantics: $$, $name and ${name}.
function substitute(text, values) {
  return text.replace(/\$(\$|\{(\w+)\}|(\w+))/g, (match, escaped, braced, plain) => {
    if (escaped === '$') return '$';
    const name = braced ?? plain;
    if (!Object.prototype.hasOwnProperty.call(values, name)) {
      throw new Error(`Invalid placeholder in template: ${match}`);
    }
    return values[name];
  });
}

function configure(source) {
  run(WINDOWS ? ['sh', './configure'] : ['./configure'], { cwd: source });
}

function amalgamations(sources, pins, output) {
  copy(path.join(PACKAGE, 'scripts', 'EXPO-LICENSE'), path.join(output, 'licenses', 'expo', 'LICENSE'));
  const vendor = path.join(output, 'vendor');

  for (const name of ['sqlite', 'sqlcipher']) {
    const source = sources[name];
    configure(source);
    run(['make', 'sqlite3.c'], { cwd: source });
    const dest = name === 'sqlite' ? vendor : path.join(vendor, name);
    for (const file of ['sqlite3.c', 'sqlite3.h']) {
      copy(path.join(source, file), path.join(dest, file));
    }
    prefixSqlite(dest);
  }

  const vec = sources['sqlite-vec'];
  // Pin the generated header date to the commit, not the checkout time.
  const stamp = Number(
    run(['git', 'show', '-s', '--format=%ct', pins['sqlite-vec']], {
      cwd: path.join(SOURCES, 'sqlite-vec'),
      capture: true,
    }).trim()
  );
  const version = fs.readFileSync(path.join(vec, 'VERSION'), 'utf8').trim();
  const parts = version.split('-')[0].split('.');
  const header = substitute(fs.readFileSync(path.join(vec, 'sqlite-vec.h.tmpl'), 'utf8'), {
    VERSION: version,
    VERSION_MAJOR: parts[0],
    VERSION_MINOR: parts[1],
    VERSION_PATCH: parts[2],
    DATE: new Date(stamp * 1000).toISOString().slice(0, 19) + 'Z+0000',
    SOURCE: pins['sqlite-vec'],
  });

  copy(path.join(vec, 'sqlite-vec.c'), path.join(vendor, 'sqlite-vec', 'sqlite-vec.c'));
  fs.writeFileSync(path.join(vendor, 'sqlite-vec', 'sqlite-vec.h'), header);
  for (const file of ['sqlite3.h', 'sqlite3ext.h']) {
    copy(path.join(sources['sqlite'], file), path.join(vendor, 'sqlite-vec', file));
  }
  copy(path.join(sources['libsql'], 'bindings', 'c', 'include', 'libsql.h'), path.join(vendor, 'libsql', 'libsql.h'));

  const licenses = {
    sqlite: ['LICENSE.md'],
    sqlcipher: ['LICENSE.md', 'LICENSE.txt'],
    'sqlite-vec': ['LICENSE-MIT', 'LICENSE-APACHE'],
    libsql: ['LICENSE.md'],
    openssl: ['LICENSE.txt'],
  };
  for (const [name, files] of Object.entries(licenses)) {
    for (const file of files) {
      copy(path.join(sources[name], file), path.join(output, 'licenses', name, file));
    }
  }
}

function shellQuote(token) {
  // Same safe/unsafe split as Python shlex.quote.
  return /^[\w@%+=:,./-]+$/.test(token) ? token : `'${token.replaceAll("'", `'\\''`)}'`;
}

function batchQuote(token) {
  // cmd.exe metacharacters need double quotes; % and " cannot be represented here.
  if (token.includes('%') || token.includes('"')) throw new Error(`Cannot quote for cmd.exe: ${token}`);
  return /[\s&|<>()^!]/.test(token) ? `"${token}"` : token;
}

function writeCompilerWrapper(work, rustTarget, compiler, sdk, clangTarget) {
  const command = [
    sdkTool(sdk, path.join('llvm', 'bin', compiler)),
    `--target=${clangTarget}`,
    `--sysroot=${path.join(sdk, 'sysroot')}`,
    '-D__MUSL__',
    '-D__OHOS_API__=13',
  ];

  if (WINDOWS) {
    const wrapper = path.join(work, `${rustTarget}-${compiler}.bat`);
    fs.writeFileSync(wrapper, `@${command.map(batchQuote).join(' ')} %*\r\n`);
    // The path is published as CC_<target>/CARGO_TARGET_*_LINKER. cargo, rustc
    // and cc-rs accept forward slashes, and libsql-ffi copies the value verbatim
    // into toolchain.cmake as `set(CMAKE_C_COMPILER <value>)`, where CMake reads
    // backslashes as escape sequences and rejects the path.
    return wrapper.replaceAll('\\', '/');
  }

  const wrapper = path.join(work, `${rustTarget}-${compiler}`);
  fs.writeFileSync(wrapper, `#!/bin/sh\nexec ${command.map(shellQuote).join(' ')} "$@"\n`);
  fs.chmodSync(wrapper, 0o755);
  return wrapper;
}

function nativeLibraries(sources, sdk, work, output) {
  const base = {
    ...process.env,
    RUSTUP_TOOLCHAIN: RUST,
    CARGO_PROFILE_RELEASE_DEBUG: 'false',
    CARGO_PROFILE_RELEASE_STRIP: 'symbols',
    CARGO_TARGET_DIR: path.join(work, 'cargo-target'),
  };
  // Host package-manager flags must not leak into OHOS dependencies.
  for (const key of ['CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS']) {
    delete base[key];
  }
  // libsql-ffi drives cmake with CMAKE_SYSTEM_NAME=Linux plus the OHOS clang
  // wrapper as CMAKE_C_COMPILER. On Windows cmake defaults to the Visual Studio
  // generator, which ignores a cross toolchain and builds the try-compile
  // project with MSBuild/cl.exe instead. Use the MSYS make this script already
  // requires, and keep an explicitly provided generator.
  if (WINDOWS && !base.CMAKE_GENERATOR) base.CMAKE_GENERATOR = 'Unix Makefiles';

  for (const [abi, rustTarget, clangTarget, opensslTarget] of ABIS) {
    const build = path.join(work, `openssl-${abi}`);
    fs.mkdirSync(build);
    const prefix = path.join(build, 'install');
    const env = {
      ...base,
      CC: posixPath(sdkTool(sdk, path.join('llvm', 'bin', 'clang'))),
      AR: posixPath(sdkTool(sdk, path.join('llvm', 'bin', 'llvm-ar'))),
      RANLIB: posixPath(sdkTool(sdk, path.join('llvm', 'bin', 'llvm-ranlib'))),
    };

    run(
      [
        'perl', posixPath(path.join(sources['openssl'], 'Configure')), opensslTarget, 'no-shared', 'no-tests', 'no-module',
        '--libdir=lib', '--prefix=/', '--openssldir=/etc/ssl', `--target=${clangTarget}`,
        `--sysroot=${posixPath(path.join(sdk, 'sysroot'))}`, '-D__OHOS_API__=13', '-fPIC', '-fvisibility=hidden',
      ],
      { cwd: build, env }
    );
    run(['make', `-j${Math.min(os.cpus().length || 2, 8)}`, 'build_libs'], { cwd: build, env });
    run(['make', 'install_dev', `DESTDIR=${posixPath(prefix)}`], { cwd: build, env });

    const dest = path.join(output, 'prebuilt', abi);
    fs.cpSync(path.join(prefix, 'include'), path.join(dest, 'openssl', 'include'), { recursive: true });
    copy(path.join(prefix, 'lib', 'libcrypto.a'), path.join(dest, 'openssl', 'lib', 'libcrypto.a'));

    const cargoEnv = { ...base };
    for (const [language, compiler] of [
      ['CC', 'clang'],
      ['CXX', 'clang++'],
    ]) {
      const wrapper = writeCompilerWrapper(work, rustTarget, compiler, sdk, clangTarget);
      cargoEnv[`${language}_${rustTarget.replaceAll('-', '_')}`] = wrapper;
      if (language === 'CC') {
        cargoEnv[`CARGO_TARGET_${rustTarget.toUpperCase().replaceAll('-', '_')}_LINKER`] = wrapper;
      }
    }
    cargoEnv[`AR_${rustTarget.replaceAll('-', '_')}`] = sdkTool(sdk, path.join('llvm', 'bin', 'llvm-ar'));

    run(['cargo', 'build', '--locked', '--release', '--target', rustTarget], {
      cwd: path.join(sources['libsql'], 'bindings', 'c'),
      env: cargoEnv,
    });
    copy(
      path.join(work, 'cargo-target', rustTarget, 'release', 'libsql_experimental.a'),
      path.join(dest, 'libsql_experimental.a')
    );
  }

  dependencyNotices(sources['libsql'], path.join(output, 'licenses', 'libsql-dependencies'), base);
}

function dependencyNotices(source, output, env) {
  const packages = {};
  for (const [, target] of ABIS) {
    const metadata = JSON.parse(
      run(['cargo', 'metadata', '--locked', '--format-version', '1', '--filter-platform', target], {
        cwd: path.join(source, 'bindings', 'c'),
        env,
        capture: true,
      })
    );
    const nodes = new Map(metadata.resolve.nodes.map((node) => [node.id, node]));
    const pending = [metadata.resolve.root];
    const seen = new Set();

    while (pending.length) {
      const key = pending.pop();
      if (seen.has(key)) continue;

      seen.add(key);
      pending.push(
        ...nodes
          .get(key)
          .deps.filter((dependency) => dependency.dep_kinds.some((kind) => kind.kind !== 'dev'))
          .map((dependency) => dependency.pkg)
      );
    }
    for (const p of metadata.packages) if (seen.has(p.id)) packages[p.id] = p;
  }

  const notices = [];
  const ordered = Object.values(packages).sort((a, b) =>
    a.name === b.name ? compare(a.version, b.version) : compare(a.name, b.name)
  );
  for (const p of ordered) {
    const root = path.dirname(p.manifest_path);
    let files = fs
      .readdirSync(root, { withFileTypes: true })
      .filter((entry) => entry.isFile() && /^(licen[cs]e|copying|notice|unlicense)/i.test(entry.name))
      .map((entry) => path.join(root, entry.name));
    if (p.license_file) files.push(path.join(root, p.license_file));
    if (files.length === 0 && p.source === null) files = [path.join(source, 'LICENSE.md')];
    if (files.length === 0 && p.name === 'prost' && p.version === '0.12.6') {
      // Upstream prost workspace ships this shared MIT license only in prost-derive.
      const sibling = Object.values(packages).find((v) => v.name === 'prost-derive' && v.version === p.version);
      files = [path.join(path.dirname(sibling.manifest_path), 'LICENSE')];
    }
    if (files.length === 0) throw new Error(`Missing upstream license text: ${p.name} ${p.version}`);

    for (const file of new Set(files)) {
      copy(file, path.join(output, `${p.name}-${p.version}`, path.basename(file)));
    }
    notices.push({
      name: p.name,
      version: p.version,
      license: p.license,
      repository: p.repository,
      notices: [...new Set(files.map((file) => path.basename(file)))].sort(compare),
    });
  }

  fs.writeFileSync(path.join(output, 'index.json'), JSON.stringify(notices, null, 2) + '\n');
}

function validOutput(recipe) {
  try {
    const manifest = JSON.parse(fs.readFileSync(path.join(OUTPUT, 'manifest.json'), 'utf8'));
    const actual = {};
    for (const file of walkFiles(OUTPUT)) {
      if (file !== 'manifest.json') actual[file] = digest(path.join(OUTPUT, file));
    }

    return isDeepStrictEqual(manifest.recipe, recipe) && Object.keys(actual).length > 0 && isDeepStrictEqual(actual, manifest.files);
  } catch {
    return false;
  }
}

function usage() {
  console.error('usage: prepare-native.cjs [-h] [--sdk SDK] [--clean]');
  console.error('');
  console.error('options:');
  console.error('  -h, --help     show this help message and exit');
  console.error('  --sdk SDK      path to the Harmony native SDK');
  console.error('  --clean        regenerate every artifact in a fresh temporary build directory');
}

function fail(message) {
  usage();
  console.error(`prepare-native.cjs: error: ${message}`);
  process.exit(2);
}

function parseArguments(argv) {
  const args = { sdk: process.env.OHOS_NDK_HOME || null, clean: false };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      usage();
      process.exit(0);
    } else if (arg === '--sdk') {
      if (index + 1 >= argv.length) fail('argument --sdk: expected one argument');
      args.sdk = argv[++index];
    } else if (arg.startsWith('--sdk=')) {
      args.sdk = arg.slice('--sdk='.length);
    } else if (arg === '--clean') {
      args.clean = true;
    } else {
      fail(`unrecognized arguments: ${arg}`);
    }
  }
  return args;
}

function main() {
  const args = parseArguments(process.argv.slice(2));

  let sdk = args.sdk;
  if (!sdk && process.env.DEVECO_SDK_HOME) {
    sdk = path.join(process.env.DEVECO_SDK_HOME, 'default', 'openharmony', 'native');
  }
  if (!sdk || !isFile(sdkTool(sdk, path.join('llvm', 'bin', 'clang')))) {
    fail('Set OHOS_NDK_HOME or DEVECO_SDK_HOME to the Harmony SDK');
  }

  sdk = sdkAlias(resolvePath(sdk), path.join(PACKAGE, 'harmony', '.native-build'));
  const pins = prepareSubmodules();

  const inputs = [
    ...fs
      .readdirSync(path.join(PACKAGE, 'patches'))
      .sort(compare)
      .map((file) => path.join(PACKAGE, 'patches', file)),
    path.join(PACKAGE, 'scripts', 'EXPO-LICENSE'),
    __filename,
  ];
  const recipe = {
    inputs: Object.fromEntries(
      inputs.filter(isFile).map((file) => [relativePosix(PACKAGE, file), digest(file)])
    ),
    submodules: pins,
    compiler: run([sdkTool(sdk, path.join('llvm', 'bin', 'clang')), '--version'], { capture: true }),
    sdk: digest(path.join(sdk, 'oh-uni-package.json')),
    sdkApi: 13,
    rustToolchain: RUST,
  };
  if (!args.clean && validOutput(recipe)) {
    console.log('[expo-sqlite] Generated native inputs verified; reusing maintainer build.');
    return;
  }

  run(['cargo', '--version'], { env: { ...process.env, RUSTUP_TOOLCHAIN: RUST } });
  const cache = path.join(PACKAGE, 'harmony', '.native-build');
  fs.mkdirSync(cache, { recursive: true });
  const temp = fs.mkdtempSync(path.join(cache, 'prepare-'));
  try {
    const generated = path.join(temp, 'generated');
    const sources = {};
    for (const [name, commit] of Object.entries(pins)) sources[name] = snapshot(name, commit, temp);

    amalgamations(sources, pins, generated);
    nativeLibraries(sources, sdk, temp, generated);

    const files = Object.fromEntries(
      walkFiles(generated).map((file) => [file, digest(path.join(generated, file))])
    );
    fs.writeFileSync(
      path.join(generated, 'manifest.json'),
      JSON.stringify({ sources: pins, recipe, files }, null, 2) + '\n'
    );

    fs.rmSync(OUTPUT, { recursive: true, force: true });
    fs.renameSync(generated, OUTPUT);
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }

  console.log('[expo-sqlite] Generated amalgamations, dual-ABI dependencies and licenses.');
}

module.exports = {
  ABIS,
  amalgamations,
  dependencyNotices,
  digest,
  main,
  nativeLibraries,
  posixPath,
  prefixSqlite,
  prepareSubmodules,
  run,
  sdkAlias,
  snapshot,
  substitute,
  validOutput,
  writeCompilerWrapper,
};

if (require.main === module) main();
