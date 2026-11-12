/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { rcp } from '@kit.RemoteCommunicationKit';

// Header names such as "__proto__" must be ordinary keys. Object.create is TS-only.
export function createHeaderRecord(): rcp.RequestHeaders {
  return Object.create(null) as rcp.RequestHeaders;
}
