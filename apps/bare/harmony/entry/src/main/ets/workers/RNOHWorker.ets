/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { setupRNOHWorker } from '@rnoh/react-native-openharmony/src/main/ets/setupRNOHWorker';
import { createRNOHWorkerPackages } from '../RNOHWorkerPackagesFactory';

setupRNOHWorker({
  createWorkerRNInstanceConfig: () => ({
    thirdPartyPackagesFactory: createRNOHWorkerPackages,
  }),
});
