import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { createRNOHProjectPlugin } from '@rnoh/hvigor-plugin';

import { writeStamp } from './native-inputs-stamp';

process.env.HERMES_V1_ENABLED = 'true';

const ProjectRoot = path.resolve('..');
const HarmonyRoot = path.join(ProjectRoot, 'harmony');
const NodeModules = findNodeModules();
const CliPath = path.join(NodeModules, '@expo-harmony/cli/bin/expo-harmony.js');
const ModuleName = 'entry';
const EmbeddedBundle = path.join(HarmonyRoot, ModuleName, 'src/main/resources/rawfile/hermes_bundle.hbc');
const HermesMagic = 'c61fbc03c103191f';

let restoreBundle: (() => void) | null = null;

writeStamp(ProjectRoot, HarmonyRoot);

function findNodeModules(): string {
  let directory = ProjectRoot;

  while (true) {
    const candidate = path.join(directory, 'node_modules');
    if (fs.existsSync(candidate)) return candidate;

    const parent = path.dirname(directory);
    if (parent === directory) throw new Error('Unable to find node_modules for the Harmony project.');
    directory = parent;
  }
}

function stashBundle() {
  if (!fs.existsSync(EmbeddedBundle) || restoreBundle) return;

  const backupRoot = path.join(ProjectRoot, '.expo', 'harmony');
  fs.mkdirSync(backupRoot, { recursive: true });

  const backupDir = fs.mkdtempSync(path.join(backupRoot, 'debug-build-'));
  const backup = path.join(backupDir, path.basename(EmbeddedBundle));
  fs.renameSync(EmbeddedBundle, backup);

  restoreBundle = () => {
    if (!fs.existsSync(backup)) {
      fs.rmSync(backupDir, { recursive: true, force: true });
      restoreBundle = null;
      throw new Error('Cannot restore the release Harmony bundle because its debug-build backup is missing.');
    }

    if (fs.existsSync(EmbeddedBundle)) {
      throw new Error('Cannot restore the release Harmony bundle because its destination changed during the debug build.');
    }

    fs.renameSync(backup, EmbeddedBundle);
    fs.rmSync(backupDir, { recursive: true, force: true });
    restoreBundle = null;
  };

  const restoreOnExit = () => {
    try {
      restoreBundle?.();
    } catch (error) {
      process.stderr.write(`[expo-harmony] Failed to restore the release bundle: ${String(error)}\n`);
    }
  };

  process.once('exit', restoreOnExit);
  hvigor.buildFinished(() => {
    try {
      restoreBundle?.();
    } finally {
      if (!restoreBundle) process.removeListener('exit', restoreOnExit);
    }
  });
}

function readNodeVersion(executable: string): string | null {
  const result = spawnSync(executable, ['-p', 'process.versions.node'], { encoding: 'utf8' });
  if (result.error || result.status !== 0) return null;
  return String(result.stdout).trim();
}

function supportsMetro(executable: string): boolean {
  const version = readNodeVersion(executable);
  return version !== null && Number.parseInt(version, 10) >= 20;
}

function resolveMetroNode(): string {
  const configured = process.env.EXPO_HARMONY_NODE;
  if (configured) {
    if (supportsMetro(configured)) return configured;

    throw new Error(
      `EXPO_HARMONY_NODE must point to Node.js 20 or newer; received ${readNodeVersion(configured) || 'an unusable executable'}.`
    );
  }

  const executable = process.platform === 'win32' ? 'node.exe' : 'node';
  const candidates = (process.env.PATH || '')
    .split(path.delimiter)
    .filter(Boolean)
    .map(directory => path.join(directory, executable));
  const seen = new Set();

  for (const candidate of [...candidates, process.execPath]) {
    if (seen.has(candidate)) continue;

    seen.add(candidate);
    if (supportsMetro(candidate)) return candidate;
  }

  throw new Error(
    'Release bundling requires Node.js 20 or newer. Set EXPO_HARMONY_NODE to its executable.'
  );
}

function isHermesBytecode(file: string): boolean {
  if (!fs.existsSync(file) || fs.statSync(file).size <= 12) return false;

  const descriptor = fs.openSync(file, 'r');

  try {
    const header = Buffer.alloc(8);
    const bytesRead = fs.readSync(descriptor, header, 0, header.length, 0);

    return bytesRead === header.length && header.toString('hex') === HermesMagic;
  } finally {
    fs.closeSync(descriptor);
  }
}

function assertBundle() {
  if (!isHermesBytecode(EmbeddedBundle)) {
    throw new Error('The prebuilt Harmony bundle is missing or is not Hermes bytecode.');
  }
}

function bundleRelease() {
  if (process.env.EXPO_HARMONY_BUNDLE_PREBUILT === '1') {
    assertBundle();
    return;
  }

  const executable = resolveMetroNode();

  if (!fs.existsSync(CliPath)) {
    throw new Error('Release bundling requires the project-local @expo-harmony/cli package.');
  }

  const result = spawnSync(executable, [CliPath, 'export:embed', ProjectRoot, '--json'], {
    cwd: ProjectRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      EXPO_METRO_TARGET: 'harmony',
      HERMES_V1_ENABLED: 'true',
    },
    maxBuffer: 64 * 1024 * 1024,
  });

  if (result.error) {
    throw new Error(result.error.message, { cause: result.error });
  }

  if (result.status !== 0) {
    const diagnostics = (result.stderr || result.stdout || '').slice(-4000);

    throw new Error(
      `Harmony bundle failed with exit code ${result.status ?? 'unknown'}.\n${diagnostics}`
    );
  }

  assertBundle();
}

const BundlerPlugin = {
  pluginId: 'expo-harmony-bundler',
  apply(node) {
    hvigor.nodesEvaluated(() => {
      const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN);
      const buildMode = appContext.getBuildMode();

      if (buildMode !== 'release') stashBundle();

      node.subNodes((moduleNode) => {
        const hapContext = moduleNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN);

        hapContext?.targets((target) => {
          const targetName = target.getTargetName();

          moduleNode.registerTask({
            name: `${targetName}@ExpoHarmonyBundle`,
            run: () => {
              if (buildMode === 'release') bundleRelease();
            },
            dependencies: [`${targetName}@ProcessResource`],
            postDependencies: [`${targetName}@CompileResource`],
          });
        });
      });
    });
  },
};

export default {
  system: appTasks,
  plugins: [
    createRNOHProjectPlugin({
      nodeModulesPath: NodeModules,
      bundler: { enabled: false },
    }),
    BundlerPlugin,
  ],
};
