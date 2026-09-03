import spawn from 'cross-spawn';

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
    const piped = Boolean(options.capture || options.onStdout || options.onStderr);
    const outputLimit = options.outputLimit || DefaultOutputLimit;
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      shell: false,
      stdio: piped ? ['ignore', 'pipe', 'pipe'] : 'inherit',
      windowsHide: true,
    });

    const stdout = new BoundedCapture(outputLimit);
    const stderr = new BoundedCapture(outputLimit);
    let timedOut = false;
    let settled = false;
    let forceKillTimer: NodeJS.Timeout | null = null;

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

    const stopChild = (signal: NodeJS.Signals = 'SIGTERM') => {
      child.kill(signal);
      if (forceKillTimer === null) {
        forceKillTimer = setTimeout(
          () => child.kill('SIGKILL'),
          options.stopGraceMs || DefaultStopGraceMs
        );
        forceKillTimer.unref?.();
      }
    };

    const forwardSigint = () => stopChild('SIGINT');
    const forwardSigterm = () => stopChild('SIGTERM');
    process.once('SIGINT', forwardSigint);
    process.once('SIGTERM', forwardSigterm);

    const timeout = options.timeoutMs
      ? setTimeout(() => {
          timedOut = true;
          stopChild('SIGTERM');
        }, options.timeoutMs)
      : null;
    timeout?.unref?.();

    const cleanup = () => {
      if (timeout) clearTimeout(timeout);
      if (forceKillTimer) clearTimeout(forceKillTimer);
      process.removeListener('SIGINT', forwardSigint);
      process.removeListener('SIGTERM', forwardSigterm);
      options.signal?.removeEventListener('abort', abort);
    };

    const abort = () => stopChild('SIGTERM');
    if (options.signal?.aborted) abort();
    else options.signal?.addEventListener('abort', abort, { once: true });

    child.once('error', (cause) => {
      if (settled) return;
      settled = true;
      cleanup();

      reject(new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot launch ${command}: ${cause.message}`, {
        cause,
        operation: options.operation || 'spawn',
      }));
    });
    // `close` runs after stdout/stderr have closed, so captured diagnostics are
    // complete. `exit` can fire while pipe data is still pending.
    child.once('close', (code, signal) => {
      if (settled) return;
      settled = true;
      cleanup();

      resolve({
        code: code === null ? 1 : code,
        signal,
        stderr: stderr.toString(),
        stdout: stdout.toString(),
        timedOut,
      });
    });
  });
}

function startManagedProcess(command: string, args: string[], options: ProcessOptions = {}) {
  const outputLimit = options.outputLimit || DefaultOutputLimit;
  const piped = options.stdio !== 'inherit';
  const child = spawn(command, args, {
    cwd: options.cwd,
    env: options.env || process.env,
    shell: false,
    stdio: piped ? ['ignore', 'pipe', 'pipe'] : 'inherit',
    windowsHide: true,
  });

  const stdout = new BoundedCapture(outputLimit);
  const stderr = new BoundedCapture(outputLimit);
  let spawnError: HarmonyCliError | null = null;
  let closed = false;
  let stopRequested = false;

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

  const forwardSigint = () => {
    void stop('SIGINT');
  };
  const forwardSigterm = () => {
    void stop('SIGTERM');
  };
  const abort = () => {
    void stop('SIGTERM');
  };

  const cleanup = () => {
    process.removeListener('SIGINT', forwardSigint);
    process.removeListener('SIGTERM', forwardSigterm);
    options.signal?.removeEventListener('abort', abort);
  };

  const completion = new Promise<ProcessResult>((resolve, reject) => {
    child.once('error', (cause) => {
      spawnError = new HarmonyCliError('ERR_HARMONY_PROCESS_FAILED', `Cannot launch ${command}: ${cause.message}`, {
        cause,
        operation: options.operation || 'spawn',
      });
    });
    child.once('close', (code, signal) => {
      closed = true;
      cleanup();

      if (spawnError) reject(spawnError);
      else resolve({
        code: code === null ? 1 : code,
        signal,
        stderr: stderr.toString(),
        stdout: stdout.toString(),
        timedOut: false,
      });
    });
  });
  // A readiness probe may be the first consumer. Keep early spawn failures from
  // becoming unhandled rejections while the probe is still polling.
  completion.catch(() => {});

  async function stop(signal: NodeJS.Signals = 'SIGTERM', graceMs = DefaultStopGraceMs) {
    if (closed) return completion;

    stopRequested = true;
    child.kill(signal);
    let timer: NodeJS.Timeout | undefined;

    await Promise.race([
      completion.catch(() => undefined),
      new Promise((resolve) => {
        timer = setTimeout(resolve, graceMs);
        timer.unref?.();
      }),
    ]);

    if (timer) clearTimeout(timer);
    if (!closed) child.kill('SIGKILL');

    return completion.catch(() => undefined);
  }

  process.once('SIGINT', forwardSigint);
  process.once('SIGTERM', forwardSigterm);
  if (options.signal?.aborted) abort();
  else options.signal?.addEventListener('abort', abort, { once: true });

  return {
    child,
    completion,
    getStderr: () => stderr.toString(),
    getStdout: () => stdout.toString(),
    stop,
    wasStopped: () => stopRequested,
  };
}

export { formatDiagnostics, spawnAsync, startManagedProcess };
