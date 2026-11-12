/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Directory, File, Paths } from 'expo-file-system';
import * as MailComposer from 'expo-mail-composer';
import { useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

function commaSeparated(value: string): string[] {
  return value.split(',').map(item => item.trim()).filter(Boolean);
}

export function MailComposerDemo() {
  const [recipients, setRecipients] = useState('');
  const [cc, setCc] = useState('');
  const [bcc, setBcc] = useState('');
  const [subject, setSubject] = useState('周末活动安排');
  const [body, setBody] = useState('你好，周六上午九点在公园门口集合。');
  const [html, setHtml] = useState(false);
  const [attachments, setAttachments] = useState('');
  const status = useAsyncResult();
  const composer = useAsyncResult();
  const busy = composer.state.phase === 'running';
  const supportsHtml = Platform.OS === 'ios' || Platform.OS === 'android';

  const prepare = () => composer.run(() => {
    const directory = new Directory(Paths.cache, 'expo-mail-composer-demo');
    directory.create({ idempotent: true, intermediates: true });

    const files = ['活动安排.txt', '物品清单.txt'].map((name) => {
      const file = new File(directory, name);
      file.create({ overwrite: true });
      file.write(name);
      return file.uri;
    });

    setAttachments(files.join(', '));
    return '已添加两份示例附件';
  });

  const open = () => composer.run(async () => json(await MailComposer.composeAsync({
    recipients: commaSeparated(recipients),
    ccRecipients: commaSeparated(cc),
    bccRecipients: commaSeparated(bcc),
    subject,
    body,
    ...(supportsHtml ? { isHtml: html } : {}),
    ...(Platform.OS !== 'web' ? { attachments: commaSeparated(attachments) } : {}),
  })));

  return (
    <>
      <Panel title="邮件客户端">
        <ActionRow>
          <ActionButton disabled={status.state.phase === 'running'} label="查询邮件功能是否可用" onPress={() => void status.run(async () => String(await MailComposer.isAvailableAsync()))} testID="mail-composer-inspect" />
          <ActionButton disabled={status.state.phase === 'running'} label="列出邮件客户端" onPress={() => void status.run(() => json(MailComposer.getClients()))} tone="secondary" />
        </ActionRow>
        <ResultPanel state={status.state} />
      </Panel>

      <Panel title="撰写邮件">
        <Field label="收件人（多个用逗号分隔）" onChangeText={setRecipients} placeholder="recipient@example.com" testID="mail-composer-recipients" value={recipients} />
        <Field label="抄送" onChangeText={setCc} testID="mail-composer-cc" value={cc} />
        <Field label="密送" onChangeText={setBcc} testID="mail-composer-bcc" value={bcc} />
        <Field label="主题" onChangeText={setSubject} testID="mail-composer-subject" value={subject} />
        <Field label="正文" multiline onChangeText={setBody} testID="mail-composer-body" value={body} />
        {supportsHtml ? <DataRow label="HTML 正文" value={<Switch accessibilityLabel="HTML 正文" value={html} onValueChange={setHtml} />} /> : null}
        {Platform.OS !== 'web'
          ? (
              <>
                <Field label="附件 URI（多个用逗号分隔）" multiline onChangeText={setAttachments} value={attachments} />
                <ActionButton disabled={busy} label="添加示例附件" onPress={() => void prepare()} testID="mail-composer-prepare" tone="secondary" />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton disabled={busy} label="打开邮件编辑页" onPress={() => void open()} testID="mail-composer-open" />
          <ActionButton disabled={busy} label="打开空白邮件" onPress={() => void composer.run(async () => json(await MailComposer.composeAsync({})))} testID="mail-composer-empty" tone="secondary" />
        </ActionRow>
        <ResultPanel state={composer.state} />
      </Panel>
    </>
  );
}
