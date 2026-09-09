# @expo-harmony/expo-contacts

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-contacts) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/contacts/)

为 HarmonyOS 上的 React Native 应用提供 Expo Contacts 的原生实现，与官方同版本的 `expo-contacts` 配套使用。支持联系人权限、查询、增删改查、系统选择器、新建表单、vCard 导出与分享，以及已有群组和容器的查询。

## 安装

```bash
npm install @expo-harmony/expo-contacts expo-contacts@55.0.14
```

鸿蒙适配会通过 Autolinking 自动接入，使用默认权限说明时无需额外配置。最低支持 HarmonyOS 5.0.1（API 13），宿主的 `compatibleSdkVersion` 也需满足此要求。

HAR 已经声明通讯录读写权限并配置好用途说明（也可以参照下方的配置插件自定义文本），`usedScene` 默认指向 `EntryAbility`；宿主入口 Ability 如果叫别的名字，需要在 `module.json5` 里改成自己的名称。读取联系人和查询群组、容器需要读权限，新增、修改、删除以及群组成员变更需要读写权限。系统选择器和新建表单不申请整个通讯录的读取权限。

业务代码依旧使用官方包：

```ts
import * as Contacts from 'expo-contacts';

const permission = await Contacts.requestPermissionsAsync();
if (permission.granted) {
  const result = await Contacts.getContactsAsync({
    fields: [Contacts.Fields.PhoneNumbers, Contacts.Fields.Emails],
    pageSize: 20,
  });
  console.log(result.data);
}
```

## Config Plugin

