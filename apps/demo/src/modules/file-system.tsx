/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Directory, File, Paths } from 'expo-file-system';
import * as Legacy from 'expo-file-system/legacy';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, Field, Panel } from '../ui';
import { FileSystemDirectoryDemo } from './file-system/directory';
import { FileSystemFileDemo } from './file-system/file';
import { FileSystemLegacyDemo } from './file-system/legacy';
import { FileSystemTransfersDemo } from './file-system/transfers';
import { FileActions, Toggle } from './file-system/shared';

const sections = ['文件', '目录和路径', '文件选择', '上传与下载', 'Legacy'] as const;
type Section = typeof sections[number];

export function FileSystemDemo() {
  const [section, setSection] = useState<Section>('文件');
  return (
    <>
      <Panel>
        <ActionRow>
          {sections.map(value => (
            <ActionButton key={value} label={value} onPress={() => setSection(value)} tone={section === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
      </Panel>
      {section === '文件' ? <FileSystemFileDemo /> : null}
      {section === '目录和路径' ? <FileSystemDirectoryDemo /> : null}
      {section === '文件选择' ? <Pickers /> : null}
      {section === '上传与下载' ? <FileSystemTransfersDemo /> : null}
      {section === 'Legacy' ? <FileSystemLegacyDemo /> : null}
    </>
  );
}

function Pickers() {
  const [initialUri, setInitialUri] = useState('');
  const [mimeTypes, setMimeTypes] = useState('*/*');
  const [multiple, setMultiple] = useState(false);
  const [nullInitial, setNullInitial] = useState(false);
  const platform = String(Platform.OS);
  const legacyDirectoryPicker = platform === 'harmony' || platform === 'android';
  const modernPicker = platform === 'harmony' || platform === 'android' || platform === 'ios';
  const types = mimeTypes.split(',').map(value => value.trim()).filter(Boolean);
  const options = { initialUri: initialUri || undefined, mimeTypes: types.length > 1 ? types : types[0] };
  const fileInfo = (file: File) => ({ uri: file.uri, type: file.type, size: file.size, exists: file.exists });

  return (
    <>
      <Panel title="选择起始位置">
        <Field label="起始目录 URI" onChangeText={setInitialUri} value={initialUri} />
        <ActionButton label="使用文档目录" onPress={() => setInitialUri(Paths.document.uri)} tone="secondary" />
      </Panel>
      <Panel title="选择文件">
        <Field label="MIME 类型，多个值用逗号分隔" onChangeText={setMimeTypes} value={mimeTypes} />
        <Toggle label="multipleFiles" value={multiple} onChange={setMultiple} />
        <FileActions
          disabled={!modernPicker}
          actions={[
            ['pickFileAsync()', async () => {
              const selection = multiple
                ? await File.pickFileAsync({ ...options, multipleFiles: true })
                : await File.pickFileAsync({ ...options, multipleFiles: false });
              if (selection.canceled) return selection;
              const { result } = selection;
              return { canceled: false, result: Array.isArray(result) ? result.map(fileInfo) : fileInfo(result) };
            }],
            ['pickFileAsync(initialUri, mimeType)', async () => {
              const result = await File.pickFileAsync(initialUri || undefined, types[0]);
              return Array.isArray(result) ? result.map(fileInfo) : fileInfo(result);
            }],
          ]}
        />
      </Panel>
      <Panel title="选择目录">
        <Toggle label="Legacy 起始地址使用 null" value={nullInitial} onChange={setNullInitial} />
        <FileActions actions={[
          ['pickDirectoryAsync()', async () => (await Directory.pickDirectoryAsync(initialUri || undefined)).info(), !modernPicker],
          ['requestDirectoryPermissionsAsync()', () => Legacy.StorageAccessFramework.requestDirectoryPermissionsAsync(
            nullInitial ? null : initialUri || undefined
          ), !legacyDirectoryPicker],
        ]}
        />
      </Panel>
    </>
  );
}
