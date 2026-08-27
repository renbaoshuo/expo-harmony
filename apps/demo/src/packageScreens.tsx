import { BlurView, type BlurTint } from 'expo-blur';
import Constants from 'expo-constants';
import * as Crypto from 'expo-crypto';
import { EventEmitter, requireOptionalNativeModule } from 'expo-modules-core';
import { router, usePathname, useSegments } from 'expo-router';
import * as TaskManager from 'expo-task-manager';
import { useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';

// @ts-expect-error Metro resolves bundled project assets to numeric asset IDs.
import bundledIcon from '../assets/app-icon.svg';

import {
  BACKGROUND_FETCH_CHECK_TASK,
  BACKGROUND_FETCH_TASK,
} from './backgroundFetch';
import {
  BACKGROUND_TASK,
  BACKGROUND_TASK_CHECK,
} from './backgroundTask';
import type { ModuleId } from './catalog';
import {
  ActionButton,
  ActionRow,
  DataRow,
  Note,
  Panel,
  ResultPanel,
  Tag,
  useAsyncResult,
} from './ui';

function json(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

const TINTS: readonly BlurTint[] = [
  'default',
  'dark',
  'systemMaterialLight',
  'prominent',
];

function BlurDemo() {
  const [tintIndex, setTintIndex] = useState(0);
  const [intensity, setIntensity] = useState(55);
  const tint = TINTS[tintIndex] ?? 'default';

  return (
    <>
      <Panel eyebrow="原生视图" title="渲染由 ArkUI 支持的材质模糊">
        <View style={styles.blurScene}>
          <View style={[styles.blurOrb, styles.blurOrbBlue]} />
          <View style={[styles.blurOrb, styles.blurOrbOrange]} />
          <Text style={styles.blurBackdrop}>HARMONY</Text>
          <BlurView intensity={intensity} style={styles.blurGlass} tint={tint}>
            <Text style={styles.blurLabel}>EXPO BLUR</Text>
            <Text style={styles.blurTitle}>材质模糊背景</Text>
            <Text style={styles.blurValue}>{tint} · {intensity}</Text>
          </BlurView>
        </View>
        <Note>卡片后方的文字与色块应仍然可见，但能看出明显的柔化效果。</Note>
      </Panel>

      <Panel eyebrow="动态属性" title="无需重新挂载即可更新色调与强度">
        <DataRow label="tint" value={tint} />
        <DataRow label="intensity" value={String(intensity)} />
        <ActionRow>
          <ActionButton
            label="下一个色调"
            onPress={() => setTintIndex(value => (value + 1) % TINTS.length)}
            testID="blur-next-tint"
          />
          <ActionButton
            label="强度 +25"
            onPress={() => setIntensity(value => value >= 100 ? 0 : value + 25)}
            testID="blur-next-intensity"
            tone="secondary"
          />
        </ActionRow>
      </Panel>
    </>
  );
}

function CryptoDemo() {
  const primitives = useAsyncResult();
  const aes = useAsyncResult();
  const busy = primitives.state.phase === 'running' || aes.state.phase === 'running';

  const runPrimitives = () => primitives.run(async () => {
    const digest = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, 'abc');
    const expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    if (digest !== expected) throw new Error(`SHA-256 摘要不符合预期：${digest}`);

    const bytes = await Crypto.getRandomBytesAsync(16);
    const uuid = Crypto.randomUUID();
    if (bytes.length !== 16) throw new Error(`预期 16 个随机字节，实际收到 ${bytes.length} 个。`);
    if (!/^[0-9a-f-]{36}$/i.test(uuid)) throw new Error(`无效的 UUID：${uuid}`);

    return json({ digest, randomBytes: Array.from(bytes), uuid });
  });

  const runAes = () => aes.run(async () => {
    const key = await Crypto.AESEncryptionKey.generate(Crypto.AESKeySize.AES128);
    const plaintext = new Uint8Array([0, 1, 2, 3, 250, 251, 252, 253]);
    const sealed = await Crypto.aesEncryptAsync(plaintext, key, {
      nonce: { length: 128 },
      tagLength: 16,
    });
    const decrypted = await Crypto.aesDecryptAsync(sealed, key);
    if (decrypted.length !== plaintext.length || decrypted.some((value, index) => value !== plaintext[index])) {
      throw new Error('AES-GCM 往返结果与原始字节不一致。');
    }

    return json({ bytes: Array.from(decrypted), ivSize: sealed.ivSize, tagSize: sealed.tagSize });
  });

  return (
    <>
      <Panel eyebrow="摘要与随机" title="校验摘要、随机字节与 UUID">
        <ActionButton disabled={busy} label="运行基础加密检测" onPress={() => void runPrimitives()} />
        <ResultPanel state={primitives.state} />
      </Panel>
      <Panel eyebrow="AES-GCM" title="加解密一段精确字节序列">
        <ActionButton disabled={busy} label="运行 AES 往返" onPress={() => void runAes()} />
        <ResultPanel state={aes.state} />
      </Panel>
    </>
  );
}

function ModulesCoreDemo() {
  const registry = useAsyncResult();
  const events = useAsyncResult();

  const inspectRegistry = () => registry.run(() => {
    const expoRuntime = (globalThis as typeof globalThis & {
      expo?: { modules?: Record<string, unknown> };
    }).expo;
    if (!expoRuntime?.modules) throw new Error('globalThis.expo.modules 不可用。');

    const constants = requireOptionalNativeModule('ExponentConstants')
      ?? requireOptionalNativeModule('ExpoConstants');
    if (!constants) throw new Error('未能通过 requireOptionalNativeModule 找到 Constants。');

    return json({
      moduleCount: Object.keys(expoRuntime.modules).length,
      modules: Object.keys(expoRuntime.modules).sort(),
    });
  });

  const runEmitter = () => events.run(() => {
    type Events = { value: (value: number) => void };
    const emitter = new EventEmitter<Events>();
    let observed = 0;
    const subscription = emitter.addListener('value', (value) => {
      observed += value;
    });
    emitter.emit('value', 7);
    subscription.remove();
    emitter.emit('value', 5);
    if (observed !== 7 || emitter.listenerCount('value') !== 0) {
      throw new Error(`EventEmitter 清理失败：observed=${observed}。`);
    }
    return '监听器同步收到 7，并在 remove() 之后不再接收事件。';
  });

  return (
    <>
      <Panel eyebrow="原生注册表" title="检查由 Expo Modules Core 安装的模块">
        <ActionButton label="读取模块注册表" onPress={() => void inspectRegistry()} />
        <ResultPanel state={registry.state} />
      </Panel>
      <Panel eyebrow="C++ 事件发射器" title="添加、触发、计数并移除监听器">
        <ActionButton label="运行事件契约" onPress={() => void runEmitter()} />
        <ResultPanel state={events.state} />
      </Panel>
    </>
  );
}

function RouterDemo() {
  const pathname = usePathname();
  const segments = useSegments();
  const state = useAsyncResult();

  return (
    <>
      <Panel eyebrow="当前路由" title="读取基于文件的路由状态">
        <DataRow label="pathname" value={pathname} />
        <DataRow label="segments" value={segments.join(' / ')} />
        <ActionButton
          label="校验路由状态"
          onPress={() => void state.run(() => {
            if (pathname !== '/module/expo-router') throw new Error(`路径不符合预期：${pathname}`);
            if (!segments.includes('[module]')) throw new Error(`缺少动态路由分段：${segments.join('/')}`);
            return json({ pathname, segments });
          })}
        />
        <ResultPanel state={state.state} />
      </Panel>
      <Panel eyebrow="动态目标页" title="推送 Unicode 路径与查询参数">
        <ActionButton
          label="打开动态路由"
          onPress={() => router.push('/router-fixture/中文?source=expo-router')}
          testID="router-open-dynamic-fixture"
        />
        <Note>该目标页仅限本包使用，不会出现在首页。</Note>
      </Panel>
    </>
  );
}

function TaskManagerDemo() {
  const availability = useAsyncResult();
  const registrations = useAsyncResult();

  const inspectDefinitions = () => availability.run(async () => {
    const available = await TaskManager.isAvailableAsync();
    const definitions = [
      BACKGROUND_FETCH_TASK,
      BACKGROUND_FETCH_CHECK_TASK,
      BACKGROUND_TASK,
      BACKGROUND_TASK_CHECK,
    ].map(taskName => ({ defined: TaskManager.isTaskDefined(taskName), taskName }));
    if (!definitions.every(item => item.defined)) throw new Error(`缺少全局任务定义：${json(definitions)}`);
    return json({ available, definitions });
  });

  const inspectRegistrations = () => registrations.run(async () => {
    const tasks = await TaskManager.getRegisteredTasksAsync();
    return json({ count: tasks.length, tasks });
  });

  return (
    <>
      <Panel eyebrow="全局定义" title="验证任务在 React 挂载前已定义">
        <ActionButton label="检查任务定义" onPress={() => void inspectDefinitions()} />
        <ResultPanel state={availability.state} />
      </Panel>
      <Panel eyebrow="持久化状态" title="列出原生任务注册">
        <ActionButton label="列出已注册任务" onPress={() => void inspectRegistrations()} />
        <ResultPanel state={registrations.state} />
      </Panel>
    </>
  );
}

type BuildPackageId = Extract<ModuleId,
  | 'cli'
  | 'config-plugins'
  | 'expo-modules-autolinking'
  | 'metro-config'
  | 'prebuild-config'
  | 'template'
>;

type ContractDefinition = {
  description: string;
  label: string;
  run: () => Promise<string> | string;
  title: string;
};

function configSnapshot() {
  const config = Constants.expoConfig as (typeof Constants.expoConfig & {
    harmony?: Record<string, unknown>;
    plugins?: unknown[];
  }) | null;
  if (!config?.harmony) throw new Error('缺少内嵌的 Harmony 配置。');
  return config;
}

const BUILD_CONTRACTS: Record<BuildPackageId, readonly ContractDefinition[]> = {
  'cli': [
    {
      description: '确认 CLI 的准备与构建管线产出了 bare 模式的 Harmony 应用。',
      label: '验证构建目标',
      title: 'Harmony 构建目标',
      run: () => {
        const platform = String(Platform.OS);
        const executionEnvironment = String(Constants.executionEnvironment);
        if (platform !== 'harmony') throw new Error(`预期 Harmony 目标，实际为 ${platform}。`);
        if (executionEnvironment !== 'bare') {
          throw new Error(`预期 bare 运行时，实际为 ${executionEnvironment}。`);
        }
        return json({ executionEnvironment, platform });
      },
    },
    {
      description: '读取由 CLI/prebuild 管线内嵌的应用标识与 Harmony 配置。',
      label: '读取构建配置',
      title: '内嵌的项目配置',
      run: () => {
        const config = configSnapshot();
        return json({
          harmony: config.harmony,
          name: config.name,
          scheme: config.scheme,
          slug: config.slug,
          version: config.version,
        });
      },
    },
  ],
  'config-plugins': [
    {
      description: '读取配置插件全部执行完毕后内嵌的应用配置。',
      label: '读取生成的配置',
      title: '内嵌的 Harmony 配置',
      run: () => json(configSnapshot()),
    },
    {
      description: '验证当前包集合所需的插件均已声明。',
      label: '检查插件归属',
      title: '已配置的插件',
      run: () => {
        const plugins = configSnapshot().plugins ?? [];
        if (plugins.length === 0) throw new Error('未内嵌任何配置插件。');
        return json(plugins);
      },
    },
  ],
  'expo-modules-autolinking': [
    {
      description: '检查 prebuild 期间由自动链接生成的原生注册表。',
      label: '读取已链接模块',
      title: '运行时注册表输出',
      run: () => {
        const modules = (
          globalThis as typeof globalThis & { expo?: { modules?: Record<string, unknown> } }
        ).expo?.modules;
        if (!modules || Object.keys(modules).length === 0) throw new Error('没有注册任何自动链接的 Expo 模块。');
        return json(Object.keys(modules).sort());
      },
    },
    {
      description: '通过注册表直接获取已知模块，而非导入其 JavaScript 门面。',
      label: '获取已知模块',
      title: '已知模块解析',
      run: () => {
        const module = requireOptionalNativeModule('ExponentConstants') ?? requireOptionalNativeModule('ExpoConstants');
        if (!module) throw new Error('未能从原生注册表解析到 Constants。');
        return '已从自动链接的 Expo 模块注册表解析到 Constants。';
      },
    },
  ],
  'metro-config': [
    {
      description: '确认 Metro 已转换并注册项目的 SVG 资源。',
      label: '检查打包资源',
      title: '资源转换',
      run: () => {
        if (typeof bundledIcon !== 'number') throw new Error(`预期数值型 Metro 资源 ID，实际为 ${typeof bundledIcon}。`);
        return json({ assetId: bundledIcon, dev: __DEV__, platform: Platform.OS });
      },
    },
    {
      description: '确认模块重定向后 Harmony 运行时与 Expo 桥接仍可用。',
      label: '检查 Harmony 目标',
      title: '解析器目标',
      run: () => json({ expoRuntime: typeof globalThis.expo, platform: Platform.OS }),
    },
  ],
  'prebuild-config': [
    {
      description: '检查写入原生 Harmony 工程的关键值。',
      label: '验证 prebuild 值',
      title: '原生工程描述',
      run: () => {
        const config = configSnapshot();
        const harmony = config.harmony as Record<string, unknown>;
        if (harmony.bundleName !== 'com.expo.harmony.demo') throw new Error(`应用包名不符合预期：${String(harmony.bundleName)}`);
        return json(harmony);
      },
    },
    {
      description: '确认启动屏、导航栏、音频与后台插件已进入应用配置。',
      label: '读取 prebuild 输入',
      title: '插件输入',
      run: () => json(configSnapshot().plugins ?? []),
    },
  ],
  'template': [
    {
      description: '检查模板约定的 React Native、Expo 与 Harmony 运行时基线。',
      label: '检查模板运行时',
      title: '运行时基线',
      run: () => {
        const version = Platform.constants?.reactNativeVersion;
        if (!version) throw new Error('无法获取 React Native 版本。');
        return json({
          executionEnvironment: Constants.executionEnvironment,
          expo: Constants.expoVersion,
          reactNative: version,
        });
      },
    },
    {
      description: '确认模板的应用标识与 scheme 已内嵌。',
      label: '检查模板配置',
      title: '应用基线',
      run: () => {
        const config = configSnapshot();
        return json({ name: config.name, scheme: config.scheme, slug: config.slug, version: config.version });
      },
    },
  ],
};

function ContractCard({ definition }: { definition: ContractDefinition }) {
  const result = useAsyncResult();
  return (
    <Panel eyebrow="构建契约" title={definition.title}>
      <Note>{definition.description}</Note>
      <ActionButton
        disabled={result.state.phase === 'running'}
        label={definition.label}
        onPress={() => void result.run(definition.run)}
      />
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function BuildPackageDemo({ id }: { id: BuildPackageId }) {
  return <>{BUILD_CONTRACTS[id].map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}

export function AdditionalModuleDemo({ id }: { id: ModuleId }) {
  switch (id) {
    case 'blur': return <BlurDemo />;
    case 'crypto': return <CryptoDemo />;
    case 'expo-modules-core': return <ModulesCoreDemo />;
    case 'expo-router': return <RouterDemo />;
    case 'expo-task-manager': return <TaskManagerDemo />;
    case 'cli':
    case 'config-plugins':
    case 'expo-modules-autolinking':
    case 'metro-config':
    case 'prebuild-config':
    case 'template':
      return <BuildPackageDemo id={id} />;
    default:
      return (
        <Panel eyebrow="无测试" title="未注册该包的测试页面">
          <Tag tone="danger">{id}</Tag>
        </Panel>
      );
  }
}

const styles = StyleSheet.create({
  blurBackdrop: { color: '#FFCC00', fontSize: 38, fontWeight: '900', left: 18, letterSpacing: -2, position: 'absolute', top: 26 },
  blurGlass: { borderColor: 'rgba(255,255,255,0.36)', borderRadius: 18, borderWidth: 1, bottom: 22, gap: 7, left: 18, overflow: 'hidden', padding: 20, position: 'absolute', right: 18 },
  blurLabel: { color: '#FFCC00', fontSize: 10, fontWeight: '800', letterSpacing: 1.2 },
  blurOrb: { borderRadius: 90, height: 170, position: 'absolute', width: 170 },
  blurOrbBlue: { backgroundColor: '#32ADE6', bottom: -38, right: -36 },
  blurOrbOrange: { backgroundColor: '#FF6B35', right: 12, top: 44 },
  blurScene: { backgroundColor: '#263643', borderRadius: 14, height: 300, overflow: 'hidden' },
  blurTitle: { color: '#FFFFFF', fontSize: 24, fontWeight: '800' },
  blurValue: { color: '#F5F7FA', fontFamily: 'monospace', fontSize: 11 },
});
