import * as Contacts from 'expo-contacts';
import { File } from 'expo-file-system';
import { useState } from 'react';

import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from '../ui';

function fixture(): Contacts.Contact {
  return {
    name: '',
    contactType: Contacts.ContactTypes.Person,
    firstName: `Expo ${Date.now()}`,
    lastName: 'Contacts',
    company: 'Expo Harmony',
    note: '联系人读写测试；仅删除本页面创建的记录。',
    phoneNumbers: [{ label: 'mobile', number: '2025550100' }],
    emails: [{ label: 'work', email: 'contacts@example.com' }],
    birthday: { year: 2000, month: 1, day: 29 },
    dates: [{ label: 'anniversary', year: 2020, month: 8, day: 9 }],
  };
}

export function ContactsDemo() {
  const [permission, setPermission] = useState<Contacts.ContactsPermissionResponse>();
  const [available, setAvailable] = useState<boolean>();
  const [id, setId] = useState<string>();
  const [name, setName] = useState('');
  const access = useAsyncResult();
  const query = useAsyncResult();
  const changes = useAsyncResult();
  const system = useAsyncResult();
  const busy = [access, query, changes, system].some(action => action.state.phase === 'running');
  const readable = permission?.accessPrivileges === 'all' || permission?.granted;

  const inspect = () => access.run(async () => {
    const [supported, current] = await Promise.all([Contacts.isAvailableAsync(), Contacts.getPermissionsAsync()]);
    setAvailable(supported);
    setPermission(current);

    return JSON.stringify({ available: supported, permission: current }, null, 2);
  });

  const create = async () => {
    const value = await Contacts.addContactAsync(fixture());
    setId(value);

    return value;
  };

  const update = async (value: string) => {
    const before = await Contacts.getContactByIdAsync(value);
    if (!before) throw new Error('新建的测试联系人无法按 ID 查询。');

    const firstName = `${before.firstName} Updated`;
    await Contacts.updateContactAsync({ ...before, firstName, phoneNumbers: [], dates: [] });

    const after = await Contacts.getContactByIdAsync(value);
    if (after?.firstName !== firstName || after.name === before.name) {
      throw new Error('修改姓名后，返回值仍包含旧姓名。');
    }
    if (after.phoneNumbers?.length || after.dates?.length) throw new Error('电话号码或纪念日数组未清空。');
    if (after.emails?.[0]?.email !== before.emails?.[0]?.email || after.note !== before.note) {
      throw new Error('更新操作丢失了未修改的邮箱或备注。');
    }
    if (after.birthday?.year !== 2000 || after.birthday.month !== 1 || after.birthday.day !== 29) {
      throw new Error('更新日期数组时没有保留生日。');
    }

    return after;
  };

  const remove = async (value: string) => {
    await Contacts.removeContactAsync(value);
    setId(undefined);

    if (await Contacts.getContactByIdAsync(value)) throw new Error('删除后仍能查询到测试联系人。');

    return '测试联系人已删除，按 ID 查询返回 undefined。';
  };

  const exportFile = async (value: string) => {
    const uri = await Contacts.writeContactToFileAsync({ id: value });
    if (!uri) throw new Error('未生成 vCard 文件。');

    const file = new File(uri);
    try {
      const text = await file.text();
      if (!text.startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n') || !text.endsWith('END:VCARD\r\n')) {
        throw new Error('导出文件不是完整的 vCard 3.0。');
      }
      if (!text.includes('contacts@example.com') || !text.includes('BDAY:20000229')) {
        throw new Error('vCard 未包含测试联系人的邮箱或生日。');
      }

      return { uri, bytes: file.size, text };
    } finally {
      file.delete();
    }
  };

  const verify = () => changes.run(async () => {
    const value = await create();
    let result: object;
    try {
      const before = await Contacts.getContactByIdAsync(value);
      if (!before?.firstName) throw new Error('新建联系人没有返回姓名。');

      const [exists, found, page, empty] = await Promise.all([
        Contacts.hasContactsAsync(),
        Contacts.getContactsAsync({ name: before.firstName, fields: [] }),
        Contacts.getPagedContactsAsync({ id: [value], pageSize: 1, fields: [Contacts.Fields.Emails] }),
        Contacts.getContactsAsync({ id: value, pageSize: 1, pageOffset: 1 }),
      ]);
      if (!exists || !found.data.some(entry => entry.id === value)) throw new Error('存在性或姓名搜索结果不正确。');
      const first = page.data[0];
      if (!first || page.data.length !== 1 || first.id !== value || page.hasNextPage || page.hasPreviousPage) {
        throw new Error('首页数据或分页标志不正确。');
      }
      if (first.phoneNumbers || first.emails?.[0]?.email !== 'contacts@example.com') {
        throw new Error('字段投影没有保留邮箱或错误返回了电话号码。');
      }
      if (empty.data.length || empty.hasNextPage || !empty.hasPreviousPage) throw new Error('末页之后的分页结果不正确。');

      const after = await update(value);
      const file = await exportFile(value);
      result = { id: value, name: after.name, vCardBytes: file.bytes };
    } finally {
      await remove(value);
    }

    return JSON.stringify({ passed: true, checks: ['新增', '按 ID 查询', '姓名搜索', '存在性', '字段与分页', '姓名更新', '数组清空', '生日保留', 'vCard 内容', '删除与清理'], result }, null, 2);
  });

  return (
    <>
      <Panel eyebrow="权限与可用性" title="访问系统通讯录">
        <DataRow label="原生能力" value={available === undefined ? '尚未检查' : available ? '可用' : '不可用'} />
        <DataRow label="权限状态" value={permission?.status ?? '尚未检查'} />
        <DataRow label="读取范围" value={permission?.accessPrivileges ?? '尚未读取'} />
        <DataRow label="可再次询问" value={permission ? String(permission.canAskAgain) : '尚未检查'} />
        <ActionRow>
          <ActionButton disabled={busy} label="检查权限与能力" onPress={() => void inspect()} testID="contacts-inspect" />
          <ActionButton
            disabled={busy}
            label="请求读写权限"
            onPress={() => void access.run(async () => {
              const current = await Contacts.requestPermissionsAsync();
              setPermission(current);
              return JSON.stringify(current, null, 2);
            })}
            testID="contacts-permission"
            tone="secondary"
          />
        </ActionRow>
        <ResultPanel state={access.state} />
      </Panel>

      <Panel eyebrow="读写校验" title="临时联系人的完整生命周期">
        <Note>只修改和删除本页面创建的测试联系人。一键校验会自动清理记录和导出文件；手动新建后，请使用删除按钮清理。</Note>
        <DataRow label="测试联系人 ID" value={id ?? '尚未创建'} />
        <ActionButton disabled={busy || !permission?.granted || !!id} label="一键读写校验" onPress={() => void verify()} testID="contacts-verify" />
        <ActionRow>
          <ActionButton disabled={busy || !permission?.granted || !!id} label="创建测试联系人" onPress={() => void changes.run(create)} testID="contacts-create" tone="secondary" />
          <ActionButton disabled={busy || !permission?.granted || !id} label="更新并校验" onPress={() => void changes.run(async () => JSON.stringify(await update(id!), null, 2))} testID="contacts-update" tone="secondary" />
          <ActionButton disabled={busy || !permission?.granted || !id} label="删除并校验" onPress={() => void changes.run(() => remove(id!))} testID="contacts-remove" tone="danger" />
        </ActionRow>
        <ResultPanel state={changes.state} />
      </Panel>

      <Panel eyebrow="查询" title="姓名搜索、群组与容器">
        <Field label="姓名（留空读取前 10 条）" onChangeText={setName} value={name} testID="contacts-name" />
        <ActionRow>
          <ActionButton disabled={busy || !readable} label="查询联系人" onPress={() => void query.run(async () => JSON.stringify(await Contacts.getContactsAsync({ name: name || undefined, pageSize: 10, fields: [Contacts.Fields.PhoneNumbers, Contacts.Fields.Emails], sort: Contacts.SortTypes.FirstName }), null, 2))} testID="contacts-query" />
          <ActionButton
            disabled={busy || !readable}
            label="查询群组和容器"
            onPress={() => void query.run(async () => {
              const [groups, containers] = await Promise.all([
                Contacts.getGroupsAsync({}),
                Contacts.getContainersAsync({}),
              ]);
              return JSON.stringify({ groups, containers }, null, 2);
            })}
            testID="contacts-containers"
            tone="secondary"
          />
        </ActionRow>
        <ResultPanel state={query.state} />
      </Panel>

      <Panel eyebrow="系统界面与文件" title="选择、新建、导出与分享">
        <Note>选择器不需要通讯录授权，取消返回 null。新建表单由系统保存记录，需要 API 15；头像需要 API 22。分享按钮只分享本页面的测试联系人。</Note>
        <ActionRow>
          <ActionButton disabled={busy} label="选择联系人" onPress={() => void system.run(async () => JSON.stringify(await Contacts.presentContactPickerAsync(), null, 2))} testID="contacts-picker" />
          <ActionButton
            disabled={busy}
            label="新建联系人表单"
            onPress={() => void system.run(async () => {
              await Contacts.presentFormAsync();
              return '系统表单已关闭。';
            })}
            testID="contacts-form"
            tone="secondary"
          />
          <ActionButton
            disabled={busy}
            label="预填联系人表单"
            onPress={() => void system.run(async () => {
              await Contacts.presentFormAsync(undefined, fixture());
              return '预填表单已关闭。';
            })}
            testID="contacts-form-prefilled"
            tone="secondary"
          />
          <ActionButton disabled={busy || !readable || !id} label="导出并校验 vCard" onPress={() => void system.run(async () => JSON.stringify(await exportFile(id!), null, 2))} testID="contacts-export" tone="secondary" />
          <ActionButton
            disabled={busy || !readable || !id}
            label="分享测试联系人"
            onPress={() => void system.run(async () => {
              await Contacts.shareContactAsync(id!, 'Expo Contacts 测试联系人');
              return '已呈现系统分享界面。';
            })}
            testID="contacts-share"
            tone="secondary"
          />
        </ActionRow>
        <ResultPanel state={system.state} />
      </Panel>
    </>
  );
}
