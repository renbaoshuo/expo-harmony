/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';
import { hvigor, type HvigorPlugin } from '@ohos/hvigor';
import { appTasks, OhosPluginId, type OhosAppContext, type OhosHapContext } from '@ohos/hvigor-ohos-plugin';
import { prepareHarmonyBundleTask, publishHarmonyNativeRuntime } from '@expo-harmony/cli/native-build';

import { writeStamp } from './native-inputs-stamp';

process.env.HERMES_V1_ENABLED = 'true';

const BundlerPlugin: HvigorPlugin = {
  pluginId: 'expo-harmony-bundler',
  apply(node) {
    const harmony = node.getNodePath();
    const root = path.dirname(harmony);
    const embedded = path.join(root, '__EXPO_HARMONY_BUNDLE_PATH__');

    writeStamp(root, harmony);

    hvigor.nodesEvaluated(() => {
      const app = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
      const mode = app.getBuildMode() === 'release' ? 'release' : 'debug';

      publishHarmonyNativeRuntime(root, mode);
      const bundle = prepareHarmonyBundleTask(
        root, mode, finish => hvigor.buildFinished(finish), embedded
      );

      node.subNodes((entry) => {
        const hap = entry.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext | undefined;
        if (hap?.getModuleType() !== 'entry') return;

        hap.targets((target) => {
          const targetName = target.getTargetName();

          entry.registerTask({
            name: `${targetName}@ExpoHarmonyBundle`,
            run: bundle,
            dependencies: [`${targetName}@ProcessResource`],
            postDependencies: [`${targetName}@CompileResource`],
          });
        });
      });
    });
  },
};

export default {
  system: appTasks,
  plugins: [BundlerPlugin],
};
