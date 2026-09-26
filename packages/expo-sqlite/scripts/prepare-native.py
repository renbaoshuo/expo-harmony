#!/usr/bin/env python3
"""Maintainer/CI preparation. Never runs during consumer installation or app builds."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import string
import subprocess
import tempfile

PACKAGE = Path(__file__).resolve().parent.parent
SOURCES = PACKAGE / 'third-party'
OUTPUT = PACKAGE / 'harmony/generated'
RUST = '1.85.1'
ABIS = [('arm64-v8a', 'aarch64-unknown-linux-ohos', 'aarch64-linux-ohos', 'linux-aarch64'),
        ('x86_64', 'x86_64-unknown-linux-ohos', 'x86_64-linux-ohos', 'linux-x86_64')]


def run(command, cwd=PACKAGE, env=None, capture=False):
    return subprocess.run([str(arg) for arg in command], cwd=cwd, env=env, check=True,
                          stdout=subprocess.PIPE if capture else None, text=True).stdout


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def submodules(root):
    """Yield (name, path, url, commit) for every expo-sqlite submodule pinned in the index."""
    entries = run(['git', 'config', '-f', root / '.gitmodules', '--get-regexp',
                   r'^submodule\.expo-sqlite-.+\.path$'], capture=True)
    if not entries.strip():
        raise ValueError('No expo-sqlite submodules found in .gitmodules')

    for entry in entries.strip().splitlines():
        key, relative = entry.split(' ', 1)
        name = key[len('submodule.expo-sqlite-'):-len('.path')]
        url = run(['git', 'config', '-f', root / '.gitmodules', '--get',
                   f'submodule.expo-sqlite-{name}.url'], capture=True).strip()
        stage = run(['git', 'ls-files', '--stage', relative], root, capture=True).split()
        if len(stage) < 2 or stage[0] != '160000':
            raise ValueError(f'Submodule is not pinned in the index: {relative}')

        yield name, relative, url, stage[1]


def prepare_submodules():
    root = Path(run(['git', 'rev-parse', '--show-toplevel'], capture=True).strip())
    metadata = Path(run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], capture=True).strip())
    pins = {}

    for name, relative, url, commit in submodules(root):
        source = SOURCES / name
        if (root / relative).resolve() != source:
            raise ValueError(f'Unexpected submodule path: {relative}')
        pins[name] = commit

        if not (source / '.git').exists():
            if source.exists() and any(source.iterdir()):
                raise ValueError(f'Refusing to replace nonempty source directory: {source}')

            module = metadata / 'modules' / f'expo-sqlite-{name}'
            if module.exists():
                source.mkdir(exist_ok=True)
                (source / '.git').write_text('gitdir: ' + str(module) + '\n')
                run(['git', '--git-dir', module, 'config', 'core.worktree', source])
            else:
                module.parent.mkdir(parents=True, exist_ok=True)
                run(['git', 'clone', '--depth', '1', '--no-checkout', '--filter=blob:none',
                     '--separate-git-dir', module, url, source])

            run(['git', 'fetch', '--depth', '1', 'origin', commit], source)
            # Only this newly created, empty worktree may be populated forcibly.
            run(['git', 'checkout', '--force', '--detach', commit], source)

        head = run(['git', 'rev-parse', 'HEAD'], source, capture=True).strip()
        if head != commit:
            raise ValueError(f'{name}: expected {commit}, found {head}; check out the locked commit')
        if run(['git', 'status', '--porcelain'], source, capture=True).strip():
            raise ValueError(f'{name}: submodule has local changes; refusing to build or modify them')

    return pins


def snapshot(name, commit, work):
    dest = work / name
    dest.mkdir()

    archive = work / (name + '.tar')
    run(['git', 'archive', '--format=tar', '-o', archive, commit], SOURCES / name)
    run(['tar', '-xf', archive, '-C', dest])
    archive.unlink()

    for patch in sorted((PACKAGE / 'patches').glob(name + '-*.patch')):
        run(['git', 'apply', '--check', patch], dest)
        run(['git', 'apply', patch], dest)

    return dest


def prefix_sqlite(directory):
    # Expo MIT scripts/replace_symbols.ts: retain precisely its API/struct symbol set.
    header = (directory / 'sqlite3.h').read_text()
    symbols = {m[2] for m in re.findall(r'(SQLITE_API .+? \*?)(ex)?((sqlite3_|sqlite3session_|sqlite3changeset_).+?)\(', header)}
    symbols.update(m[1] for m in re.findall(r'\bstruct\s+?(ex)?(sqlite3_\w+)', header))
    pattern = re.compile(r'\b(?:' + '|'.join(re.escape(s) for s in sorted(symbols)) + r')\b')

    for name in ['sqlite3.c', 'sqlite3.h']:
        file = directory / name
        file.write_text(pattern.sub(lambda m: 'ex' + m[0], file.read_text()))


def amalgamations(sources, pins, output):
    copy(PACKAGE / 'scripts/EXPO-LICENSE', output / 'licenses/expo/LICENSE')
    vendor = output / 'vendor'

    for name in ['sqlite', 'sqlcipher']:
        source = sources[name]
        run(['./configure'], source)
        run(['make', 'sqlite3.c'], source)
        dest = vendor if name == 'sqlite' else vendor / name
        for file in ['sqlite3.c', 'sqlite3.h']:
            copy(source / file, dest / file)
        prefix_sqlite(dest)

    vec = sources['sqlite-vec']
    # Pin the generated header date to the commit, not the checkout time.
    stamp = int(run(['git', 'show', '-s', '--format=%ct', pins['sqlite-vec']], SOURCES / 'sqlite-vec', capture=True))
    version = (vec / 'VERSION').read_text().strip()
    parts = version.split('-')[0].split('.')
    header = string.Template((vec / 'sqlite-vec.h.tmpl').read_text()).substitute(
        VERSION=version, VERSION_MAJOR=parts[0], VERSION_MINOR=parts[1], VERSION_PATCH=parts[2],
        DATE=datetime.fromtimestamp(stamp, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ+0000'),
        SOURCE=pins['sqlite-vec'])

    copy(vec / 'sqlite-vec.c', vendor / 'sqlite-vec/sqlite-vec.c')
    (vendor / 'sqlite-vec/sqlite-vec.h').write_text(header)
    for file in ['sqlite3.h', 'sqlite3ext.h']:
        copy(sources['sqlite'] / file, vendor / 'sqlite-vec' / file)
    copy(sources['libsql'] / 'bindings/c/include/libsql.h', vendor / 'libsql/libsql.h')

    for name, files in {'sqlite': ['LICENSE.md'], 'sqlcipher': ['LICENSE.md', 'LICENSE.txt'],
                        'sqlite-vec': ['LICENSE-MIT', 'LICENSE-APACHE'], 'libsql': ['LICENSE.md'],
                        'openssl': ['LICENSE.txt']}.items():
        for file in files:
            copy(sources[name] / file, output / 'licenses' / name / file)


def native_libraries(sources, sdk, work, output):
    base = dict(os.environ, RUSTUP_TOOLCHAIN=RUST, CARGO_PROFILE_RELEASE_DEBUG='false',
                CARGO_PROFILE_RELEASE_STRIP='symbols', CARGO_TARGET_DIR=str(work / 'cargo-target'))
    # Host package-manager flags must not leak into OHOS dependencies.
    for key in ['CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS']:
        base.pop(key, None)

    for abi, rust_target, clang_target, openssl_target in ABIS:
        build = work / ('openssl-' + abi)
        build.mkdir()
        prefix = build / 'install'
        env = dict(base, CC=str(sdk / 'llvm/bin/clang'), AR=str(sdk / 'llvm/bin/llvm-ar'),
                   RANLIB=str(sdk / 'llvm/bin/llvm-ranlib'))

        run(['perl', sources['openssl'] / 'Configure', openssl_target, 'no-shared', 'no-tests', 'no-module',
             '--libdir=lib', '--prefix=/', '--openssldir=/etc/ssl', '--target=' + clang_target,
             '--sysroot=' + str(sdk / 'sysroot'), '-D__OHOS_API__=13', '-fPIC', '-fvisibility=hidden'], build, env)
        run(['make', '-j' + str(min(os.cpu_count() or 2, 8)), 'build_libs'], build, env)
        run(['make', 'install_dev', 'DESTDIR=' + str(prefix)], build, env)

        dest = output / 'prebuilt' / abi
        shutil.copytree(prefix / 'include', dest / 'openssl/include')
        copy(prefix / 'lib/libcrypto.a', dest / 'openssl/lib/libcrypto.a')

        env = dict(base)
        for language, compiler in [('CC', 'clang'), ('CXX', 'clang++')]:
            wrapper = work / (rust_target + '-' + compiler)
            command = [str(sdk / ('llvm/bin/' + compiler)), '--target=' + clang_target,
                       '--sysroot=' + str(sdk / 'sysroot'), '-D__MUSL__', '-D__OHOS_API__=13']
            wrapper.write_text('#!/bin/sh\nexec ' + shlex.join(command) + ' "$@"\n')
            wrapper.chmod(0o755)
            env[language + '_' + rust_target.replace('-', '_')] = str(wrapper)
            if language == 'CC':
                env['CARGO_TARGET_' + rust_target.upper().replace('-', '_') + '_LINKER'] = str(wrapper)
        env['AR_' + rust_target.replace('-', '_')] = str(sdk / 'llvm/bin/llvm-ar')

        run(['cargo', 'build', '--locked', '--release', '--target', rust_target], sources['libsql'] / 'bindings/c', env)
        copy(work / 'cargo-target' / rust_target / 'release/libsql_experimental.a', dest / 'libsql_experimental.a')

    dependency_notices(sources['libsql'], output / 'licenses/libsql-dependencies', base)


def dependency_notices(source, output, env):
    packages = {}
    for _, target, _, _ in ABIS:
        metadata = json.loads(run(['cargo', 'metadata', '--locked', '--format-version', '1', '--filter-platform', target], source / 'bindings/c', env, capture=True))
        nodes = {n['id']: n for n in metadata['resolve']['nodes']}
        pending, seen = [metadata['resolve']['root']], set()

        while pending:
            key = pending.pop()
            if key in seen:
                continue

            seen.add(key)
            pending.extend(d['pkg'] for d in nodes[key]['deps'] if any(k['kind'] != 'dev' for k in d['dep_kinds']))
        packages.update({p['id']: p for p in metadata['packages'] if p['id'] in seen})

    notices = []
    for p in sorted(packages.values(), key=lambda p: (p['name'], p['version'])):
        root = Path(p['manifest_path']).parent
        files = [f for f in root.iterdir() if f.is_file() and re.match(r'^(licen[cs]e|copying|notice|unlicense)', f.name, re.I)]
        if p['license_file']:
            files.append(root / p['license_file'])
        if not files and p['source'] is None:
            files = [source / 'LICENSE.md']
        if not files and p['name'] == 'prost' and p['version'] == '0.12.6':
            # Upstream prost workspace ships this shared MIT license only in prost-derive.
            sibling = next(v for v in packages.values() if v['name'] == 'prost-derive' and v['version'] == p['version'])
            files = [Path(sibling['manifest_path']).parent / 'LICENSE']
        if not files:
            raise ValueError(f'Missing upstream license text: {p["name"]} {p["version"]}')

        for file in set(files):
            copy(file, output / (p['name'] + '-' + p['version']) / file.name)
        notices.append({key: p[key] for key in ['name', 'version', 'license', 'repository']} | {'notices': sorted({f.name for f in files})})

    (output / 'index.json').write_text(json.dumps(notices, indent=2) + '\n')


def valid_output(recipe):
    try:
        manifest = json.loads((OUTPUT / 'manifest.json').read_text())
        actual = {str(f.relative_to(OUTPUT)): digest(f) for f in sorted(OUTPUT.rglob('*')) if f.is_file() and f != OUTPUT / 'manifest.json'}

        return manifest['recipe'] == recipe and bool(actual) and actual == manifest['files']
    except (OSError, ValueError, KeyError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, default=os.environ.get('OHOS_NDK_HOME'))
    parser.add_argument('--clean', action='store_true', help='Regenerate every artifact in a fresh temporary build directory')
    args = parser.parse_args()

    sdk = args.sdk
    if not sdk and os.environ.get('DEVECO_SDK_HOME'):
        sdk = Path(os.environ['DEVECO_SDK_HOME']) / 'default/openharmony/native'
    if not sdk or not (sdk / 'llvm/bin/clang').is_file():
        parser.error('Set OHOS_NDK_HOME or DEVECO_SDK_HOME to the Harmony SDK')

    sdk = sdk.resolve()
    pins = prepare_submodules()

    inputs = [*sorted((PACKAGE / 'patches').glob('*')),
              PACKAGE / 'scripts/EXPO-LICENSE', Path(__file__)]
    recipe = {'inputs': {str(f.relative_to(PACKAGE)): digest(f) for f in inputs if f.is_file()},
              'submodules': pins,
              'compiler': run([sdk / 'llvm/bin/clang', '--version'], capture=True),
              'sdk': digest(sdk / 'oh-uni-package.json'), 'sdkApi': 13, 'rustToolchain': RUST}
    if not args.clean and valid_output(recipe):
        print('[expo-sqlite] Generated native inputs verified; reusing maintainer build.', flush=True)
        return

    run(['cargo', '--version'], env=dict(os.environ, RUSTUP_TOOLCHAIN=RUST))
    cache = PACKAGE / 'harmony/.native-build'
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='prepare-', dir=cache) as temp:
        work = Path(temp)
        generated = work / 'generated'
        sources = {name: snapshot(name, commit, work) for name, commit in pins.items()}

        amalgamations(sources, pins, generated)
        native_libraries(sources, sdk, work, generated)

        files = {str(f.relative_to(generated)): digest(f) for f in sorted(generated.rglob('*')) if f.is_file()}
        (generated / 'manifest.json').write_text(json.dumps({'sources': pins, 'recipe': recipe, 'files': files}, indent=2) + '\n')

        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        generated.rename(OUTPUT)

    print('[expo-sqlite] Generated amalgamations, dual-ABI dependencies and licenses.', flush=True)


if __name__ == '__main__':
    main()
