/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  Contact,
  ContactField,
  Container,
  Group,
  getPermissionsAsync,
  requestPermissionsAsync,
} from 'expo-contacts';
import * as Legacy from 'expo-contacts/legacy';
import { useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { ContactDateAndImage, ContactListFields, ContactTextFields } from './contacts/fields';

const legacyContact: Legacy.Contact = {
  name: '',
  contactType: Legacy.ContactTypes.Person,
  firstName: 'Alex',
  lastName: 'Expo',
  company: 'Expo Harmony',
  jobTitle: '开发者',
  nickname: 'Alex',
  phoneNumbers: [{ label: 'mobile', number: '+12025550100' }],
  emails: [{ label: 'work', email: 'hello@example.com' }],
  birthday: { year: 2000, month: 1, day: 29 },
};

const legacyFieldsExample: Partial<Legacy.Contact> = {
  middleName: 'Lee',
  namePrefix: 'Mr.',
  nameSuffix: 'Jr.',
  phoneticFirstName: 'Alex',
  phoneticMiddleName: 'Lee',
  phoneticLastName: 'Expo',
  note: '下午方便联系',
  dates: [{ label: 'anniversary', year: 2020, month: 8, day: 9 }],
  addresses: [{ label: 'work', street: '1 Main Street', city: 'San Francisco', region: 'CA', postalCode: '94105', country: 'USA' }],
  relationships: [{ label: 'friend', name: 'Sam' }],
  urlAddresses: [{ label: 'other', url: 'https://example.com' }],
  instantMessageAddresses: [{ label: 'other', service: 'Skype', username: 'alex' }],
};

const objectContact = {
  givenName: 'Alex',
  familyName: 'Expo',
  company: 'Expo Harmony',
  jobTitle: '开发者',
  nickname: 'Alex',
  phones: [{ label: 'mobile', number: '+12025550100' }],
  emails: [{ label: 'work', address: 'hello@example.com' }],
  birthday: { year: 2000, month: 2, day: 29 },
};

const sections = [
  { id: 'query', label: '查询' },
  { id: 'contact', label: '联系人' },
  { id: 'groups', label: '群组与账户' },
  { id: 'system', label: '系统表单' },
] as const;

function queryOptions(value: string) {
  const entries = Object.entries(JSON.parse(value));
  return Object.fromEntries(entries.filter(([, field]) => field !== ''));
}

export function ContactsDemo() {
  const [legacy, setLegacy] = useState(false);
  const [section, setSection] = useState<(typeof sections)[number]['id']>('system');
  const [permission, setPermission] = useState<Legacy.ContactsPermissionResponse>();
  const [selected, setSelected] = useState<Contact | null>(null);
  const [contactId, setContactId] = useState('');
  const [ownedContactId, setOwnedContactId] = useState('');
  const [record, setRecord] = useState(() => json(objectContact));
  const [legacyRecord, setLegacyRecord] = useState(() => json(legacyContact));
  const [patch, setPatch] = useState(() => json({ givenName: 'Alexis' }));
  const [legacyPatch, setLegacyPatch] = useState(() => json({ firstName: 'Alexis' }));
  const [form, setForm] = useState(() => json({ givenName: 'Alex', familyName: 'Expo' }));
  const [legacyForm, setLegacyForm] = useState(() => json({ name: '', contactType: 'person', firstName: 'Alex', lastName: 'Expo' }));
  const [detailsFields, setDetailsFields] = useState(() => json([ContactField.FULL_NAME, ContactField.PHONES]));
  const [legacyFields, setLegacyFields] = useState(() => json([Legacy.Fields.PhoneNumbers, Legacy.Fields.Emails]));
  const [objectQuery, setObjectQuery] = useState(() => json({ limit: 10, offset: 0, sortOrder: 'givenName', name: '' }));
  const [legacyQuery, setLegacyQuery] = useState(() => json({
    id: '',
    name: '',
    groupId: '',
    containerId: '',
    pageSize: 10,
    pageOffset: 0,
    sort: 'firstName',
    fields: ['phoneNumbers', 'emails'],
  }));
  const [groupId, setGroupId] = useState('');
  const [containerId, setContainerId] = useState('');
  const [groupName, setGroupName] = useState('');
  const [shareMessage, setShareMessage] = useState('Expo 联系人');
  const [fieldBusy, setFieldBusy] = useState(false);
  const access = useAsyncResult();
  const result = useAsyncResult();
  const busy = fieldBusy || access.state.phase === 'running' || result.state.phase === 'running';
  const canWrite = !!ownedContactId && contactId === ownedContactId;
  const canRead = !!contactId;
  const platform = String(Platform.OS);
  const showGroups = platform === 'harmony' || platform === 'ios';
  const contact = () => selected?.id === contactId ? selected : new Contact(contactId);
  const group = () => new Group(groupId);
  const container = () => new Container(containerId);
  const run = (operation: () => unknown) => () => void result.run(async () => {
    const value = await operation();
    return value === undefined ? 'undefined' : json(value);
  });
  const runField = async (operation: () => Promise<unknown>) => {
    setFieldBusy(true);
    try {
      await operation();
    } finally {
      setFieldBusy(false);
    }
  };

  const updatePermission = (request: boolean) => access.run(async () => {
    const current = await (legacy
      ? request ? Legacy.requestPermissionsAsync() : Legacy.getPermissionsAsync()
      : request ? requestPermissionsAsync() : getPermissionsAsync());
    setPermission(current);
    return json(current);
  });

  const create = run(async () => {
    if (legacy) {
      const id = await Legacy.addContactAsync(JSON.parse(legacyRecord));
      setOwnedContactId(id);
      setContactId(id);
      return { id };
    }
    const value = await Contact.create(JSON.parse(record));
    setSelected(value);
    setOwnedContactId(value.id);
    setContactId(value.id);
    return { id: value.id };
  });

  const remove = () => void result.run(async () => {
    if (legacy) await Legacy.removeContactAsync(contactId);
    else await contact().delete();
    setOwnedContactId('');
    setContactId('');
    setSelected(null);
    return `已删除联系人 ${contactId}`;
  });
  const fieldProps = { busy, canRead, canWrite, contact, runField };

  return (
    <>
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="对象 API"
          tone={legacy ? 'secondary' : 'primary'}
          onPress={() => {
            setLegacy(false);
            result.clear();
          }}
        />
        <ActionButton
          disabled={busy}
          label="旧版 API"
          tone={legacy ? 'primary' : 'secondary'}
          onPress={() => {
            setLegacy(true);
            result.clear();
          }}
        />
      </ActionRow>

      <Panel title="通讯录权限">
        <DataRow label="权限状态" value={permission?.status ?? '尚未查询'} />
        <ActionRow>
          {legacy ? <ActionButton disabled={busy} label="检查可用性" tone="secondary" onPress={() => void access.run(async () => json(await Legacy.isAvailableAsync()))} /> : null}
          <ActionButton disabled={busy} label="查询权限" tone="secondary" onPress={() => void updatePermission(false)} />
          <ActionButton disabled={busy} label="申请权限" onPress={() => void updatePermission(true)} />
        </ActionRow>
        <ResultPanel state={access.state} />
      </Panel>

      <ActionRow>
        {sections.filter(item => showGroups || item.id !== 'groups').map(item => (
          <ActionButton
            key={item.id}
            disabled={busy}
            label={item.label}
            tone={section === item.id ? 'primary' : 'secondary'}
            onPress={() => {
              setSection(item.id);
              result.clear();
            }}
          />
        ))}
      </ActionRow>

      {section === 'system'
        ? (
            <Panel title="系统联系人表单">
              <ActionButton
                disabled={busy}
                label="打开联系人选择器"
                onPress={run(async () => {
                  if (legacy) {
                    const value = await Legacy.presentContactPickerAsync();
                    if (value) {
                      setContactId(value.id);
                      setSelected(null);
                    }
                    return value;
                  }
                  const value = await Contact.presentPicker();
                  if (value) {
                    setSelected(value);
                    setContactId(value.id);
                  }
                  return value ? { id: value.id } : null;
                })}
              />
              <Field
                label="表单预填资料（JSON）"
                multiline
                value={legacy ? legacyForm : form}
                onChangeText={legacy ? setLegacyForm : setForm}
              />
              <ActionButton
                disabled={busy}
                label="打开新建联系人表单"
                tone="secondary"
                onPress={() => void result.run(async () => {
                  if (legacy) {
                    await Legacy.presentFormAsync(undefined, legacyForm.trim() ? JSON.parse(legacyForm) : undefined);
                    return '表单已关闭';
                  }
                  return json(await Contact.presentCreateForm(form.trim() ? JSON.parse(form) : undefined));
                })}
              />
              <ResultPanel state={result.state} />
            </Panel>
          )
        : null}

      {section === 'query'
        ? (
            <Panel title="查询联系人">
              <Field
                label="查询条件（JSON）"
                multiline
                value={legacy ? legacyQuery : objectQuery}
                onChangeText={legacy ? setLegacyQuery : setObjectQuery}
                placeholder={legacy ? '{"id":[],"name":"","groupId":"","containerId":""}' : '{"limit":10,"offset":0,"sortOrder":"givenName","name":""}'}
              />
              {!legacy ? <Field label="返回字段（JSON 数组）" value={detailsFields} onChangeText={setDetailsFields} /> : null}
              <ActionRow>
                <ActionButton disabled={busy} label="检查是否有联系人" tone="secondary" onPress={run(legacy ? Legacy.hasContactsAsync : () => Contact.hasAny())} />
                {legacy
                  ? (
                      <>
                        <ActionButton disabled={busy} label="查询联系人" onPress={run(() => Legacy.getContactsAsync(queryOptions(legacyQuery)))} />
                        <ActionButton disabled={busy} label="分页查询" tone="secondary" onPress={run(() => Legacy.getPagedContactsAsync(queryOptions(legacyQuery)))} />
                        <ActionButton disabled={busy} label="导出 vCard" tone="secondary" onPress={run(() => Legacy.writeContactToFileAsync(queryOptions(legacyQuery)))} />
                      </>
                    )
                  : (
                      <>
                        <ActionButton disabled={busy} label="统计联系人" tone="secondary" onPress={run(() => Contact.getCount())} />
                        <ActionButton disabled={busy} label="查询联系人 ID" onPress={run(async () => (await Contact.getAll(queryOptions(objectQuery))).map(item => ({ id: item.id })))} />
                        <ActionButton disabled={busy} label="查询联系人详情" tone="secondary" onPress={run(() => Contact.getAllDetails(JSON.parse(detailsFields), queryOptions(objectQuery)))} />
                      </>
                    )}
              </ActionRow>
              <ResultPanel state={result.state} />
            </Panel>
          )
        : null}

      {section === 'contact'
        ? (
            <>
              <Panel title="联系人记录">
                <Field label="联系人 ID" value={contactId} onChangeText={setContactId} editable={!busy} />
                <Field
                  label="返回字段（JSON 数组）"
                  value={legacy ? legacyFields : detailsFields}
                  onChangeText={legacy ? setLegacyFields : setDetailsFields}
                />
                <ActionButton
                  disabled={busy || (legacy ? !contactId : !canRead)}
                  label="读取联系人详情"
                  tone="secondary"
                  onPress={run(() => legacy
                    ? Legacy.getContactByIdAsync(contactId, legacyFields.trim() ? JSON.parse(legacyFields) : undefined)
                    : contact().getDetails(detailsFields.trim() ? JSON.parse(detailsFields) : undefined))}
                />
                <Field
                  label="联系人资料（JSON）"
                  multiline
                  value={legacy ? legacyRecord : record}
                  onChangeText={legacy ? setLegacyRecord : setRecord}
                />
                <ActionRow>
                  {legacy ? <ActionButton disabled={busy} label="填入更多资料字段" tone="secondary" onPress={() => setLegacyRecord(json({ ...legacyContact, ...legacyFieldsExample }))} /> : null}
                  <ActionButton disabled={busy || !!ownedContactId} label="创建演示联系人" onPress={create} />
                  {!legacy
                    ? (
                        <ActionButton
                          disabled={busy || !canWrite}
                          label="替换全部资料"
                          tone="secondary"
                          onPress={() => void result.run(async () => {
                            await contact().update(JSON.parse(record));
                            return '已替换全部资料';
                          })}
                        />
                      )
                    : null}
                </ActionRow>
                <Field
                  label="要修改的字段（JSON）"
                  multiline
                  value={legacy ? legacyPatch : patch}
                  onChangeText={legacy ? setLegacyPatch : setPatch}
                />
                <ActionRow>
                  <ActionButton
                    disabled={busy || !canWrite}
                    label="更新指定字段"
                    tone="secondary"
                    onPress={() => void result.run(async () => {
                      if (legacy) return await Legacy.updateContactAsync({ ...JSON.parse(legacyPatch), id: contactId });
                      await contact().patch(JSON.parse(patch));
                      return '已更新指定字段';
                    })}
                  />
                  <ActionButton disabled={busy || !canWrite} label="删除演示联系人" tone="danger" onPress={remove} />
                </ActionRow>
                {legacy
                  ? (
                      <>
                        <Field label="分享标题" value={shareMessage} onChangeText={setShareMessage} />
                        <ActionButton
                          disabled={busy || !contactId}
                          label="分享联系人"
                          tone="secondary"
                          onPress={() => void result.run(async () => {
                            await Legacy.shareContactAsync(contactId, shareMessage);
                            return '已打开分享界面';
                          })}
                        />
                      </>
                    )
                  : null}
                <ResultPanel state={result.state} />
              </Panel>
              {!legacy
                ? (
                    <>
                      <ContactTextFields {...fieldProps} />
                      <ContactDateAndImage {...fieldProps} />
                      <ContactListFields key={contactId} {...fieldProps} />
                    </>
                  )
                : null}
            </>
          )
        : null}

      {section === 'groups' && showGroups
        ? (
            <Panel title="群组与账户">
              <Field label="群组 ID" value={groupId} onChangeText={setGroupId} />
              {legacy ? <Field label="群组名称" value={groupName} onChangeText={setGroupName} /> : null}
              <Field label="账户 ID" value={containerId} onChangeText={setContainerId} />
              <Field label="联系人 ID" value={contactId} onChangeText={setContactId} />
              <ActionRow>
                <ActionButton
                  disabled={busy}
                  label="查询群组"
                  onPress={run(async () => legacy
                    ? Legacy.getGroupsAsync({
                        groupId: groupId || undefined,
                        groupName: groupName || undefined,
                        containerId: containerId || undefined,
                      })
                    : (await Group.getAll(containerId || undefined)).map(item => ({ id: item.id })))}
                />
                <ActionButton
                  disabled={busy}
                  label="查询账户"
                  tone="secondary"
                  onPress={run(async () => legacy
                    ? Legacy.getContainersAsync({
                        contactId: contactId || undefined,
                        groupId: groupId || undefined,
                        containerId: containerId ? containerId.split(',').map(id => id.trim()).filter(Boolean) : undefined,
                      })
                    : (await Container.getAll()).map(item => ({ id: item.id })))}
                />
              </ActionRow>
              {!legacy
                ? (
                    <>
                      <Field label="群组成员查询条件（JSON）" multiline value={objectQuery} onChangeText={setObjectQuery} />
                      <ActionRow>
                        <ActionButton disabled={busy || !groupId} label="读取群组名称" tone="secondary" onPress={run(() => group().getName())} />
                        <ActionButton disabled={busy || !groupId} label="查询群组成员" tone="secondary" onPress={run(async () => (await group().getContacts(queryOptions(objectQuery))).map(item => ({ id: item.id })))} />
                        <ActionButton disabled={busy || !containerId} label="读取账户名称" tone="secondary" onPress={run(() => container().getName())} />
                        <ActionButton disabled={busy || !containerId} label="读取账户类型" tone="secondary" onPress={run(() => container().getType())} />
                        <ActionButton disabled={busy || !containerId} label="查询账户群组" tone="secondary" onPress={run(async () => (await container().getGroups()).map(item => ({ id: item.id })))} />
                        <ActionButton disabled={busy || !containerId} label="查询账户联系人" tone="secondary" onPress={run(async () => (await container().getContacts()).map(item => ({ id: item.id })))} />
                      </ActionRow>
                    </>
                  )
                : null}
              <ActionRow>
                <ActionButton
                  disabled={busy || !groupId || !canWrite}
                  label="把演示联系人加入群组"
                  onPress={() => void result.run(async () => {
                    if (legacy) await Legacy.addExistingContactToGroupAsync(contactId, groupId);
                    else await group().addContact(contact());
                    return '已加入群组';
                  })}
                />
                <ActionButton
                  disabled={busy || !groupId || !canWrite}
                  label="从群组移出演示联系人"
                  tone="secondary"
                  onPress={() => void result.run(async () => {
                    if (legacy) await Legacy.removeContactFromGroupAsync(contactId, groupId);
                    else await group().removeContact(contact());
                    return '已移出群组';
                  })}
                />
              </ActionRow>
              <ResultPanel state={result.state} />
            </Panel>
          )
        : null}
    </>
  );
}
