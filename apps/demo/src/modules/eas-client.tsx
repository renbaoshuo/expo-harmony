/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { clientID, deterministicUniformValue } from 'expo-eas-client';

import { DataRow, Panel } from '../ui';

export function EASClientDemo() {
  return (
    <Panel title="客户端标识">
      <DataRow label="clientID" value={String(clientID)} />
      <DataRow label="deterministicUniformValue" value={String(deterministicUniformValue)} />
    </Panel>
  );
}
