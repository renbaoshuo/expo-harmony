/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { RNOHLogger } from '@rnoh/react-native-openharmony';
import { Logger, LogHandler, LogType } from '../logging/Logger';
import { describeLogError } from '../logging/LogHandlers';

export type ExpoModuleLogger = Logger;

type JSLogReporter = (type: LogType, message: string) => void;

export function createExpoModuleLogger(logger: RNOHLogger, moduleName: string, debug: boolean, report: JSLogReporter): ExpoModuleLogger {
  return new Logger([new RNOHLogHandler(logger.clone(['ExpoModulesCore', moduleName]), debug ? report : undefined)], debug);
}

class RNOHLogHandler implements LogHandler {
  private readonly logger: RNOHLogger;
  private readonly report?: JSLogReporter;
  constructor(logger: RNOHLogger, report?: JSLogReporter) {
    this.logger = logger;
    this.report = report;
  }

  log(type: LogType, message: string, cause?: Error): void {
    const text = cause === undefined ? message : `${message}\n${describeLogError(cause)}`;
    switch (type) {
      case 'info':
        this.logger.info(text);
        break;
      case 'warn':
        this.logger.warn(text);
        break;
      case 'error':
        this.logger.error(text);
        break;
      case 'fatal':
        this.logger.fatal(text);
        break;
      default:
        this.logger.debug(text);
    }
    this.report?.(type, text);
  }
}
