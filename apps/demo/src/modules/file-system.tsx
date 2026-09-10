import { Directory, File, Paths } from 'expo-file-system';
import { ActionButton, ActionRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function FileSystemDemo() {
  const operation = useAsyncResult();

  const runSandbox = () => operation.run(async () => {
    const directory = new Directory(Paths.cache, 'expo-harmony-demo-manual');
    try {
      directory.create({ idempotent: true, intermediates: true });
      const source = new File(directory, 'source.txt');
      source.create({ overwrite: true });
      source.write('Harmony file system\n', { append: false });
      source.write(new TextEncoder().encode('shared object API'), { append: true });

      const copied = new File(directory, 'copy.txt');
      source.copy(copied);
      const moved = new File(directory, 'moved.txt');
      copied.move(moved);
      copied.rename('renamed.txt');

      const handle = source.open();
      let prefix: Uint8Array;
      try {
        handle.offset = 0;
        prefix = handle.readBytes(7);
      } finally {
        handle.close();
      }

      return json({
        contentUri: source.contentUri,
        entries: directory.list().map(entry => entry.uri),
        md5: source.info({ md5: true }).md5,
        prefix: new TextDecoder().decode(prefix),
        size: source.size,
        text: await source.text(),
      });
    } finally {
      if (directory.exists) directory.delete();
    }
  });

  const pickFile = () => operation.run(async () => {
    const selection = await File.pickFileAsync(undefined, '*/*');
    const file = Array.isArray(selection) ? selection[0] : selection;
    if (!file) throw new Error('选择器未返回文件。');
    const handle = file.open();
    let sample: Uint8Array;
    try {
      sample = handle.readBytes(Math.min(file.size, 64));
    } finally {
      handle.close();
    }
    return json({
      contentUri: file.contentUri,
      exists: file.exists,
      mimeType: file.type,
      sampleBytes: Array.from(sample),
      size: file.size,
      uri: file.uri,
    });
  });

  const pickDirectory = () => operation.run(async () => {
    const directory = await Directory.pickDirectoryAsync();
    return json({
      entries: directory.list().slice(0, 12).map(entry => entry.uri),
      exists: directory.exists,
      size: directory.size,
      uri: directory.uri,
    });
  });

  const runReadContracts = () => operation.run(async () => {
    const { assertFileSystemReadContracts, assertFileSystemRawDirectoryContracts } = await import('./file-system/assertions');
    return json({
      reads: await assertFileSystemReadContracts(),
      resources: await assertFileSystemRawDirectoryContracts(),
    });
  });

  const requestLegacyDirectory = (explicitNull: boolean) => operation.run(async () => {
    const { StorageAccessFramework } = await import('expo-file-system/legacy');
    const result = explicitNull
      ? await StorageAccessFramework.requestDirectoryPermissionsAsync(null)
      : await StorageAccessFramework.requestDirectoryPermissionsAsync();
    return json(result);
  });

  return (
    <>
      <Panel eyebrow="沙箱" title="演练现代文件对象">
        <Note>测试只会在应用缓存目录下写入，并在输出结果后删除该目录。</Note>
        <ActionButton
          disabled={operation.state.phase === 'running'}
          label="执行 创建 · 复制 · 移动 · 句柄"
          onPress={() => void runSandbox()}
        />
        <ActionButton
          disabled={operation.state.phase === 'running'}
          label="验证 连续读取 · Seek · EOF · 资源目录"
          onPress={() => void runReadContracts()}
          tone="secondary"
        />
      </Panel>

      <Panel eyebrow="系统选择器" title="检查持久化授权">
        <ActionRow>
          <ActionButton disabled={operation.state.phase === 'running'} label="选择文件" onPress={() => void pickFile()} />
          <ActionButton disabled={operation.state.phase === 'running'} label="选择目录" onPress={() => void pickDirectory()} tone="secondary" />
        </ActionRow>
        <ActionRow>
          <ActionButton disabled={operation.state.phase === 'running'} label="Legacy 目录授权（无参）" onPress={() => void requestLegacyDirectory(false)} tone="secondary" />
          <ActionButton disabled={operation.state.phase === 'running'} label="Legacy 目录授权（null）" onPress={() => void requestLegacyDirectory(true)} tone="secondary" />
        </ActionRow>
        <Note>
          选中的内容仅作抽样读取，演示不会编辑或删除用户选择的文件和目录。
        </Note>
      </Panel>
      <ResultPanel state={operation.state} />
    </>
  );
}
