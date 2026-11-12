/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { getContentUriAsync } from 'expo-file-system/legacy';
import * as SMS from 'expo-sms';
import { useState } from 'react';
import { Platform } from 'react-native';

import sample from '../../assets/image/sample.png';
import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function SMSDemo() {
  const [addresses, setAddresses] = useState('');
  const [message, setMessage] = useState('你好，周末见。');
  const [attachmentURI, setAttachmentURI] = useState('');
  const [mimeType, setMimeType] = useState('image/png');
  const [filename, setFilename] = useState('photo.png');
  const status = useAsyncResult();
  const composer = useAsyncResult();
  const busy = composer.state.phase === 'running';
  const recipients = addresses.split(',').map(value => value.trim()).filter(Boolean);
  const supportsAttachments = Platform.OS === 'ios' || Platform.OS === 'android';
  const attachment = attachmentURI.trim() ? { uri: attachmentURI.trim(), mimeType, filename } : undefined;

  const open = (recipients: string | string[], attachments?: SMS.SMSOptions['attachments']) => composer.run(async () => (
    json(await SMS.sendSMSAsync(recipients, message, attachments === undefined ? undefined : { attachments }))
  ));

  const prepareSample = () => composer.run(async () => {
    const asset = Asset.fromModule(sample);
    await asset.downloadAsync();
    if (!asset.localUri) throw new Error('无法读取示例图片');

    const uri = Platform.OS === 'android' ? await getContentUriAsync(asset.localUri) : asset.localUri;
    setAttachmentURI(uri);
    setMimeType('image/png');
    setFilename('photo.png');
    return '已添加示例图片';
  });

  return (
    <>
      <Panel title="短信功能">
        <ActionButton disabled={status.state.phase === 'running'} label="查询短信功能是否可用" onPress={() => void status.run(async () => String(await SMS.isAvailableAsync()))} testID="sms-available" />
        <ResultPanel state={status.state} />
      </Panel>

      <Panel title="撰写短信">
        <Field label="收件人（多个用逗号分隔）" onChangeText={setAddresses} placeholder="+12025550123" testID="sms-addresses" value={addresses} />
        <Field label="正文" multiline onChangeText={setMessage} testID="sms-message" value={message} />
        <ActionRow>
          <ActionButton disabled={busy} label="打开短信编辑页" onPress={() => void open(recipients)} testID="sms-open" />
          <ActionButton disabled={busy || recipients.length !== 1} label="以单个号码打开" onPress={() => void open(recipients[0] ?? '')} testID="sms-open-single" tone="secondary" />
        </ActionRow>
        {supportsAttachments
          ? (
              <>
                <ActionButton disabled={busy} label="使用示例图片" onPress={() => void prepareSample()} tone="secondary" />
                <Field label="附件 URI" onChangeText={setAttachmentURI} value={attachmentURI} />
                <Field label="附件 MIME 类型" onChangeText={setMimeType} value={mimeType} />
                <Field label="附件文件名" onChangeText={setFilename} value={filename} />
                <ActionRow>
                  <ActionButton disabled={busy || !attachment} label="打开带附件的短信" onPress={() => void open(recipients, attachment)} />
                  <ActionButton
                    disabled={busy || !attachment}
                    label="以附件数组打开"
                    onPress={() => {
                      if (attachment) void open(recipients, [attachment]);
                    }}
                    tone="secondary"
                  />
                </ActionRow>
              </>
            )
          : null}
        <ResultPanel state={composer.state} />
      </Panel>
    </>
  );
}
