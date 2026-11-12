/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ConfigPlugin } from 'expo/config-plugins';
import type sqlite from 'expo-sqlite/plugin';

declare const withHarmonySQLite: ConfigPlugin<withHarmonySQLite.SQLitePluginProps | void>;

declare namespace withHarmonySQLite {
  type UpstreamSQLitePluginProps = NonNullable<Parameters<typeof sqlite>[0]>;

  type HarmonySQLiteOptions = Pick<UpstreamSQLitePluginProps,
    'enableFTS' | 'customBuildFlags' | 'useSQLCipher' | 'useLibSQL' | 'withSQLiteVecExtension'>;

  type SQLitePluginProps = UpstreamSQLitePluginProps & { harmony?: HarmonySQLiteOptions };
}

export = withHarmonySQLite;
