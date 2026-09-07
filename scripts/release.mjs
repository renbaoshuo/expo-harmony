import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline/promises';
import { spawnSync } from 'node:child_process';
import JSON5 from 'json5';
import tar from 'tar';
import { bump, planRelease, updateManifests } from './release-plan.mjs';
import { assertPortableHarmonyHarSync } from '../packages/expo-module-scripts/src/har.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('yarn release [--prepare-only]\nInteractively bump packages, build once, pack and optionally publish.');
  process.exit(0);
}
if (args.some(arg => arg !== '--prepare-only')) throw new Error('Unknown option. Use --help.');

function run(command, argv, options = {}) {
  const result = spawnSync(command, argv, { cwd: root, stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${argv.join(' ')} failed (${result.status}).`);
  return result.stdout;
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
    if (project.config.modules.length > 0) {
      nativeFiles.push(path.join(packedRoot, path.relative(project.packageRoot, project.ohPackageManifest)));
    }
    for (const nativeFile of nativeFiles) {
      const native = JSON5.parse(await fs.readFile(nativeFile, 'utf8'));
      if (native.name !== manifest.name || native.version !== manifest.version) throw new Error(`Native version mismatch: ${nativeFile}`);
    }
  }
}

async function main() {
  if (!process.stdin.isTTY) throw new Error('Run release in an interactive terminal.');
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
      let suggested = '';
      try { suggested = bump(pkg.manifest.version); } catch { /* Ask for a custom version. */ }
      const version = (await rl.question(`${pkg.manifest.name} 新版本 [${suggested || '必填'}]: `)).trim() || suggested;
      selected.set(pkg.manifest.name, version);
    }
    const versions = planRelease(packages, selected);
    for (const [name, version] of versions) {
      console.log(`${name}: ${packages.find(pkg => pkg.manifest.name === name).manifest.version} → ${version}${selected.has(name) ? '' : '（依赖联动）'}`);
    }
    const tag = (await rl.question('npm dist-tag [latest]: ')).trim() || 'latest';
    if (!/^[a-z][a-z0-9-]*$/.test(tag) || tag === 'v') throw new Error('Use a dist-tag such as latest or next.');
    if ((await rl.question('更新版本并构建打包？[y/N] ')).trim().toLowerCase() !== 'y') return;
    for (const pkg of packages) {
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
      await verifyTarball(file, pkg, projects.find(project => project.packageRoot === pkg.directory), temporary);
      artifacts.push({ name, version, file, tag });
    }
    await fs.writeFile(path.join(output, 'release.json'), `${JSON.stringify(artifacts, null, 2)}\n`);
    console.log(`产物已校验：${output}`);
    if (args.includes('--prepare-only')) return;
    console.table(artifacts.map(({ name, version, tag }) => ({ name, version, tag })));
    if ((await rl.question('将这些 tgz 发布到 npm？[y/N] ')).trim().toLowerCase() !== 'y') return;
    for (const artifact of artifacts) {
      run('npm', ['publish', artifact.file, '--access', 'public', '--tag', tag]);
      console.log(`已发布 ${artifact.name}@${artifact.version}`);
    }
  } finally {
    rl.close();
    if (temporary) await fs.rm(temporary, { recursive: true, force: true });
  }
}

main().catch(error => {
  console.error(error.message);
  console.error('若版本已更新，修改会保留以便检查；不会自动提交、回滚或重新发布。已生成的 tgz 可用于重试。');
  process.exitCode = 1;
});
