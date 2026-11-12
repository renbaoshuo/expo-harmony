/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Legacy from 'expo-file-system/legacy';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionRow, Field, Panel } from '../../ui';
import { childName, FileActions, localDirectory, localFile, Toggle } from './shared';

const platform = String(Platform.OS);
const SAF = Legacy.StorageAccessFramework;

export function FileSystemLegacyDemo() {
  const [path, setPath] = useState('legacy.txt');
  const [destination, setDestination] = useState('legacy-copy.txt');
  const [directory, setDirectory] = useState('legacy');
  const [text, setText] = useState('你好，文件系统');
  const [position, setPosition] = useState('');
  const [length, setLength] = useState('');
  const [md5, setMD5] = useState(false);
  const [append, setAppend] = useState(false);
  const [base64, setBase64] = useState(false);
  const [idempotent, setIdempotent] = useState(false);
  const [intermediates, setIntermediates] = useState(true);
  const [safName, setSafName] = useState('sample');
  const [safMime, setSafMime] = useState('text/plain');
  const fileUri = () => localFile(path).uri;
  const directoryUri = () => localDirectory(directory).uri;
  const encoding = base64 ? Legacy.EncodingType.Base64 : Legacy.EncodingType.UTF8;

  return (
    <>
      <Panel title="旧版文件 API">
        <Field label="缓存中的相对路径" onChangeText={setPath} value={path} />
        <Field label="写入内容" multiline onChangeText={setText} value={text} />
        <Field label="读取起始字节" keyboardType="number-pad" onChangeText={setPosition} value={position} />
        <Field label="读取字节数" keyboardType="number-pad" onChangeText={setLength} value={length} />
        <ActionRow>
          <Toggle label={base64 ? 'encoding base64' : 'encoding utf8'} value={base64} onChange={setBase64} />
          <Toggle label="append" value={append} onChange={setAppend} />
          <Toggle label="md5" value={md5} onChange={setMD5} />
          <Toggle label="idempotent" value={idempotent} onChange={setIdempotent} />
        </ActionRow>
        <Field label="目标相对路径" onChangeText={setDestination} value={destination} />
        <FileActions actions={[
          ['writeAsStringAsync()', () => Legacy.writeAsStringAsync(fileUri(), text, { encoding, append })],
          ['readAsStringAsync()', () => Legacy.readAsStringAsync(fileUri(), {
            encoding, position: position ? Number(position) : undefined, length: length ? Number(length) : undefined,
          })],
          ['getInfoAsync()', () => Legacy.getInfoAsync(fileUri(), { md5 })],
          ['getContentUriAsync()', () => Legacy.getContentUriAsync(fileUri()), platform !== 'android' && platform !== 'harmony'],
          ['copyAsync()', () => Legacy.copyAsync({ from: fileUri(), to: localFile(destination).uri })],
          ['moveAsync()', async () => {
            await Legacy.moveAsync({ from: fileUri(), to: localFile(destination).uri });
            setPath(destination);
          }],
          ['deleteAsync()', () => Legacy.deleteAsync(fileUri(), { idempotent })],
        ]}
        />
      </Panel>
      <Panel title="旧版目录 API">
        <Field label="缓存中的目录名" onChangeText={setDirectory} value={directory} />
        <Toggle label="intermediates" value={intermediates} onChange={setIntermediates} />
        <FileActions actions={[
          ['makeDirectoryAsync()', () => Legacy.makeDirectoryAsync(directoryUri(), { intermediates })],
          ['readDirectoryAsync()', () => Legacy.readDirectoryAsync(directoryUri())],
          ['documentDirectory', () => Legacy.documentDirectory],
          ['cacheDirectory', () => Legacy.cacheDirectory],
          ['bundleDirectory', () => Legacy.bundleDirectory],
          ['getFreeDiskStorageAsync()', () => Legacy.getFreeDiskStorageAsync()],
          ['getTotalDiskCapacityAsync()', () => Legacy.getTotalDiskCapacityAsync()],
        ]}
        />
      </Panel>
      {platform === 'harmony'
        ? (
            <Panel title="StorageAccessFramework">
              <Field label="子项名称" onChangeText={setSafName} value={safName} />
              <Field label="文件 MIME 类型" onChangeText={setSafMime} value={safMime} />
              <FileActions actions={[
                ['readDirectoryAsync()', () => SAF.readDirectoryAsync(directoryUri())],
                ['makeDirectoryAsync()', () => SAF.makeDirectoryAsync(directoryUri(), childName(safName))],
                ['createFileAsync()', () => SAF.createFileAsync(directoryUri(), childName(safName), safMime)],
              ]}
              />
            </Panel>
          )
        : null}
    </>
  );
}
