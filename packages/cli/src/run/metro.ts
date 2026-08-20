import http from 'node:http';

import { HarmonyCliError } from '../errors';
import { formatDiagnostics, startManagedProcess, type ProcessResult } from '../process';
import { resolveExpoCli } from '../expo';

type MetroStatus = 'free' | 'metro' | 'occupied';

interface MetroOptions {
  port: number;
  readyTimeoutMs?: number;
}

export interface MetroSession {
  owner: 'existing' | 'started';
  port: number;
  process?: ReturnType<typeof startManagedProcess>;
  stop(): Promise<unknown>;
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

async function requireExistingMetroAsync(port: number): Promise<MetroSession> {
  const status = await probeMetroAsync(port);

  if (status === 'metro') return { owner: 'existing', port, stop: async () => {} };

  const code = status === 'free' ? 'ERR_HARMONY_METRO_UNAVAILABLE' : 'ERR_HARMONY_METRO_PORT_IN_USE';
  const message = status === 'free'
    ? `No Metro server is running on port ${port}; start Expo Metro before using --no-bundler.`
    : `Port ${port} is occupied by a process that is not a compatible Metro server.`;

  throw new HarmonyCliError(code, message, { operation: 'metro-probe' });
}

async function startExpoMetroAsync(
  projectRoot: string,
  options: MetroOptions
): Promise<MetroSession> {
  const before = await probeMetroAsync(options.port);

  if (before === 'metro') return { owner: 'existing', port: options.port, stop: async () => {} };

  if (before === 'occupied') {
    throw new HarmonyCliError(
      'ERR_HARMONY_METRO_PORT_IN_USE',
      `Port ${options.port} is occupied by a process that is not a compatible Metro server.`,
      { operation: 'metro-probe' }
    );
  }

  const expo = resolveExpoCli(projectRoot);
  const managed = startManagedProcess(process.execPath, [
    expo.cliPath,
    'start',
    projectRoot,
    '--dev-client',
    '--port', String(options.port),
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      EXPO_METRO_TARGET: 'harmony',
    },
    operation: 'expo-metro',
    outputLimit: 1024 * 1024,
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
  const timeoutMs = options.readyTimeoutMs || 60_000;

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
          owner: 'started',
          port: options.port,
          process: managed,
          stop: () => managed.stop(),
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

export { requireExistingMetroAsync, startExpoMetroAsync };