`readContactsPermission`、`writeContactsPermission` 和 `contactsPermission` 是 HarmonyOS 的构建期配置扩展，需要自定义读写权限的用途说明时，在应用配置中添加：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-contacts",
        {
          "readContactsPermission": "用于查找您选择的联系人",
          "writeContactsPermission": "用于保存您编辑的联系人"
        }
      ]
    ]
  }
}
```

`contactsPermission` 可以一次设置读写的用途说明，`readContactsPermission` 和 `writeContactsPermission` 分别优先于它。选项只接受非空字符串，不支持用 `false` 关闭权限。未配置时沿用默认文案「用于读取和选择您的联系人信息」和「用于添加、更新和删除您的联系人」。修改配置后需要重新 prebuild 并构建应用。

## API 对照表

### Component

> **未实现的内容**
>
> - `ContactAccessButton`：只在 iOS 上提供的系统控件，HarmonyOS 上没有对应实现，渲染结果为空，`ContactAccessButton.isAvailable()` 返回 `false`。

### Constants

#### `Contacts.onContactsChangeEventName`

类型：`'onContactsChange'`，联系人变化事件的名称。

### Methods

#### `Contacts.isAvailableAsync()`

返回 `Promise<boolean>`，设备是否具备通讯录数据能力。不检查权限，与官方语义一致。返回 `false` 时，读写联系人、查询群组和容器、导出 vCard 这些接口都没有注册，调用会抛出 `UnavailabilityError`。

#### `Contacts.hasContactsAsync()`

返回 `Promise<boolean>`，设备上是否存在联系人。需要读权限。API 22 起直接查询数量，更低版本要先读出联系人再判断，通讯录较大时更慢。

#### `Contacts.shareContactAsync(contactId, message, shareOptions?)`

返回 `Promise<void>`，把联系人写成 vCard 后打开系统分享界面，界面呈现后 Promise 结束。需要 SystemShare 系统能力和读权限，联系人不存在时拒绝。`message` 作为分享标题，`shareOptions` 在 HarmonyOS 上忽略。

#### `Contacts.getContactsAsync(contactQuery?)`

返回 `Promise<ContactResponse>`。不传条件时返回全部联系人。

查询支持按 `name`（不区分大小写的包含匹配）、`id`（单个或数组）、`groupId`、`containerId` 过滤，按 `sort` 排序，用 `pageSize` 和 `pageOffset` 分页。同时提供多个条件时按 `id`、`name`、`groupId` 的顺序取第一个生效，`containerId` 只在没有这些条件时用于限定账户。`sort` 取 `firstName` 或 `lastName` 时按姓名排序，取 `userDefault` 或 `none` 时保持系统顺序。`rawContacts` 为 `true` 时抛出 `ERR_CONTACTS_UNSUPPORTED`。

`fields` 只控制邮箱、电话、地址、备注、生日、日期、即时通讯、网址、关系和头像这些字段；`id`、`contactType`、`name`、姓名分量、昵称、公司、职位和 `imageAvailable` 始终返回。`fields` 为空数组时仍会返回联系人。

先读出系统联系人，再在本地做投影、筛选、排序和分页，通讯录条目很多时存在扫描开销。

#### `Contacts.getPagedContactsAsync(contactQuery?)`

返回 `Promise<ContactResponse>`，分页查询，行为与 `getContactsAsync()` 相同。`pageSize` 为负数时拒绝。

#### `Contacts.getContactByIdAsync(id, fields?)`

返回 `Promise<ExistingContact | undefined>`，按 ID 查询单个联系人，没有匹配时返回 `undefined`。需要读权限。

#### `Contacts.addContactAsync(contact, containerId?)`

返回 `Promise<string>`，新建联系人并返回其 ID。需要读写权限。

`containerId` 不支持，传入时抛出 `ERR_CONTACTS_UNSUPPORTED`。`contactType` 只接受 `person`，写入 `company` 时拒绝。写入 `department`、`nonGregorianBirthday`、`socialProfiles`、`isFavorite`、`rawImage`、`extraNames` 时抛出 `ERR_CONTACTS_UNSUPPORTED`；`image` 需要 API 22，且只使用 `uri`。

#### `Contacts.updateContactAsync(contact)`

返回 `Promise<string>`，更新已有联系人并返回其 ID。`id` 必填，需要读写权限。

只更新明确提供的字段，未提供的字段保持原值。不支持的字段与 `addContactAsync()` 相同。`name` 是读取结果，写入时忽略，请使用 `firstName`、`lastName` 等姓名分量。

`birthday` 和 `dates` 一起构成联系人的全部日期，更新其中一个会重写整组日期，并以整条联系人写回，可能覆盖其他应用在此期间做的修改。只改其他字段时写入范围限定在提供的字段内。

#### `Contacts.removeContactAsync(contactId)`

返回 `Promise<void>`，删除联系人。官方标记为 iOS 专属，HarmonyOS 上可用。需要读写权限，ID 不存在时不报错。

#### `Contacts.writeContactToFileAsync(contactQuery?)`

返回 `Promise<string | undefined>`，把符合条件的联系人写成 vCard 3.0 文件，返回文件 URI，没有匹配时返回 `undefined`。文件保存在应用缓存目录。需要读权限。

内容包含姓名、昵称、电话、邮箱、地址、公司、职位、备注、生日、网址和可读取的头像，头像以 JPEG 内嵌；不包含群组、即时通讯、关系、其他纪念日以及自定义标签扩展。

#### `Contacts.presentFormAsync(contactId?, contact?, formOptions?)`

返回 `Promise<void>`，打开系统新建联系人表单。需要 API 15 和 Contacts 系统能力，否则抛出 `ERR_CONTACTS_UNSUPPORTED`。

只支持新建，`contactId` 不支持。`contact` 可以预填字段，但 `image` 不能预填。`formOptions` 传入非空对象时抛出 `ERR_CONTACTS_UNSUPPORTED`。用户在系统表单中保存后记录写入通讯录，取消时 Promise 正常结束，不报错。

#### `Contacts.addExistingContactToGroupAsync(contactId, groupId)`

返回 `Promise<void>`，把联系人加入群组。官方标记为 iOS 专属，HarmonyOS 上可用。需要读写权限。联系人和群组必须属于同一个账户，否则抛出 `ERR_CONTACTS_GROUP_CONTAINER_MISMATCH`；已经在群组中时不重复操作。

#### `Contacts.removeContactFromGroupAsync(contactId, groupId)`

返回 `Promise<void>`，把联系人移出群组，不删除联系人。官方标记为 iOS 专属，HarmonyOS 上可用。需要读写权限，约束与 `addExistingContactToGroupAsync()` 相同。

#### `Contacts.getGroupsAsync(groupQuery)`

返回 `Promise<Group[]>`，查询联系人群组。官方标记为 iOS 专属，HarmonyOS 上可用。支持按 `groupId`、`groupName`（精确匹配）、`containerId` 过滤，需要读权限。

#### `Contacts.presentContactPickerAsync()`

返回 `Promise<ExistingContact | null>`，打开系统联系人选择器，返回选中的联系人，取消时返回 `null`。选择结果本身就是授权范围，不需要读取权限。需要 Contacts 系统能力。

API 13 和 14 的选择器按电话号码展示，没有号码的联系人可能无法选择；API 15 起按姓名展示。

#### `Contacts.getContainersAsync(containerQuery)`

返回 `Promise<Container[]>`，查询联系人账户容器。官方标记为 iOS 专属，HarmonyOS 上可用。支持按 `contactId`、`groupId`、`containerId` 过滤，需要读权限。`type` 恒为 `unassigned`。

#### `Contacts.getPermissionsAsync()`

返回 `Promise<ContactsPermissionResponse>`，查询通讯录权限。

`status` 为 `granted`、`denied` 或 `undetermined`，读写权限都授予时 `granted` 为 `true`。`accessPrivileges` 在授予读权限时为 `all`，否则为 `none`，不会出现 `limited`。`expires` 恒为 `never`。

API 20 起系统保留拒绝状态，可以直接据此判断 `denied`；更低版本在用户拒绝后系统仍报告未决定，本模块会记住这次拒绝，`canAskAgain` 因此返回 `false`。

#### `Contacts.requestPermissionsAsync()`

返回 `Promise<ContactsPermissionResponse>`，同时申请读权限和写权限，结果与 `getPermissionsAsync()` 一致。并发调用复用同一次申请，不会重复弹窗。

权限未在 `module.json5` 中声明时抛出 `ERR_CONTACTS_PERMISSION_REQUEST`。系统不再允许申请时，`canAskAgain` 为 `false`，需要引导用户到系统设置中授权。

> **未实现的内容**
>
> - `addExistingGroupToContainerAsync()`、`createGroupAsync()`、`updateGroupNameAsync()`、`removeGroupAsync()`、`getDefaultContainerIdAsync()`：群组的写操作和默认容器查询在 HarmonyOS 上没有对应接口，调用抛出 `UnavailabilityError`。
> - `presentAccessPickerAsync()`：有限的通讯录授权只在 iOS 上提供，调用抛出 `ERR_CONTACTS_UNSUPPORTED`。

### Event Subscriptions

> **未实现的内容**
>
> - `addContactsChangeListener()`：HarmonyOS 没有联系人变化通知接口，添加订阅时抛出 `ERR_CONTACTS_UNSUPPORTED`。

### Types

#### `Contact`

联系人记录。`id`、`contactType`、`name` 始终存在。`name` 优先取系统的完整姓名，没有时由姓名分量拼接，再退回公司名。`firstName`、`middleName`、`lastName`、`namePrefix`、`nameSuffix`、`nickname`、`phoneticFirstName`、`phoneticMiddleName`、`phoneticLastName`、`company`、`jobTitle`、`note`、`birthday`、`dates`、`emails`、`phoneNumbers`、`addresses`、`instantMessageAddresses`、`urlAddresses`、`relationships` 和 `imageAvailable` 可读写。`image` 需要 API 22，读写都只使用 `uri`、`width` 和 `height`。

`contactType` 只支持 `person`。`department`、`nonGregorianBirthday`、`socialProfiles`、`isFavorite`、`rawImage`、`extraNames` 没有数据来源，读取时省略，写入时拒绝；`maidenName` 读取时省略，写入时忽略。

#### `ContactQuery`

`pageSize`、`pageOffset`、`fields`、`sort`、`name`、`id`、`groupId`、`containerId` 在 HarmonyOS 上生效。`rawContacts` 为 `true` 时抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `ContactResponse`

`data` 是查询结果，`hasNextPage` 表示后面还有数据，`hasPreviousPage` 在 `pageOffset` 大于 `0` 时为 `true`。

#### `ContactsPermissionResponse`

`status`、`granted`、`canAskAgain`、`expires`、`accessPrivileges`。`expires` 恒为 `never`，`accessPrivileges` 为 `all` 或 `none`。

#### `FormOptions`

HarmonyOS 上不支持自定义表单，传入非空对象时抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `GroupQuery`

`groupId`、`groupName`、`containerId` 生效。

#### `ContainerQuery`

`contactId`、`groupId`、`containerId` 生效。

#### `Container`

`id`、`name`、`type`，`type` 恒为 `unassigned`。

#### `Group`

`id` 和 `name`。

#### `Date`

`day`、`month`、`year`、`label` 可读写，`month` 从 `0` 开始。`format` 只支持 `gregorian`，写入其他值时拒绝。`id` 不返回。省略 `year` 表示每年重复的日期。

#### `PhoneNumber`

`number`、`label`、`digits` 返回，`id`、`isPrimary`、`countryCode` 不返回。`digits` 由号码去掉分隔符等格式字符得到。`label` 按系统标签映射为 `home`、`work`、`mobile` 等。

#### `Email`

`email` 和 `label`，`id`、`isPrimary` 不返回。

#### `Address`

`street`、`city`、`country`、`region`、`neighborhood`、`postalCode`、`poBox`、`label` 返回，`id`、`isoCountryCode` 不返回。

#### `Image`

`uri`、`width`、`height`。`base64` 不返回，需要图片内容时自行读取 URI。

#### `Relationship`

`label` 和 `name`，`id` 不返回。

#### `InstantMessageAddress`

`service`、`username`、`label` 返回，`id`、`localizedService` 不返回。`service` 是 IM 服务名，`label` 固定为 `other`；写入时 `label` 用于映射系统标签。

#### `UrlAddress`

`url` 和 `label`，`id` 不返回。`label` 固定为 `url`。

#### `ExistingContact`

`Contact` 加上必有的 `id`。

#### `ContactSort`

取值来自 `SortTypes`。

#### `FieldType`

取值来自 `Fields`。

#### `ContactType`

取值来自 `ContactTypes`，HarmonyOS 上只会是 `person`。

#### `ContainerType`

取值来自 `ContainerTypes`，HarmonyOS 上只会是 `unassigned`。

#### `CalendarFormatType`

取值来自 `CalendarFormats`，HarmonyOS 上只会是 `gregorian`。

#### `PermissionResponse`

`status`、`granted`、`canAskAgain`、`expires`，与系统权限模型一致。

#### `PermissionExpiration`

`'never' | number`，HarmonyOS 上恒为 `never`。

> **未实现的内容**
>
> - `SocialProfile`：社交账号信息在 HarmonyOS 上没有数据来源。

### Interfaces

> **未实现的内容**
>
> - `ContactAccessButtonProps`：只在 `ContactAccessButton` 上使用，该组件在 HarmonyOS 上不可用。

### Enums

#### `ContactTypes`

| 成员      | 值          |
| --------- | ----------- |
| `Person`  | `'person'`  |
| `Company` | `'company'` |

HarmonyOS 只支持 `person`，写入 `company` 时拒绝。

#### `SortTypes`

| 成员          | 值              |
| ------------- | --------------- |
| `UserDefault` | `'userDefault'` |
| `FirstName`   | `'firstName'`   |
| `LastName`    | `'lastName'`    |
| `None`        | `'none'`        |

`UserDefault` 和 `None` 在 HarmonyOS 上都保持系统顺序。

#### `CalendarFormats`

| 成员        | 值            |
| ----------- | ------------- |
| `Gregorian` | `'gregorian'` |

其他日历格式只在 iOS 上使用，HarmonyOS 上写入时拒绝。

#### `ContainerTypes`

| 成员         | 值             |
| ------------ | -------------- |
| `Local`      | `'local'`      |
| `Exchange`   | `'exchange'`   |
| `CardDAV`    | `'cardDAV'`    |
| `Unassigned` | `'unassigned'` |

查询容器时只返回 `Unassigned`。

#### `Fields`

| 成员                      | 值                          |
| ------------------------- | --------------------------- |
| `ID`                      | `'id'`                      |
| `ContactType`             | `'contactType'`             |
| `Name`                    | `'name'`                    |
| `FirstName`               | `'firstName'`               |
| `MiddleName`              | `'middleName'`              |
| `LastName`                | `'lastName'`                |
| `NamePrefix`              | `'namePrefix'`              |
| `NameSuffix`              | `'nameSuffix'`              |
| `Nickname`                | `'nickname'`                |
| `PhoneticFirstName`       | `'phoneticFirstName'`       |
| `PhoneticMiddleName`      | `'phoneticMiddleName'`      |
| `PhoneticLastName`        | `'phoneticLastName'`        |
| `Birthday`                | `'birthday'`                |
| `Dates`                   | `'dates'`                   |
| `Emails`                  | `'emails'`                  |
| `PhoneNumbers`            | `'phoneNumbers'`            |
| `Addresses`               | `'addresses'`               |
| `InstantMessageAddresses` | `'instantMessageAddresses'` |
| `UrlAddresses`            | `'urlAddresses'`            |
| `Company`                 | `'company'`                 |
| `JobTitle`                | `'jobTitle'`                |
| `ImageAvailable`          | `'imageAvailable'`          |
| `Image`                   | `'image'`                   |
| `Note`                    | `'note'`                    |
| `Relationships`           | `'relationships'`           |

> **未实现的内容**
>
> - `MaidenName`、`NonGregorianBirthday`、`SocialProfiles`、`Department`、`RawImage`、`ExtraNames`、`IsFavorite`：HarmonyOS 上没有对应的联系人字段。

#### `PermissionStatus`

| 成员           | 值               |
| -------------- | ---------------- |
| `DENIED`       | `'denied'`       |
| `GRANTED`      | `'granted'`      |
| `UNDETERMINED` | `'undetermined'` |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
