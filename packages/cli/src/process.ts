import spawn from 'cross-spawn';
import { terminateProcess } from '@expo-harmony/expo-modules-autolinking/tool-command';

import { HarmonyCliError } from './errors';

const DefaultOutputLimit = 1024 * 1024;
const DefaultStopGraceMs = 3_000;

export interface ProcessOptions {
  capture?: boolean;
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  onStderr?: (chunk: Uint8Array) => void;
  onStdout?: (chunk: Uint8Array) => void;
  operation?: string;
  outputLimit?: number;
  signal?: AbortSignal;
  stdio?: 'inherit' | 'pipe';
  stopGraceMs?: number;
  timeoutMs?: number;
}

export interface ProcessResult {
  code: number;
  signal: NodeJS.Signals | null;
  stderr: string;
  stdout: string;
  timedOut: boolean;
}

interface CheckedProcessOptions {
  code: string;
  cwd: string;
  env?: NodeJS.ProcessEnv;
  message: string;
  operation: string;
  outputLimit?: number;
  timeoutMs?: number;
}

class BoundedCapture {
  private buffers: Uint8Array[] = [];
  private head = 0;
  private length = 0;

  constructor(private readonly limit: number) {
  }

  append(value: Uint8Array | string): void {
    const buffer = typeof value === 'string' ? new TextEncoder().encode(value) : Uint8Array.from(value);
    if (buffer.length >= this.limit) {
      this.buffers = [buffer.subarray(buffer.length - this.limit)];
      this.head = 0;
      this.length = this.limit;
      return;
    }

    while (this.length + buffer.length > this.limit && this.head < this.buffers.length) {
      const first = this.buffers[this.head];
      const excess = this.length + buffer.length - this.limit;
      if (first.length > excess) {
        this.buffers[this.head] = first.subarray(excess);
        this.length -= excess;
        break;
      }
      this.length -= first.length;
      this.head += 1;
    }

    this.buffers.push(buffer);
    this.length += buffer.length;

    if (this.head > 128 && this.head * 2 > this.buffers.length) {
      this.buffers = this.buffers.slice(this.head);
      this.head = 0;
    }
  }

  toString(): string {
    return Buffer.concat(this.buffers.slice(this.head), this.length).toString('utf8');
  }
}

function formatDiagnostics(result: Pick<ProcessResult, 'stderr' | 'stdout'>, limit = 4_000): string {
  return (result.stderr || result.stdout || '').slice(-limit).trim();
}

function spawnAsync(command: string, args: string[], options: ProcessOptions = {}): Promise<ProcessResult> {
  return new Promise<ProcessResult>((resolve, reject) => {
    if (options.signal?.aborted) {
      throw new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot run ${command}: operation aborted.`, {
        cause: options.signal.reason,
        operation: options.operation || 'spawn',
      });
    }

    const piped = Boolean(options.capture || options.onStdout || options.onStderr);
    const limit = options.outputLimit || DefaultOutputLimit;
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      shell: false,
      stdio: piped ? ['ignore', 'pipe', 'pipe'] : 'inherit',
      windowsHide: true,
    });

    const stdout = new BoundedCapture(limit);
    const stderr = new BoundedCapture(limit);
    let timedOut = false;
    let settled = false;
    let escalation: NodeJS.Timeout | null = null;
    let stopping: Promise<void> | undefined;

    if (piped) {
      child.stdout.on('data', (chunk) => {
        stdout.append(chunk);
        options.onStdout?.(chunk);
      });
      child.stderr.on('data', (chunk) => {
        stderr.append(chunk);
        options.onStderr?.(chunk);
      });
    }

    const stop = (signal: NodeJS.Signals = 'SIGTERM') => {
      if (stopping || settled) return;

      stopping = Promise.resolve().then(() => terminateProcess(child, signal));
      if (process.platform === 'win32') {
        void finish(null, signal);
      } else {
        stopping.catch((cause) => {
          void finish(null, null, cause);
        });
        escalation = setTimeout(
          () => {
            stopping = terminateProcess(child, 'SIGKILL');
            stopping.catch((cause) => {
              void finish(null, null, cause);
            });
          },
          options.stopGraceMs || DefaultStopGraceMs
        );
        escalation.unref?.();
      }
    };

    const interrupt = () => stop('SIGINT');
    const terminate = () => stop('SIGTERM');
    process.once('SIGINT', interrupt);
    process.once('SIGTERM', terminate);

    const timeout = options.timeoutMs
      ? setTimeout(() => {
          timedOut = true;
          stop('SIGTERM');
        }, options.timeoutMs)
      : null;
    timeout?.unref?.();

    const cleanup = () => {
      if (timeout) clearTimeout(timeout);
      if (escalation) clearTimeout(escalation);
      process.removeListener('SIGINT', interrupt);
      process.removeListener('SIGTERM', terminate);
      options.signal?.removeEventListener('abort', abort);
    };

    const finish = async (code, signal, cause?) => {
      try {
        await stopping;
      } catch (error) {
        cause = error;
      }

      if (settled) return;
      settled = true;
      cleanup();

      if (cause) reject(new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot run ${command}: ${cause.message}`, {
        cause,
        operation: options.operation || 'spawn',
      }));
      else resolve({
        code: code === null ? 1 : code,
        signal,
        stderr: stderr.toString(),
        stdout: stdout.toString(),
        timedOut,
      });
    };

    child.once('error', (cause) => {
      void finish(null, null, cause);
    });
    child.once('close', (code, signal) => {
      void finish(code, signal);
    });

    const abort = () => stop('SIGTERM');
    options.signal?.addEventListener('abort', abort, { once: true });
    if (options.signal?.aborted) abort();
  });
}

