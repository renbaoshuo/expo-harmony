/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { createRNOHProjectPlugin } from '@rnoh/hvigor-plugin';
import { prepareHarmonyBundleTask, prepareHarmonyNativeBuild } from '@expo-harmony/cli/native-build';

const projectRoot = path.resolve('..');
process.env.HERMES_V1_ENABLED = 'true';

export default {
  system: appTasks,
  plugins: [
    createRNOHProjectPlugin({
      nodeModulesPath: path.join(projectRoot, 'node_modules'),
      bundler: { enabled: false },
    }),
    {
      pluginId: 'expo-harmony-bare',
      apply(node) {
        hvigor.nodesEvaluated(() => {
          const mode = node.getContext(OhosPluginId.OHOS_APP_PLUGIN).getBuildMode();
          const buildMode = mode === 'release' ? 'release' : 'debug';

          prepareHarmonyNativeBuild(projectRoot, buildMode);
          const bundle = prepareHarmonyBundleTask(projectRoot, buildMode, finish => hvigor.buildFinished(finish));

          node.subNodes((moduleNode) => {
            const hapContext = moduleNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN);
            if (hapContext?.getModuleType() !== 'entry') return;

            hapContext.targets((target) => {
              const name = target.getTargetName();
              moduleNode.registerTask({
                name: `${name}@ExpoHarmonyBundle`,
                run: bundle,
                dependencies: [`${name}@ProcessResource`],
                postDependencies: [`${name}@CompileResource`],
              });
            });
          });
        });
      },
    },
  ],
};
