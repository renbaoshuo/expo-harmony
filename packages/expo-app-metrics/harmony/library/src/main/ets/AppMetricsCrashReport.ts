/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { LogRecord } from './AppMetricsModels.ts';
import { optionalMap, optionalText, truncateLogText } from './AppMetricsLogging.ts';

export class CrashStackFrame {
  symbol?: string;
  binaryName?: string;
}
export class CrashStack {
  threadAttributed: boolean = true;
  callStackRootFrames: CrashStackFrame[] = [];
}
export class CrashStackTree {
  callStacks: CrashStack[] = [];
}
export class CrashReport {
  eventId: string;
  sessionId: string | null = null;
  signal?: number;
  terminationReason?: string;
  exceptionReason?: string;
  exceptionName?: string;
  crashType?: string;
  callStackTree?: CrashStackTree;
  appVersion: string;
  timestampBegin: string;
  ingestedAt: string;

  constructor(eventId: string, version: string, timestamp: string) {
    this.eventId = eventId;
    this.appVersion = version;
    this.timestampBegin = timestamp;
    this.ingestedAt = new Date().toISOString();
  }
}

/** The HiAppEvent schema is documented by Huawei; never parse private crash-log text. */
export function crashFromSystemEvent(name: string, params: Record<string, ESObject>): CrashReport | undefined {
  const time: ESObject = params['time'];
  const version: ESObject = params['bundle_version'];
  if (typeof time !== 'number' || !Number.isFinite(time) || time <= 0 || !Number.isFinite(new Date(time).getTime()) || typeof version !== 'string') {
    return undefined;
  }

  const id = `${name}:${time}:${String(params['pid'])}:${optionalText(params['uuid']) ?? ''}`;
  const report = new CrashReport(id, version, new Date(time).toISOString());
  report.crashType = optionalText(params['crash_type']);
  const exception = optionalMap(params['exception']);
  report.terminationReason = optionalText(exception?.['message']);
  const kind = optionalText(exception?.['name']);
  report.exceptionName = kind;
  if (kind !== undefined) report.exceptionReason = `${kind}: ${report.terminationReason ?? ''}`;
  const signal = optionalMap(exception?.['signal']);
  const signo: ESObject = signal?.['signo'];
  if (typeof signo === 'number' && Number.isSafeInteger(signo) && signo > 0) report.signal = signo;

  const tree = new CrashStackTree();
  const tid = exception?.['tid'];
  const stack = new CrashStack();
  const frames: ESObject = exception?.['frames'];
  stack.callStackRootFrames = readFrames(frames);
  if (stack.callStackRootFrames.length === 0) {
    const text = optionalText(exception?.['stack']);
    text?.split('\n').filter((line: string): boolean => line.trim().length > 0).forEach((line: string): void => {
      const frame = new CrashStackFrame();
      frame.symbol = line;
      stack.callStackRootFrames.push(frame);
    });
  }

  const threads: ESObject = params['threads'];
  if (Array.isArray(threads)) {
    (threads as ESObject[]).forEach((raw: ESObject): void => {
      const thread = optionalMap(raw);
      const frames = readFrames(thread?.['frames']);
      if (frames.length === 0) return;

      if (typeof tid === 'number' && thread?.['tid'] === tid) {
        // The thread list carries the full stack when the exception has only a summary.
        stack.callStackRootFrames = frames;
        return;
      }
      const other = new CrashStack();
      other.threadAttributed = false;
      other.callStackRootFrames = frames;
      tree.callStacks.push(other);
    });
  }
  if (stack.callStackRootFrames.length > 0) tree.callStacks.unshift(stack);
  if (tree.callStacks.length > 0) report.callStackTree = tree;

  return report;
}

function readFrames(value: ESObject): CrashStackFrame[] {
  if (!Array.isArray(value)) return [];

  const frames: CrashStackFrame[] = [];
  (value as ESObject[]).forEach((raw: ESObject): void => {
    const input = optionalMap(raw);
    if (input === undefined) return;
    const frame = new CrashStackFrame();
    frame.symbol = optionalText(input['symbol']);
    frame.binaryName = optionalText(input['file']);
    if (frame.symbol !== undefined || frame.binaryName !== undefined) frames.push(frame);
  });

  return frames;
}

// SDK 57 limits diagnostic log rendering while retaining the complete crash report.
const MAX_LOG_STACK_FRAMES: number = 50;
const MAX_LOG_STACKTRACE_LENGTH: number = 65_536;

