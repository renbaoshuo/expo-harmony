/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import type { Contact, ContactDate } from 'expo-contacts';
import { useState } from 'react';

import photo from '../../../assets/live-photo/photo.jpg';
import { json } from '../../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../../ui';

type ContactFieldProps = {
  canRead: boolean;
  canWrite: boolean;
  contact: () => Contact;
  busy: boolean;
  runField: (operation: () => Promise<unknown>) => Promise<void>;
};

function useFieldResult(runField: ContactFieldProps['runField']) {
  const result = useAsyncResult();
  return { ...result, run: (operation: () => Promise<string> | string) => runField(() => result.run(operation)) };
}

const textFields = [
  { label: '名', method: 'GivenName' },
  { label: '中间名', method: 'MiddleName' },
  { label: '姓', method: 'FamilyName' },
  { label: '昵称', method: 'Nickname' },
  { label: '称谓', method: 'Prefix' },
  { label: '姓名后缀', method: 'Suffix' },
  { label: '名的拼音', method: 'PhoneticGivenName' },
  { label: '中间名的拼音', method: 'PhoneticMiddleName' },
  { label: '姓的拼音', method: 'PhoneticFamilyName' },
  { label: '公司', method: 'Company' },
  { label: '职位', method: 'JobTitle' },
  { label: '备注', method: 'Note' },
] as const;

const listFields = [
  { label: '邮箱', getter: 'getEmails', entry: 'Email', sample: { label: 'work', address: 'hello@example.com' } },
  { label: '电话', getter: 'getPhones', entry: 'Phone', sample: { label: 'mobile', number: '+12025550100' } },
  { label: '纪念日', getter: 'getDates', entry: 'Date', sample: { label: 'anniversary', date: { year: 2020, month: 8, day: 9 } } },
  { label: '地址', getter: 'getAddresses', entry: 'Address', sample: { label: 'work', street: '1 Main Street', city: 'San Francisco', region: 'CA', postcode: '94105', country: 'USA' } },
  { label: '关系', getter: 'getRelations', entry: 'Relation', sample: { label: 'friend', name: 'Alex' } },
  { label: '网址', getter: 'getUrlAddresses', entry: 'UrlAddress', sample: { label: 'other', url: 'https://example.com' } },
  { label: '即时通讯', getter: 'getImAddresses', entry: 'ImAddress', sample: { label: 'other', username: 'alex', service: 'Skype' } },
] as const;

