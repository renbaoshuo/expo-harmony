/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export interface AssetPluginOptions {
  /** Paths to asset files or directories, relative to the project root. */
  assets?: string[];
}

export default function assets(
  props?: AssetPluginOptions
): ['@expo-harmony/expo-asset', AssetPluginOptions];
