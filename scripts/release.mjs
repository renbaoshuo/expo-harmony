/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { createInterface } from 'node:readline/promises';
import { spawnSync } from 'node:child_process';
import JSON5 from 'json5';
import tar from 'tar';
import { bump, planRelease, updateManifests } from './release-plan.mjs';
import { publishOhpm as publishOhpmWithPassphrase, readOhpmPassphrase } from './release-ohpm.mjs';
import { assertPortableHarmonyHarSync } from '../packages/expo-module-scripts/src/har.mjs';
import { planWorkspaceBuild } from '../packages/expo-module-scripts/src/workspace.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('yarn release [--prepare-only] [--no-bump] [--registry npm|ohpm|all]\nyarn release:prepare [--no-bump] [--registry npm|ohpm|all]\nyarn release:publish <artifact-directory> [--registry npm|ohpm|all]\nInteractively prepare a release, or publish an existing release.json without rebuilding. Use --no-bump to prepare only the selected packages at their current versions without updating manifests. Defaults to both registries (OHPM, then npm). Completed publications are skipped. OHPM publishing requires expect and asks for the private-key passphrase once per run (hidden input, kept in memory only).');
  process.exit(0);
}
const { values: options } = parseArgs({
  args,
  options: {
    'prepare-only': { type: 'boolean' },
    'no-bump': { type: 'boolean' },
    'publish-only': { type: 'string' },
    registry: { type: 'string', default: 'all' },
  },
});
if (!['npm', 'ohpm', 'all'].includes(options.registry)) throw new Error('Use --registry npm, ohpm or all.');
if (options['prepare-only'] && options['publish-only'] !== undefined) throw new Error('Use either --prepare-only or --publish-only <artifact-directory>.');
const publishDirectory = options['publish-only'] !== undefined ? path.resolve(options['publish-only']) : undefined;
const publishNpm = options.registry !== 'ohpm';
const publishOhpm = options.registry !== 'npm';

