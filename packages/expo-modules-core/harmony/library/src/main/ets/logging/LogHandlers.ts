/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import hilog from '@ohos.hilog';
import { LogHandler, LogType } from './Logger';
import { PersistentFileLog } from './PersistentFileLog';

const APP_LOG_DOMAIN = 0;

interface LogError extends Error { cause?: Error; }

export function describeLogError(error: Error): string {
  const messages: string[] = [];
  const seen = new Set<Error>();
  let current: LogError | undefined = error;
  while (current instanceof Error && !seen.has(current)) {
    seen.add(current);
    messages.push(current.message);
    current = current.cause;
  }

  return messages.join(' Caused by: ') + (error.stack ? `\n${error.stack}` : '');
}

export class LogHandlers {
  static createOSLogHandler(category: string): LogHandler { return new OSLogHandler(category); }
  static createPersistentFileLogHandler(filesDirectory: string, category: string): LogHandler {
    return new PersistentFileLogHandler(category, filesDirectory);
  }
}

class OSLogHandler implements LogHandler {
  constructor(private readonly category: string) {}

  log(type: LogType, message: string, cause?: Error): void {
    const text = cause === undefined ? message : `${message}\n${describeLogError(cause)}`;
    switch (type) {
      case 'info': hilog.info(APP_LOG_DOMAIN, this.category, '%{public}s', text); break;
      case 'warn': hilog.warn(APP_LOG_DOMAIN, this.category, '%{public}s', text); break;
      case 'error': hilog.error(APP_LOG_DOMAIN, this.category, '%{public}s', text); break;
      case 'fatal': hilog.fatal(APP_LOG_DOMAIN, this.category, '%{public}s', text); break;
      default: hilog.debug(APP_LOG_DOMAIN, this.category, '%{public}s', text);
    }
  }
}

class PersistentFileLogHandler implements LogHandler {
  private readonly file: PersistentFileLog;
  constructor(category: string, filesDirectory: string) { this.file = new PersistentFileLog(category, filesDirectory); }

  log(_type: LogType, message: string, cause?: Error): void {
    const text = cause === undefined ? message : `${message}\n${describeLogError(cause)}`;
    this.file.appendEntry(text).catch(error => console.error(`Unable to persist log: ${String(error)}`));
  }
}
