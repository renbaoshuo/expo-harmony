/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { GLViewProps } from 'expo-gl';
import type { Component } from 'react';

export type ProcessingViewProps = Omit<GLViewProps, 'onContextCreate'> & {
  /** Draws a sketch with the Processing.js instance. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- Processing.js does not publish types.
  sketch?: (processing: any) => void;
};

export declare class ProcessingView extends Component<ProcessingViewProps> {}
