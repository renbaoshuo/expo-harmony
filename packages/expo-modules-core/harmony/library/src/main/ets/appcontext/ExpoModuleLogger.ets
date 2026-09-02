import type { RNOHLogger } from '@rnoh/react-native-openharmony';

/** Author-facing logger scoped to one Expo Module instance. */
export interface ExpoModuleLogger {
  debug(message: string): void;
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

/** @internal */
export function createExpoModuleLogger(logger: RNOHLogger, moduleName: string): ExpoModuleLogger {
  return new RNOHExpoModuleLogger(logger.clone(['ExpoModules', moduleName]));
}

class RNOHExpoModuleLogger implements ExpoModuleLogger {
  private readonly logger: RNOHLogger;

  constructor(logger: RNOHLogger) {
    this.logger = logger;
  }

  debug(message: string): void {
    this.logger.debug(message);
  }

  info(message: string): void {
    this.logger.info(message);
  }

  warn(message: string): void {
    this.logger.warn(message);
  }

  error(message: string): void {
    this.logger.error(message);
  }
}