export function signalName(signal: number): string {
  // These are the stable POSIX signal numbers used by HarmonyOS and upstream Android.
  switch (signal) {
    case 4: return 'SIGILL';
    case 5: return 'SIGTRAP';
    case 6: return 'SIGABRT';
    case 7: return 'SIGBUS';
    case 8: return 'SIGFPE';
    case 9: return 'SIGKILL';
    case 11: return 'SIGSEGV';
    case 15: return 'SIGTERM';
    default: return `SIG${signal}`;
  }
}

export function nativeCrashLog(report: CrashReport): LogRecord {
  const name = report.signal === undefined ? undefined : signalName(report.signal);
  const attributes: Record<string, ESObject> = {
    'exception.type': report.exceptionName ?? name ?? report.crashType ?? 'NativeCrash',
    'exception.message': report.terminationReason ?? report.exceptionReason ?? name ?? 'Process crash',
    'expo.error.source': report.crashType === 'JsError' ? 'arktsCrash' : 'nativeCrash',
    'expo.error.is_fatal': true,
  };
  if (report.signal !== undefined) {
    attributes['expo.crash.signal'] = name;
    attributes['expo.crash.signal_number'] = report.signal;
  }
  if (report.terminationReason !== undefined) attributes['expo.crash.termination_reason'] = report.terminationReason;
  const symbols: string[] = [];
  const stacks = report.callStackTree?.callStacks ?? [];
  const attributed = stacks.filter((stack: CrashStack): boolean => stack.threadAttributed);
  (attributed.length > 0 ? attributed : stacks).forEach((stack: CrashStack): void => {
    stack.callStackRootFrames.forEach((frame: CrashStackFrame): void => { symbols.push(frame.symbol ?? '<unknown>'); });
  });
  let stacktrace: string | null = null;
  if (symbols.length > 0) {
    const rendered = symbols.slice(0, MAX_LOG_STACK_FRAMES);
    if (symbols.length > MAX_LOG_STACK_FRAMES) rendered.push(`… +${symbols.length - MAX_LOG_STACK_FRAMES} more frames`);
    stacktrace = truncateLogText(rendered.join('\n'), MAX_LOG_STACKTRACE_LENGTH, (message: string): void => console.warn(message));
  }
  attributes['exception.stacktrace'] = stacktrace;
  const log = new LogRecord(report.timestampBegin, 'native.exception', 'fatal', undefined, attributes);
  log.recordId = report.eventId;

  return log;
}

export function decodeCrashReport(value: ESObject): CrashReport | undefined {
  const input = optionalMap(value);
  if (input === undefined || typeof input['eventId'] !== 'string' || typeof input['appVersion'] !== 'string'
    || typeof input['timestampBegin'] !== 'string' || !Number.isFinite(Date.parse(input['timestampBegin']))
    || typeof input['ingestedAt'] !== 'string' || !Number.isFinite(Date.parse(input['ingestedAt']))) return undefined;

  const result = new CrashReport(input['eventId'], input['appVersion'], input['timestampBegin']);
  result.ingestedAt = input['ingestedAt'];
  result.sessionId = optionalText(input['sessionId']) ?? null;
  const signal: ESObject = input['signal'];
  if (typeof signal === 'number' && Number.isSafeInteger(signal)) result.signal = signal;
  result.terminationReason = optionalText(input['terminationReason']);
  result.exceptionReason = optionalText(input['exceptionReason']);
  result.exceptionName = optionalText(input['exceptionName']);
  result.crashType = optionalText(input['crashType']);
  const tree = optionalMap(input['callStackTree']);
  const stacks: ESObject = tree?.['callStacks'];
  if (Array.isArray(stacks)) {
    result.callStackTree = new CrashStackTree();
    (stacks as ESObject[]).forEach((raw: ESObject): void => {
      const stackInput = optionalMap(raw);
      const frames: ESObject = stackInput?.['callStackRootFrames'];
      if (!Array.isArray(frames)) return;

      const stack = new CrashStack();
      if (typeof stackInput?.['threadAttributed'] === 'boolean') stack.threadAttributed = stackInput['threadAttributed'];
      (frames as ESObject[]).forEach((rawFrame: ESObject): void => {
        const frameInput = optionalMap(rawFrame);
        if (frameInput === undefined) return;
        const frame = new CrashStackFrame();
        frame.symbol = optionalText(frameInput['symbol']);
        frame.binaryName = optionalText(frameInput['binaryName']);
        stack.callStackRootFrames.push(frame);
      });
      result.callStackTree?.callStacks.push(stack);
    });
  }

  return result;
}

export function copyCrashReport(report: CrashReport): CrashReport {
  return decodeCrashReport(JSON.parse(JSON.stringify(report)) as ESObject) as CrashReport;
}
