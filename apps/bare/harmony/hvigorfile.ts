import path from 'node:path';
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { createRNOHProjectPlugin } from '@rnoh/hvigor-plugin';
import { prepareHarmonyNativeBuild, bundleHarmonyNativeBuild } from '@expo-harmony/cli/native-build';

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
          prepareHarmonyNativeBuild(projectRoot, mode === 'release' ? 'release' : 'debug');
          if (mode !== 'release') return;
          node.subNodes(moduleNode => {
            moduleNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN)?.targets(target => {
              const name = target.getTargetName();
              moduleNode.registerTask({
                name: `${name}@ExpoHarmonyBundle`,
                run: () => bundleHarmonyNativeBuild(projectRoot),
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
