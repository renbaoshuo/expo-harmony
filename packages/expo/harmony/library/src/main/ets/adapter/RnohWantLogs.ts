/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

interface WantLogger {
  clone(segment: string | string[]): WantLogger;
  info(...values: unknown[]): void;
}

export function redactRnohWantLogs<T extends WantLogger>(logger: T): T {
  const clone = logger.clone.bind(logger);
  logger.clone = (segment) => {
    const child = clone(segment);
    if (segment === 'RNAbility') {
      const info = child.info.bind(child);
      child.info = (...values: unknown[]) => {
        const message = values[0];
        // RNOH logs the whole incoming URI, including authorization callback parameters.
        if (typeof message === 'string' && message.startsWith('NewWant: uri=')) info('NewWant: received a link');
        else info(...values);
      };
    }

    return child;
  };
  return logger;
}
