/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { RNInstance, RNInstanceImpl } from '@rnoh/react-native-openharmony/src/main/ets/RNOH/RNInstance';
import type { RNOHError } from '@rnoh/react-native-openharmony/src/main/ets/RNOH/RNOHError';

/**
 * RNOH 0.86.1 still flattens structured stacks in reportRNOHError. Observe that
 * boundary before information is lost; never parse its diagnostic context header.
 * Core provides the bundle provider even before the first download succeeds.
 */
export class RnohLogBoxAdapter {
  private reporting?: RNOHError;
  private readonly restore?: () => void;

  constructor(
    private readonly instance: RNInstance,
    private readonly getBundleUrl: () => string | undefined,
  ) {
    const reportable = instance as RNInstanceImpl;
    const report = reportable.reportRNOHError;
    if (typeof report !== 'function') return;

    const reportWrapper = (error: RNOHError): void => {
      const previous = this.reporting;
      this.reporting = error;
      try {
        report.call(instance, error);
      } finally {
        this.reporting = previous;
      }
    };
    reportable.reportRNOHError = reportWrapper;
    this.restore = () => {
      if (reportable.reportRNOHError === reportWrapper) reportable.reportRNOHError = report;
    };
  }

  originalError(fallback: RNOHError): RNOHError {
    return this.reporting ?? fallback;
  }

  bundleUrl(): string | undefined {
    return this.getBundleUrl() ?? this.instance.getInitialBundleUrl();
  }

  dispose(): void {
    this.restore?.();
    this.reporting = undefined;
  }
}
