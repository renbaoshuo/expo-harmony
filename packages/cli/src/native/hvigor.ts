import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fingerprintHarmonyNativeInputsSync } from '@expo-harmony/config-plugins/internal/native-inputs';

import { HarmonyCliError } from '../errors';
import { createHarmonyToolchainEnv, resolveHarmonyToolchain } from './toolchain';

function nodeExecutable(): string {
  const candidates = process.env.EXPO_HARMONY_NODE
    ? [process.env.EXPO_HARMONY_NODE]
    : [
        process.execPath,
        ...(process.env.PATH || '').split(path.delimiter).filter(Boolean)
          .map(directory => path.join(directory, process.platform === 'win32' ? 'node.exe' : 'node')),
      ];

  for (const candidate of new Set(candidates)) {
    const result = spawnSync(candidate, ['-p', 'process.versions.node'], { encoding: 'utf8', timeout: 5_000 });
    if (result.status === 0 && Number.parseInt(result.stdout, 10) >= 20) return candidate;
  }

  throw new HarmonyCliError('ERR_HARMONY_NODE', 'Harmony native builds require Node.js 20 or newer. Set EXPO_HARMONY_NODE to its executable.', { operation: 'native-build' });
}

function run(command: string, args: string[], cwd: string): void {
  const result = spawnSync(command, args, {
    cwd,
    env: { ...createHarmonyToolchainEnv(), EXPO_HARMONY: '1', EXPO_METRO_TARGET: 'harmony', HERMES_V1_ENABLED: 'true' },
    stdio: 'inherit',
    timeout: 10 * 60_000,
  });

  if (result.error || result.status !== 0) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_BUILD', `Harmony build command failed: ${command} (${result.error?.message || result.status}).`, { cause: result.error, exitCode: result.status || 1, operation: 'native-build' });
  }
}

// Hvigor configuration is synchronous; linking must finish before task execution.
export function prepareHarmonyNativeBuild(root: string, mode: 'debug' | 'release'): void {
  const harmony = path.join(root, 'harmony');

  if (process.env.EXPO_HARMONY_NATIVE_PREPARED !== '1') {
    const require = createRequire(path.join(root, 'package.json'));
    const manifest = path.resolve(path.dirname(require.resolve('@expo-harmony/expo-modules-autolinking')), '../package.json');
    const bin = path.resolve(path.dirname(manifest), require(manifest).bin['expo-harmony-autolinking']);

    run(nodeExecutable(), [bin, 'link', '--project-root', root, '--harmony-project-path', harmony, '--build-type', mode], root);

    const { ohpm } = resolveHarmonyToolchain();
    run(ohpm.command, [...ohpm.args, 'install', '--all'], harmony);
  }

  const { fingerprint } = fingerprintHarmonyNativeInputsSync({
    projectRoot: root,
    manifest: path.join(harmony, 'oh-package.json5'),
    lockfile: path.join(harmony, 'oh-package-lock.json5'),
  });
  const file = path.join(harmony, '.hvigor/expo-harmony/native-inputs.cmake');
  const content = `# Generated native dependency fingerprint.\nadd_compile_definitions(EXPO_HARMONY_NATIVE_INPUTS_SHA256_${fingerprint}=1)\n`;
  if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === content) return;

  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${crypto.randomUUID()}.tmp`;

  try {
    fs.writeFileSync(temp, content);
    fs.renameSync(temp, file);
  } finally {
    fs.rmSync(temp, { force: true });
  }
}

export function bundleHarmonyNativeBuild(root: string): void {
  if (process.env.EXPO_HARMONY_BUNDLE_PREBUILT === '1') return;

  const require = createRequire(path.join(root, 'package.json'));
  run(nodeExecutable(), [require.resolve('@expo-harmony/cli/bin/expo-harmony'), 'export:embed', root], root);
}