function startManagedProcess(command: string, args: string[], options: ProcessOptions = {}) {
  if (options.signal?.aborted) {
    throw new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot launch ${command}: operation aborted.`, {
      cause: options.signal.reason,
      operation: options.operation || 'spawn',
    });
  }

  const limit = options.outputLimit || DefaultOutputLimit;
  const piped = options.stdio !== 'inherit';
  const child = spawn(command, args, {
    cwd: options.cwd,
    env: options.env || process.env,
    shell: false,
    stdio: piped ? ['ignore', 'pipe', 'pipe'] : 'inherit',
    windowsHide: true,
  });

  const stdout = new BoundedCapture(limit);
  const stderr = new BoundedCapture(limit);
  let failure: HarmonyCliError | null = null;
  let closed = false;
  let stopped = false;
  let stopping: Promise<void> | undefined;
  let stopPromise: Promise<ProcessResult | undefined> | undefined;
  let finish: (code: number | null, signal: NodeJS.Signals | null) => Promise<void>;

  if (piped) {
    child.stdout.on('data', (chunk) => {
      stdout.append(chunk);
      options.onStdout?.(chunk);
    });
    child.stderr.on('data', (chunk) => {
      stderr.append(chunk);
      options.onStderr?.(chunk);
    });
  }

  const interrupt = () => {
    void stop('SIGINT').catch(() => {});
  };
  const terminate = () => {
    void stop('SIGTERM').catch(() => {});
  };
  const abort = () => {
    void stop('SIGTERM').catch(() => {});
  };

  const cleanup = () => {
    process.removeListener('SIGINT', interrupt);
    process.removeListener('SIGTERM', terminate);
    options.signal?.removeEventListener('abort', abort);
  };

  const completion = new Promise<ProcessResult>((resolve, reject) => {
    child.once('error', (cause) => {
      failure = new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot launch ${command}: ${cause.message}`, {
        cause,
        operation: options.operation || 'spawn',
      });
    });
    finish = async (code, signal) => {
      try {
        await stopping;
      } catch (cause) {
        failure = new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot stop ${command}: ${cause.message}`, {
          cause, operation: options.operation || 'spawn',
        });
      }

      if (closed) return;
      closed = true;
      cleanup();

      if (failure) reject(failure);
      else resolve({
        code: code === null ? 1 : code,
        signal,
        stderr: stderr.toString(),
        stdout: stdout.toString(),
        timedOut: false,
      });
    };

    child.once('close', (code, signal) => {
      void finish(code, signal);
    });
  });
  // A readiness probe may be the first consumer. Keep early spawn failures from
  // becoming unhandled rejections while the probe is still polling.
  completion.catch(() => {});

  async function stop(signal: NodeJS.Signals = 'SIGTERM', graceMs = DefaultStopGraceMs) {
    if (stopPromise) return stopPromise;
    if (closed) return completion;

    stopped = true;
    stopping = Promise.resolve().then(() => terminateProcess(child, signal));
    stopPromise = (async () => {
      if (process.platform === 'win32') {
        void finish(null, signal);
        return completion;
      }

      try {
        await stopping;
      } catch {
        await finish(null, signal);
        return completion;
      }

      let timer: NodeJS.Timeout | undefined;

      await Promise.race([
        completion.catch(() => undefined),
        new Promise((resolve) => {
          timer = setTimeout(resolve, graceMs);
          timer.unref?.();
        }),
      ]);

      if (timer) clearTimeout(timer);
      if (!closed) {
        stopping = terminateProcess(child, 'SIGKILL');
        try {
          await stopping;
        } catch {
          await finish(null, signal);
        }
      }

      return completion.catch(() => undefined);
    })();
    stopPromise.catch(() => {});

    return stopPromise;
  }

  process.once('SIGINT', interrupt);
  process.once('SIGTERM', terminate);
  if (options.signal?.aborted) abort();
  else options.signal?.addEventListener('abort', abort, { once: true });

  return {
    child,
    completion,
    getStderr: () => stderr.toString(),
    getStdout: () => stdout.toString(),
    stop,
    wasStopped: () => stopped,
  };
}

async function runCheckedAsync(
  command: string,
  args: string[],
  options: CheckedProcessOptions
) {
  const result = await spawnAsync(command, args, {
    capture: true,
    cwd: options.cwd,
    env: options.env,
    operation: options.operation,
    outputLimit: options.outputLimit || 2 * 1024 * 1024,
    timeoutMs: options.timeoutMs,
  });

  if (result.code !== 0 || result.timedOut) {
    const diagnostics = formatDiagnostics(result);

    throw new HarmonyCliError(
      options.code,
      `${options.message} exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.${diagnostics ? `\n${diagnostics}` : ''}`,
      { exitCode: result.code || 1, operation: options.operation }
    );
  }

  return result;
}

export { formatDiagnostics, runCheckedAsync, spawnAsync, startManagedProcess };