function run(command, argv, options = {}) {
  const result = spawnSync(command, argv, { cwd: root, stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${argv.join(' ')} failed (${result.status}).`);
  return result.stdout;
}

async function runOhpm(argv, passphrase) {
  const { resolveHarmonyCommand } = await import('@expo-harmony/expo-modules-autolinking/tool-command');
  const command = resolveHarmonyCommand('ohpm', argv);
  if (passphrase === undefined) run(command.command, command.args);
  else publishOhpmWithPassphrase(command.command, command.args, passphrase, root);
}

function validateTag(tag) {
  if (typeof tag !== 'string' || !/^[a-z][a-z0-9-]{0,59}$/.test(tag) || tag === 'v') throw new Error('Use a tag such as latest or next (at most 60 characters).');
}

function harmonyChangelog(pkg, version) {
  const packagePath = path.relative(root, pkg.directory).split(path.sep).join('/');
  const historyUrl = `https://github.com/renbaoshuo/expo-harmony/commits/master/${packagePath}`;
  return `# Changelog\n\nVersion: ${version}\n\n[Commit History](${historyUrl})\n`;
}

async function saveRelease(file, artifacts) {
  await fs.writeFile(`${file}.tmp`, `${JSON.stringify(artifacts, null, 2)}\n`);
  await fs.rename(`${file}.tmp`, file);
}

function needsPublication(artifact) {
  return (publishNpm && !artifact.published.npm) || (publishOhpm && artifact.har && !artifact.published.ohpm);
}

async function publishArtifacts(artifacts, releaseFile, rl) {
  const pending = artifacts.filter(needsPublication);
  if (!pending.length) {
    console.log('所选仓库没有待发布产物。');
    return;
  }
  console.table(pending.map(({ name, version, tag, har, published }) => ({
    name, version, tag,
    ohpm: !publishOhpm ? '本次跳过' : har ? (published.ohpm ? '已提交' : '待提交') : '—',
    npm: !publishNpm ? '本次跳过' : published.npm ? '已发布' : '待发布',
  })));
  const destination = options.registry === 'all' ? 'OHPM → npm' : options.registry;
  if ((await rl.question(`按清单顺序将尚未完成的产物发布到 ${destination}？[y/N] `)).trim().toLowerCase() !== 'y') return;
  // Release the terminal before opening the hidden prompt or running publishers.
  rl.close();
  let passphrase;
  if (publishOhpm && pending.some(artifact => artifact.har && !artifact.published.ohpm)) {
    passphrase = await readOhpmPassphrase();
  }
  for (const artifact of pending) {
    if (!publishOhpm || !artifact.har || artifact.published.ohpm) continue;
    // OHPM reserves "latest" and rejects it as an explicit tag.
    const tagArgs = artifact.tag === 'latest' ? [] : ['--tag', artifact.tag];
    await runOhpm(['publish', artifact.har, ...tagArgs], passphrase);
    artifact.published.ohpm = true;
    await saveRelease(releaseFile, artifacts);
    console.log(`已提交到 OHPM：${artifact.name}@${artifact.version}（公仓上架状态请在 OHPM 确认）`);
  }
  passphrase = undefined;
  for (const artifact of pending) {
    if (!publishNpm || artifact.published.npm) continue;
    run('npm', ['publish', artifact.file, '--access', 'public', '--tag', artifact.tag]);
    artifact.published.npm = true;
    await saveRelease(releaseFile, artifacts);
    console.log(`已发布到 npm：${artifact.name}@${artifact.version}`);
  }
}

async function readNative(directory) {
  const entries = [];
  for (const relative of ['harmony/oh-package.json5', 'harmony/library/oh-package.json5']) {
    const file = path.join(directory, relative);
    try {
      entries.push({ file, data: JSON5.parse(await fs.readFile(file, 'utf8')) });
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return entries;
}

async function verifyTarball(file, pkg, project, temporary) {
  const directory = await fs.mkdtemp(path.join(temporary, 'verify-'));
  await tar.x({ file, cwd: directory, strict: true });
  const packedRoot = path.join(directory, 'package');
  const manifest = JSON.parse(await fs.readFile(path.join(packedRoot, 'package.json'), 'utf8'));
  if (manifest.name !== pkg.manifest.name || manifest.version !== pkg.manifest.version) throw new Error(`Wrong package identity in ${file}`);
  for (const section of ['dependencies', 'optionalDependencies', 'peerDependencies', 'devDependencies']) {
    for (const value of Object.values(manifest[section] || {})) {
      if (/^(?:workspace:|file:|link:|\/|\.{1,2}\/)/.test(value)) throw new Error(`Nonportable dependency ${value} in ${file}`);
    }
  }
  for (const entry of [manifest.main, manifest.types, ...Object.values(typeof manifest.bin === 'string' ? { bin: manifest.bin } : manifest.bin || {})]) {
    if (entry) await fs.access(path.join(packedRoot, entry));
  }
  if (project) {
    const har = path.join(packedRoot, path.relative(project.packageRoot, project.bundledHar));
    assertPortableHarmonyHarSync(har);
    const unpacked = await fs.mkdtemp(path.join(temporary, 'har-'));
    await tar.x({ file: har, cwd: unpacked, strict: true });
    const nativeFiles = [path.join(unpacked, 'package/oh-package.json5')];

    // RNOH runtime packages ship only the HAR; Expo modules also ship the source manifest.
    if (project.isExpoModule) {
      await fs.access(path.join(packedRoot, 'expo-module.config.json'));
      nativeFiles.push(path.join(packedRoot, path.relative(project.packageRoot, project.ohPackageManifest)));
    }

    for (const nativeFile of nativeFiles) {
      const native = JSON5.parse(await fs.readFile(nativeFile, 'utf8'));
      if (native.name !== manifest.name || native.version !== manifest.version) throw new Error(`Native version mismatch: ${nativeFile}`);
    }
    return { packedRoot, har };
  }
  return { packedRoot };
}

async function publishPrepared(directory) {
  const releaseFile = path.join(directory, 'release.json');
  const artifacts = JSON.parse(await fs.readFile(releaseFile, 'utf8'));
  if (!Array.isArray(artifacts) || !artifacts.length) throw new Error(`Empty or invalid release manifest: ${releaseFile}`);
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'expo-release-'));
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    for (const artifact of artifacts) {
      if (!artifact || typeof artifact.name !== 'string' || typeof artifact.version !== 'string' || typeof artifact.file !== 'string' || !artifact.file.endsWith('.tgz')) {
        throw new Error(`Invalid package entry in ${releaseFile}`);
      }
      validateTag(artifact.tag);
      if (artifact.har !== undefined && (typeof artifact.har !== 'string' || !artifact.har.endsWith('.har'))) throw new Error(`Invalid HAR path for ${artifact.name}`);
      // Resolve files in the selected directory, even after the directory has moved.
      artifact.file = path.join(directory, path.basename(artifact.file));
      if (artifact.har) artifact.har = path.join(directory, path.basename(artifact.har));
      artifact.published = { npm: artifact.published?.npm === true, ...(artifact.har ? { ohpm: artifact.published?.ohpm === true } : {}) };
      if (!needsPublication(artifact)) continue;
      const { packedRoot } = await verifyTarball(artifact.file, { manifest: artifact }, undefined, temporary);
      if (artifact.har) {
        const harmony = path.join(packedRoot, 'harmony');
        const bundled = (await fs.readdir(harmony)).filter(name => name.endsWith('.har'));
        if (bundled.length !== 1) throw new Error(`Expected one bundled HAR in ${artifact.file}`);
        const bundledHar = path.join(harmony, bundled[0]);
        assertPortableHarmonyHarSync(bundledHar);
        const unpacked = await fs.mkdtemp(path.join(temporary, 'har-'));
        await tar.x({ file: bundledHar, cwd: unpacked, strict: true });
        const native = JSON5.parse(await fs.readFile(path.join(unpacked, 'package/oh-package.json5'), 'utf8'));
        if (native.name !== artifact.name || native.version !== artifact.version) throw new Error(`Native version mismatch: ${artifact.file}`);
        if (publishOhpm && !artifact.published.ohpm) {
          if (!(await fs.readFile(artifact.har)).equals(await fs.readFile(bundledHar))) throw new Error(`HAR does not match the npm archive: ${artifact.har}`);
          await runOhpm(['prepublish', artifact.har]);
        }
      }
    }
    await publishArtifacts(artifacts, releaseFile, rl);
  } finally {
    rl.close();
    await fs.rm(temporary, { recursive: true, force: true });
  }
}

async function main() {
  if (!process.stdin.isTTY) throw new Error('Run release in an interactive terminal.');
  if (publishDirectory) return publishPrepared(publishDirectory);
  if (run('git', ['status', '--porcelain'], { encoding: 'utf8', stdio: 'pipe' }).trim()) {
    throw new Error('Commit or stash working tree changes before preparing a release.');
  }
  const listing = run('yarn', ['workspaces', 'list', '--json'], { encoding: 'utf8', stdio: 'pipe' });
  const packages = [];
  for (const line of listing.trim().split('\n')) {
    const workspace = JSON.parse(line);
    if (workspace.location === '.') continue;
    const directory = path.join(root, workspace.location);
    const manifest = JSON.parse(await fs.readFile(path.join(directory, 'package.json'), 'utf8'));
    packages.push({ directory, manifest, native: await readNative(directory) });
  }
  const choices = packages.filter(pkg => !pkg.manifest.private && pkg.manifest.name.startsWith('@expo-harmony/'));
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  let temporary;
  try {
    choices.forEach((pkg, index) => console.log(`${index + 1}. ${pkg.manifest.name}  ${pkg.manifest.version}`));
    const answer = (await rl.question('选择包编号，逗号分隔（all = 全部）: ')).trim();
    const indices = answer === 'all' ? choices.map((_, index) => index) : answer.split(',').map(value => Number(value.trim()) - 1);
    if (!indices.length || indices.some(index => !Number.isInteger(index) || !choices[index])) throw new Error('Invalid package selection.');
    const selected = new Map();
    for (const index of new Set(indices)) {
      const pkg = choices[index];
      if (options['no-bump']) {
        selected.set(pkg.manifest.name, pkg.manifest.version);
        continue;
      }
      let suggested = '';
      try { suggested = bump(pkg.manifest.version); } catch { /* Ask for a custom version. */ }
      const version = (await rl.question(`${pkg.manifest.name} 新版本 [${suggested || '必填'}]: `)).trim() || suggested;
      selected.set(pkg.manifest.name, version);
    }
    const versions = options['no-bump'] ? selected : planRelease(packages, selected);
    for (const [name, version] of versions) {
      console.log(options['no-bump']
        ? `${name}: ${version}（保持版本）`
        : `${name}: ${packages.find(pkg => pkg.manifest.name === name).manifest.version} → ${version}${selected.has(name) ? '' : '（依赖联动）'}`);
    }
    const tag = (await rl.question('发布 tag [latest，OHPM 不传 --tag]: ')).trim() || 'latest';
    validateTag(tag);
    if ((await rl.question(options['no-bump'] ? '使用当前版本构建打包？[y/N] ' : '更新版本并构建打包？[y/N] ')).trim().toLowerCase() !== 'y') return;
    for (const pkg of options['no-bump'] ? [] : packages) {
      const version = versions.get(pkg.manifest.name);
      const updated = updateManifests(pkg, versions);
      if (JSON.stringify(updated.manifest) !== JSON.stringify(pkg.manifest)) {
        await fs.writeFile(path.join(pkg.directory, 'package.json'), `${JSON.stringify(updated.manifest, null, 2)}\n`);
      }
      for (let index = 0; index < updated.native.length; index++) {
        const entry = updated.native[index];
        if (JSON.stringify(entry.data) !== JSON.stringify(pkg.native[index].data)) {
          await fs.writeFile(entry.file, `${JSON.stringify(entry.data, null, 2)}\n`);
        }
      }
      if (version && updated.native.some(entry => entry.file === path.join(pkg.directory, 'harmony/library/oh-package.json5'))) {
        await fs.writeFile(path.join(pkg.directory, 'harmony/library/CHANGELOG.md'), harmonyChangelog(pkg, version));
      }
      pkg.manifest = updated.manifest;
    }
    run('yarn', ['install']);
    // Compile the JS tooling before importing it or building native modules.
    run('yarn', ['workspaces', 'foreach', '--all', '--include', '@expo-harmony/*', '--topological-dev', '--verbose', 'run', 'build']);
    const { buildWorkspace, loadModuleProject, writeBuildReceipt } = await import('../packages/expo-module-scripts/src/index.mjs');
    await buildWorkspace(root, { clean: true });
    temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'expo-release-'));
    const projects = [];
    for (const pkg of packages) {
      if (pkg.native.some(entry => entry.file.endsWith('/library/oh-package.json5'))) projects.push(await loadModuleProject(pkg.directory));
    }
    const receipt = path.join(temporary, 'receipt.json');
    await writeBuildReceipt(receipt, projects);
    const output = path.join(root, 'release-artifacts', new Date().toISOString().replace(/[:.]/g, '-'));
    await fs.mkdir(output, { recursive: true });
    const artifacts = [];
    // Nothing is published until every archive has passed validation.
    for (const [name, version] of versions) {
      const pkg = packages.find(item => item.manifest.name === name);
      const file = path.join(output, `${name.replace('@', '').replaceAll('/', '-')}-${version}.tgz`);
      run('yarn', ['workspace', name, 'pack', '--out', file], { env: { ...process.env, EXPO_HARMONY_BUILD_RECEIPT: receipt } });
      const { har: packedHar } = await verifyTarball(file, pkg, projects.find(project => project.packageRoot === pkg.directory), temporary);
      const artifact = { name, version, file, tag, published: { npm: false } };
      if (packedHar) {
        // Publish exactly the same HAR that npm consumers receive, including native-only packages.
        artifact.har = file.replace(/\.tgz$/, '.har');
        artifact.published.ohpm = false;
        await fs.copyFile(packedHar, artifact.har);
        if (publishOhpm) await runOhpm(['prepublish', artifact.har]);
      }
      artifacts.push(artifact);
    }
    const nativeOrder = new Map(planWorkspaceBuild(projects, projects).map(({ project }, index) => [project.packageJson.name, index]));
    artifacts.sort((a, b) => (nativeOrder.get(a.name) ?? nativeOrder.size) - (nativeOrder.get(b.name) ?? nativeOrder.size));
    const releaseFile = path.join(output, 'release.json');
    await saveRelease(releaseFile, artifacts);
    console.log(`产物已校验：${output}`);
    if (options['prepare-only']) return;
    await publishArtifacts(artifacts, releaseFile, rl);
  } finally {
    rl.close();
    if (temporary) await fs.rm(temporary, { recursive: true, force: true });
  }
}

main().catch(error => {
  console.error(error.message);
  console.error(`修改和产物会保留。可运行 yarn release:publish <产物目录> --registry ${options.registry} 继续发布，已记录成功的步骤会跳过；若上传时中断，请先确认仓库状态。`);
  process.exitCode = 1;
});