export function ContactTextFields({ busy, canRead, canWrite, contact, runField }: ContactFieldProps) {
  const [field, setField] = useState<(typeof textFields)[number]>(textFields[0]);
  const [value, setValue] = useState('');
  const [clearValue, setClearValue] = useState(false);
  const result = useFieldResult(runField);

  return (
    <Panel title="姓名与资料">
      <ActionRow>
        {textFields.map(item => (
          <ActionButton
            key={item.method}
            disabled={busy}
            label={item.label}
            tone={field === item ? 'primary' : 'secondary'}
            onPress={() => {
              setField(item);
              setValue('');
              setClearValue(false);
              result.clear();
            }}
          />
        ))}
      </ActionRow>
      <Field label={field.label} value={value} editable={!clearValue} onChangeText={setValue} />
      <ActionRow>
        <ActionButton disabled={busy} label="写入空值" tone={clearValue ? 'primary' : 'secondary'} onPress={() => setClearValue(current => !current)} />
        <ActionButton
          disabled={busy || !canRead}
          label="读取字段"
          tone="secondary"
          onPress={() => void result.run(async () => {
            const current = await contact()[`get${field.method}`]();
            setValue(current ?? '');
            return json(current);
          })}
        />
        <ActionButton disabled={busy || !canWrite} label="写入字段" onPress={() => void result.run(async () => json(await contact()[`set${field.method}`](clearValue ? null : value)))} />
        <ActionButton disabled={busy || !canRead} label="读取完整姓名" tone="secondary" onPress={() => void result.run(async () => json(await contact().getFullName()))} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

export function ContactDateAndImage({ busy, canRead, canWrite, contact, runField }: ContactFieldProps) {
  const [birthday, setBirthday] = useState('{"year":2000,"month":2,"day":29}');
  const [image, setImage] = useState('');
  const result = useFieldResult(runField);
  const run = (operation: () => Promise<unknown>) => () => void result.run(async () => json(await operation()));

  return (
    <Panel title="生日与头像">
      <Field label="生日（JSON）" value={birthday} onChangeText={setBirthday} />
      <ActionRow>
        <ActionButton disabled={busy || !canRead} label="读取生日" tone="secondary" onPress={run(() => contact().getBirthday())} />
        <ActionButton disabled={busy || !canWrite} label="设置生日" onPress={run(() => contact().setBirthday(JSON.parse(birthday) as ContactDate | null))} />
        <ActionButton disabled={busy || !canWrite} label="清除生日" tone="secondary" onPress={run(() => contact().setBirthday(null))} />
      </ActionRow>
      <Field label="头像 URI" value={image} onChangeText={setImage} />
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="使用示例图片"
          tone="secondary"
          onPress={run(async () => {
            const asset = Asset.fromModule(photo);
            await asset.downloadAsync();
            const uri = asset.localUri ?? asset.uri;
            setImage(uri);
            return uri;
          })}
        />
        <ActionButton disabled={busy || !canRead} label="读取头像" tone="secondary" onPress={run(() => contact().getImage())} />
        <ActionButton disabled={busy || !canRead} label="读取缩略图" tone="secondary" onPress={run(() => contact().getThumbnail())} />
        <ActionButton disabled={busy || !canWrite || !image.trim()} label="设置头像" onPress={run(() => contact().setImage(image.trim()))} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

export function ContactListFields({ busy, canRead, canWrite, contact, runField }: ContactFieldProps) {
  const [field, setField] = useState<(typeof listFields)[number]>(listFields[0]);
  const [value, setValue] = useState(() => json(listFields[0].sample));
  const [entryId, setEntryId] = useState('');
  const result = useFieldResult(runField);

  return (
    <Panel title="联系人条目">
      <ActionRow>
        {listFields.map(item => (
          <ActionButton
            key={item.entry}
            disabled={busy}
            label={item.label}
            tone={field === item ? 'primary' : 'secondary'}
            onPress={() => {
              setField(item);
              setValue(json(item.sample));
              setEntryId('');
              result.clear();
            }}
          />
        ))}
      </ActionRow>
      <Field label={`${field.label}条目（JSON）`} multiline value={value} onChangeText={setValue} />
      <ActionRow>
        <ActionButton disabled={busy || !canRead} label="读取条目" tone="secondary" onPress={() => void result.run(async () => json(await contact()[field.getter]()))} />
        <ActionButton
          disabled={busy || !canWrite}
          label="新增条目"
          onPress={() => void result.run(async () => {
            const id = await contact()[`add${field.entry}`](JSON.parse(value));
            setEntryId(id);
            return json(id);
          })}
        />
      </ActionRow>
      <Field label="条目 ID" value={entryId} onChangeText={setEntryId} />
      <ActionRow>
        <ActionButton
          disabled={busy || !canWrite || !entryId}
          label="更新条目"
          tone="secondary"
          onPress={() => void result.run(async () => {
            await contact()[`update${field.entry}`]({ ...JSON.parse(value), id: entryId });
            setEntryId('');
            return '已更新条目';
          })}
        />
        <ActionButton
          disabled={busy || !canWrite || !entryId}
          label="删除条目"
          tone="danger"
          onPress={() => void result.run(async () => {
            await contact()[`delete${field.entry}`]({ ...JSON.parse(value), id: entryId });
            setEntryId('');
            return '已删除条目';
          })}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}
