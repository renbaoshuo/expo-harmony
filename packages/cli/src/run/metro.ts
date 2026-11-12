/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import http from 'node:http';

import { resolveDevelopmentHostAsync } from '../development/host';
import { readDevelopmentSessionAsync } from '../development/session';
import { HarmonyCliError } from '../errors';
import { formatDiagnostics, startManagedProcess, type ProcessResult } from '../process';
import { resolveExpoCli } from '../expo';
import { resolveTimeoutMs } from '../timeout';

type MetroStatus = 'free' | 'metro' | 'occupied';

interface MetroOptions {
  interactive?: boolean;
  host?: string;
  port: number;
  privateKeyPath?: string;
  readyTimeoutMs?: number;
  resetCache?: boolean;
}

export interface MetroSession {
  owner: 'existing' | 'started';
  development?: Awaited<ReturnType<typeof readDevelopmentSessionAsync>>;
  port: number;
  process?: ReturnType<typeof startManagedProcess>;
  stop(): Promise<unknown>;
  waitAsync(): Promise<void>;
}

function delay(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

function probeMetroAsync(
  port: number,
  options: { host?: string; timeoutMs?: number } = {}
): Promise<MetroStatus> {
  const timeoutMs = options.timeoutMs || 750;

  return new Promise<MetroStatus>((resolve) => {
    let settled = false;

    const finish = (value) => {
      if (settled) return;

      settled = true;
      resolve(value);
    };

    const request = http.get({
      headers: { Accept: 'text/plain' },
      host: options.host || '127.0.0.1',
      path: '/status',
      port,
    }, (response) => {
      let body = '';

      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        if (body.length < 1_024) body += chunk;
      });
      response.on('end', () => finish(
        response.statusCode === 200 && body.trim() === 'packager-status:running'
          ? 'metro'
          : 'occupied'
      ));
    });

    request.setTimeout(timeoutMs, () => {
      request.destroy();
      finish('occupied');
    });

    request.on('error', (error: NodeJS.ErrnoException) => finish(
      error.code === 'ECONNREFUSED' || error.code === 'EHOSTUNREACH'
        ? 'free'
        : 'occupied'
    ));
  });
}

async function requireExistingMetroAsync(projectRoot: string, port: number, host?: string): Promise<MetroSession> {
  const status = await probeMetroAsync(port);

  if (status === 'metro') {
    return {
      development: await readDevelopmentSessionAsync(projectRoot, port, host),
      owner: 'existing',
      port,
      stop: async () => {},
      waitAsync: async () => {},
    };
  }

  const code = status === 'free' ? 'ERR_HARMONY_METRO_UNAVAILABLE' : 'ERR_HARMONY_METRO_PORT_IN_USE';
  const message = status === 'free'
    ? `No Metro server is running on port ${port}; use expo-harmony start before using --no-bundler.`
    : `Port ${port} is occupied by a process that is not a compatible Metro server.`;

  throw new HarmonyCliError(code, message, { operation: 'metro-probe' });
}

async function startExpoMetroAsync(
  projectRoot: string,
  options: MetroOptions
): Promise<MetroSession> {
  const host = await resolveDevelopmentHostAsync(projectRoot, options.host);
  const before = await probeMetroAsync(options.port);

  if (before === 'metro') {
    return {
      development: await readDevelopmentSessionAsync(projectRoot, options.port, host),
      owner: 'existing',
      port: options.port,
      stop: async () => {},
      waitAsync: async () => {},
    };
  }

  if (before === 'occupied') {
    throw new HarmonyCliError(
      'ERR_HARMONY_METRO_PORT_IN_USE',
      `Port ${options.port} is occupied by a process that is not a compatible Metro server.`,
      { operation: 'metro-probe' }
    );
  }

  const expo = resolveExpoCli(projectRoot);
  const managed = startManagedProcess(process.execPath, [
    require.resolve('../internal/development'),
    expo.cliPath,
    'start',
    projectRoot,
    '--dev-client',
    '--port', String(options.port),
    ...(options.privateKeyPath ? ['--private-key-path', options.privateKeyPath] : []),
    ...(options.resetCache ? ['--clear'] : []),
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      EXPO_HARMONY: '1',
      EXPO_METRO_TARGET: 'harmony',
      REACT_NATIVE_PACKAGER_HOSTNAME: host,
    },
    operation: 'expo-metro',
    outputLimit: 1024 * 1024,
    stdio: options.interactive ? 'inherit' : 'pipe',
  });
  let exitResult: ProcessResult | null = null;
  let exitError: unknown = null;

  managed.completion.then(
    (result) => {
      exitResult = result;
    },
    (error) => {
      exitError = error;
    }
  );

  const startedAt = Date.now();
  const timeoutMs = resolveTimeoutMs('metro-ready', 30 * 60_000, options.readyTimeoutMs);

  try {
    while (Date.now() - startedAt < timeoutMs) {
      if (exitError instanceof HarmonyCliError) {
        throw new HarmonyCliError(exitError.code, exitError.message, {
          cause: exitError,
          exitCode: exitError.exitCode,
          operation: exitError.operation,
        });
      }

      if (exitError) {
        const failure = exitError as {
          code?: string;
          exitCode?: number;
          message?: string;
          operation?: string;
        };
        throw new HarmonyCliError(
          failure.code || 'ERR_HARMONY_METRO_EXITED',
          failure.message || 'Expo Metro failed before becoming ready.',
          { cause: exitError, exitCode: failure.exitCode, operation: failure.operation }
        );
      }

      if (exitResult) {
        const diagnostics = formatDiagnostics(exitResult);
        throw new HarmonyCliError(
          'ERR_HARMONY_METRO_EXITED',
          `Expo Metro exited before becoming ready with code ${exitResult.code}.${diagnostics ? `\n${diagnostics}` : ''}`,
          { exitCode: exitResult.code || 1, operation: 'expo-metro' }
        );
      }

      if (await probeMetroAsync(options.port) === 'metro') {
        return {
          development: await readDevelopmentSessionAsync(projectRoot, options.port, host),
          owner: 'started',
          port: options.port,
          process: managed,
          stop: () => managed.stop(),
          async waitAsync() {
            const result = await managed.completion;
            if (managed.wasStopped()) return;

            const interrupted = result.signal === 'SIGINT' || result.signal === 'SIGTERM';
            if (result.code === 0 || interrupted) return;

            const diagnostics = formatDiagnostics(result);
            throw new HarmonyCliError(
              'ERR_HARMONY_METRO_EXITED',
              `Expo Metro exited with code ${result.code}.${diagnostics ? `\n${diagnostics}` : ''}`,
              { exitCode: result.code || 1, operation: 'expo-metro' }
            );
          },
        };
      }

      await delay(150);
    }

    throw new HarmonyCliError(
      'ERR_HARMONY_METRO_TIMEOUT',
      `Expo Metro did not become ready on port ${options.port} within ${timeoutMs}ms.`,
      { operation: 'expo-metro' }
    );
  } catch (error) {
    await managed.stop();

    if (error instanceof HarmonyCliError) {
      throw new HarmonyCliError(error.code, error.message, {
        cause: error,
        exitCode: error.exitCode,
        operation: error.operation,
      });
    }

    throw new HarmonyCliError(
      error.code || 'ERR_HARMONY_METRO_EXITED',
      error.message || 'Expo Metro failed while waiting for the server to become ready.',
      { cause: error, exitCode: error.exitCode, operation: error.operation }
    );
  }
}

export {
  requireExistingMetroAsync,
  startExpoMetroAsync,
};
