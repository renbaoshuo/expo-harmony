# @expo-harmony/expo-contacts

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-contacts) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/contacts/)

为 HarmonyOS 上的 React Native 应用提供 Expo Contacts 的原生实现，与官方同版本的 `expo-contacts` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-contacts expo-contacts
```

## API 对照表

### Hooks

本包没有提供 Hook。

### Constants

#### `onContactsChangeEventName`

字符串常量 `'onContactsChange'`，用于标识 legacy 联系人变化事件。

### Methods

#### `Contacts.isAvailableAsync()`

返回 `Promise<boolean>`。当设备提供 Contacts Data 系统能力时返回 `true`；否则返回 `false`。

#### `Contacts.hasContactsAsync()`

返回 `Promise<boolean>`，查询设备是否有联系人。需要通讯录读权限。

#### `Contacts.getContactsAsync(contactQuery?)`

返回 `Promise<ContactResponse>`。`contactQuery` 支持 `pageSize`、`pageOffset`、`fields`、`sort`、`name`、`id`、`groupId` 和 `containerId`。`pageSize`、`pageOffset` 必须是非负整数；`pageSize` 为 `0` 表示不限制数量。`rawContacts: true` 会抛出 `ERR_CONTACTS_UNSUPPORTED`。

`name` 使用不区分大小写的包含匹配。只提供多个筛选条件时，`id`、`name`、`groupId` 按此顺序生效；`containerId` 在没有这些条件时限定账户。`sort` 支持 `firstName`、`lastName`、`userDefault` 和 `none`；后两者保留系统顺序。查询需要读权限。

`fields` 控制邮箱、电话、地址、备注、生日、日期、即时通讯地址、网址、关系和头像字段。`id`、`contactType`、`name`、姓名分量、昵称、公司、职位和 `imageAvailable` 始终返回。`fields` 为空数组时仍返回这些基础字段。

#### `Contacts.getPagedContactsAsync(contactQuery?)`

返回 `Promise<ContactResponse>`，按 `pageSize` 和 `pageOffset` 分页，其他查询参数与 `getContactsAsync()` 相同。`pageSize` 为负数时拒绝；`0` 表示不限制数量。

#### `Contacts.getContactByIdAsync(id, fields?)`

返回 `Promise<ExistingContact | undefined>`。未找到对应联系人时返回 `undefined`。需要读权限。

#### `Contacts.addContactAsync(contact, containerId?)`

返回 `Promise<string>`，成功时返回新联系人的 ID。需要读写权限。`containerId` 不受支持，传入后抛出 `ERR_CONTACTS_UNSUPPORTED`。`contactType` 只支持 `person`；公司名称请写入 `company`。HarmonyOS SDK API 22 起支持头像，头像只接受 `image.uri`。

写入 `department`、`nonGregorianBirthday`、`socialProfiles`、`isFavorite`、`rawImage` 或 `extraNames` 会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Contacts.updateContactAsync(contact)`

返回 `Promise<string>`，成功时返回联系人 ID。`id` 必填，需要读写权限。只更新传入且值不是 `null` 或 `undefined` 的字段；未传入字段保持原值。`name` 是读取字段，写入时忽略，请使用姓名分量。`birthday` 与 `dates` 共用系统日期数据；更新生日时保留其他日期，更新 `dates` 时保留生日并替换非生日日期。

#### `Contacts.removeContactAsync(contactId)`

返回 `Promise<void>`，删除联系人。需要读写权限；ID 不存在时不报错。

#### `Contacts.writeContactToFileAsync(contactQuery?)`

返回 `Promise<string | undefined>`，将符合条件的联系人导出为 vCard 3.0 文件 URI；没有匹配项时返回 `undefined`。文件保存在应用缓存目录，需要读权限。导出包含姓名、昵称、电话、邮箱、地址、公司、职位、备注、生日、网址和可读取的头像；不包含群组、即时通讯地址、关系、其他日期和自定义标签扩展。

#### `Contacts.shareContactAsync(contactId, message, shareOptions?)`

返回 `Promise<void>`。将联系人导出为 vCard 并打开系统分享界面。需要读权限和 SystemShare 系统能力。联系人不存在时抛出 `ERR_CONTACTS_NOT_FOUND`；`shareOptions` 在 HarmonyOS 上无效。

#### `Contacts.presentFormAsync(contactId?, contact?, formOptions?)`

返回 `Promise<void>`，打开系统新建联系人表单。需要 Contacts 系统能力及 HarmonyOS SDK API 15 或更高版本。仅支持新建：传入 `contactId`、非空 `formOptions` 或头像预填时抛出 `ERR_CONTACTS_UNSUPPORTED`。保存或取消后 Promise 均正常完成。

#### `Contacts.addExistingContactToGroupAsync(contactId, groupId)`

返回 `Promise<void>`，将联系人加入群组。需要读写权限；联系人与群组必须属于同一账户，否则抛出 `ERR_CONTACTS_GROUP_CONTAINER_MISMATCH`。已在群组中的联系人不会重复添加。

#### `Contacts.removeContactFromGroupAsync(contactId, groupId)`

返回 `Promise<void>`，将联系人移出群组，不会删除联系人。需要读写权限；联系人与群组必须属于同一账户。

#### `Contacts.getGroupsAsync(groupQuery?)`

返回 `Promise<Group[]>`。支持按 `groupId`、`groupName`（精确匹配）或 `containerId` 查询，需要读权限。同传多个条件时，`groupName` 优先；没有 `groupName` 时，`containerId` 优先于 `groupId`。

#### `Contacts.presentContactPickerAsync()`

返回 `Promise<ExistingContact | null>`。打开系统单选联系人界面，取消时返回 `null`。选中的联系人可直接读取，无需通讯录读权限；查询或修改其他联系人仍需相应权限。需要 Contacts 系统能力。HarmonyOS SDK API 13 和 14 按电话号码展示联系人；API 15 起按姓名展示。

#### `Contacts.getContainersAsync(containerQuery?)`

返回 `Promise<Container[]>`，查询联系人账户容器。支持按 `contactId`、`groupId` 或 `containerId` 筛选，需要读权限。同传多个条件时，`contactId` 优先于 `groupId`，`groupId` 优先于 `containerId`。legacy 结果的 `type` 为 `unassigned`。

#### `Contacts.addExistingGroupToContainerAsync(groupId, containerId)`

- HarmonyOS Contacts Kit 不提供将群组移动到账户容器的操作；调用会抛出 `UnavailabilityError`。

#### `Contacts.createGroupAsync(name?, containerId?)`

- HarmonyOS Contacts Kit 不提供创建群组的操作；调用会抛出 `UnavailabilityError`。

#### `Contacts.updateGroupNameAsync(groupName, groupId)`

- HarmonyOS Contacts Kit 不提供重命名群组的操作；调用会抛出 `UnavailabilityError`。

#### `Contacts.removeGroupAsync(groupId)`

- HarmonyOS Contacts Kit 不提供删除群组的操作；调用会抛出 `UnavailabilityError`。

#### `Contacts.getDefaultContainerIdAsync()`

- HarmonyOS Contacts Kit 不提供默认容器；调用会抛出 `UnavailabilityError`。

#### `Contacts.presentAccessPickerAsync()`

- HarmonyOS 不提供有限联系人访问选择器；调用会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Contact.getAll(options?)`

返回 `Promise<Contact[]>`。`options` 支持 `limit`、`offset`、`sortOrder`、`name` 和 `rawContacts`。`limit` 为 `0` 时返回空数组；`name` 匹配姓名或拼音姓名；`sortOrder` 支持 `givenName`、`familyName`、`userDefault` 和 `none`，后两者保留系统顺序。`rawContacts: true` 会抛出 `ERR_CONTACTS_UNSUPPORTED`。需要读权限。

#### `Contact.getAllDetails(fields, options?)`

返回 `Promise<PartialContactDetails[]>`，按字段批量查询联系人。筛选和排序选项与 `Contact.getAll()` 相同。请求的 HarmonyOS 不支持字段会从结果中略去；未知字段抛出 `ERR_CONTACTS_INVALID_ARGUMENT`。需要读权限。

#### `Contact.create(contact)`

返回 `Promise<Contact>`，创建联系人并返回对象。需要读写权限；不支持指定容器。字段限制与 `Contacts.addContactAsync()` 相同。

#### `Contact.getCount()` 和 `Contact.hasAny()`

分别返回 `Promise<number>` 和 `Promise<boolean>`，查询联系人数量以及是否存在联系人。均需要读权限。

#### `Contact.presentCreateForm(contact?, options?)`

返回 `Promise<boolean>`。打开系统新建联系人表单；保存时返回 `true`，取消时返回 `false`。需要 Contacts 系统能力及 HarmonyOS SDK API 15 或更高版本。可预填联系人字段，但不能预填头像；非空 `options` 会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Contact.presentPicker()`

返回 `Promise<Contact | null>`。行为和权限要求与 `Contacts.presentContactPickerAsync()` 相同。通过此方法选中的联系人可在未获读权限时读取所选联系人详情。

#### `Contact.presentAccessPicker()`

- HarmonyOS 不提供有限联系人访问选择器；调用会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Contact.getDetails(fields?)`

返回 `Promise<PartialContactDetails>`，读取指定字段；省略 `fields` 时读取 HarmonyOS 支持的全部字段。结果始终包含 `id`。不支持的字段会被略去，未知字段抛出 `ERR_CONTACTS_INVALID_ARGUMENT`。

#### `Contact.patch(contact)`

返回 `Promise<void>`，只修改传入字段；未传入字段不变。传入列表字段时，该列表整体替换。`image` 需要 HarmonyOS SDK API 22 或更高版本；不支持清除已有头像。

#### `Contact.update(contact)`

返回 `Promise<void>`，用传入信息覆盖联系人。省略的字符串和列表字段会清空；生日和其他日期共用日期列表，省略 `dates` 会清空整组日期，传入空列表也会清空。`image` 需要 HarmonyOS SDK API 22 或更高版本；不支持清除已有头像。

#### `Contact.delete()`

返回 `Promise<void>`，删除联系人。需要读写权限。

#### `Contact.editWithForm(options?)`

- HarmonyOS Contacts Kit 不提供编辑指定联系人的系统表单；调用会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Contact.getFullName()`

返回 `Promise<string>`。`Contact.getDetails()` 的 `fullName` 字段也提供同一姓名值。

#### `Contact` 姓名、文本与头像方法

以下读取和写入方法返回的值遵循 HarmonyOS 联系人字段映射：

- `getGivenName()` / `setGivenName(value)`、`getMiddleName()` / `setMiddleName(value)`、`getFamilyName()` / `setFamilyName(value)`
- `getNickname()` / `setNickname(value)`、`getPrefix()` / `setPrefix(value)`、`getSuffix()` / `setSuffix(value)`
- `getPhoneticGivenName()` / `setPhoneticGivenName(value)`、`getPhoneticMiddleName()` / `setPhoneticMiddleName(value)`、`getPhoneticFamilyName()` / `setPhoneticFamilyName(value)`
- `getCompany()` / `setCompany(value)`、`getJobTitle()` / `setJobTitle(value)`、`getNote()` / `setNote(value)`

字符串 getter 返回 `Promise<string | null>`，setter 返回 `Promise<boolean>`。公司名称存入联系人公司字段。

`getImage()`、`getThumbnail()` 返回 `Promise<string | null>`，值为图片 URI；`setImage(uri)` 返回 `Promise<boolean>`。图片读写需要 HarmonyOS SDK API 22 或更高版本，不能清除已有头像；`thumbnail` 只能读取。

#### `Contact.getBirthday()` / `Contact.setBirthday(value)`

读取或设置生日。读取返回 `Promise<ContactDate | null>`，写入返回 `Promise<boolean>`。该 API 的月份从 `1` 开始；日期仅支持 Gregorian 日历，写入其他日历格式或无效日期会拒绝。

#### `Contact` 列表字段方法

以下列表均提供 `getX()`、`addX(value)`、`updateX(value)` 和 `deleteX(value)` 方法。读取返回列表；新增返回列表项 ID；修改和删除返回 `Promise<void>`。

- `getEmails()`、`addEmail()`、`updateEmail()`、`deleteEmail()`：邮箱项使用 `address`、`label`。
- `getPhones()`、`addPhone()`、`updatePhone()`、`deletePhone()`：电话项使用 `number`、`label`。
- `getDates()`、`addDate()`、`updateDate()`、`deleteDate()`：日期项使用 `date`、`label`；日期月份从 `1` 开始。
- `getAddresses()`、`addAddress()`、`updateAddress()`、`deleteAddress()`：支持 `street`、`city`、`region`、`postcode`、`country` 和 `label`；单独的地址 `state` 不支持。
- `getRelations()`、`addRelation()`、`updateRelation()`、`deleteRelation()`：支持 `name`、`label`。
- `getUrlAddresses()`、`addUrlAddress()`、`updateUrlAddress()`、`deleteUrlAddress()`：支持 `url`，返回的 `label` 固定为 `other`。
- `getImAddresses()`、`addImAddress()`、`updateImAddress()`、`deleteImAddress()`：支持 `username`、`service`；返回的 `label` 固定为 `other`。

列表项的 `id` 用于更新和删除；联系人列表发生变化后，旧 ID 可能失效，届时会抛出 `ERR_CONTACTS_STALE_FIELD`。网址和即时通讯条目只支持 `other` 标签。

#### `Contact` 不支持的字段方法

- HarmonyOS 联系人服务不提供收藏状态、曾用名、部门、公司拼音名、非公历生日、额外姓名和社交账号字段。对应的 `get`、`set`、`add`、`update` 或 `delete` 方法会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Group` 方法

`Group.getAll(containerId?)` 返回 `Promise<Group[]>`；`getName()` 返回 `Promise<string | null>`；`getContacts(options?)` 返回群组联系人；`addContact(contact)` 和 `removeContact(contact)` 返回 `Promise<void>`。群组成员变更需要读写权限，联系人和群组必须属于同一账户。

#### `Group.create(name, containerId?)`、`Group.setName(name)` 和 `Group.delete()`

- HarmonyOS Contacts Kit 不提供创建、重命名或删除联系人群组的操作；这些方法会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `Container` 方法

`Container.getAll()` 返回 `Promise<Container[]>`。实例的 `getName()` 返回 `Promise<string | null>`，`getGroups()` 返回 `Promise<Group[]>`，`getContacts(options?)` 返回 `Promise<Contact[]>`；这些查询均需要读权限。`getType()` 返回 `'unknown'`。legacy `getContainersAsync()` 的 `type` 则返回 `'unassigned'`。

#### `Container.getDefault()`

- HarmonyOS Contacts Kit 不提供默认联系人容器；调用会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `ContactAccessButton.isAvailable()`

返回 `false`。HarmonyOS 没有对应的系统控件，渲染 `ContactAccessButton` 时不显示内容。

### Event subscriptions

#### `Contacts.addContactsChangeListener(listener)` 和 `Contacts.removeAllContactsChangeListeners()`

- HarmonyOS Contacts Kit 不提供联系人变化通知；添加监听器会抛出 `ERR_CONTACTS_UNSUPPORTED`。

### Types

#### `Contact` 和 `ExistingContact`

联系人查询结果始终包含 `id`、`contactType` 和 `name`。`contactType` 始终为 `person`；姓名优先使用系统完整姓名，其次由姓名分量组成，再退回公司名。姓名分量、昵称、拼音姓名、公司、职位和 `imageAvailable` 始终可读；`note`、`emails`、`phoneNumbers`、`addresses`、`instantMessageAddresses`、`urlAddresses`、`relationships`、`birthday`、`dates` 和 `image` 按请求字段返回。

`birthday` 与 `dates` 表示同一组联系人日期。legacy `Date.month` 从 `0` 开始，`Date.format` 为 `gregorian`；设置生日或日期只支持 Gregorian 格式。头像使用 `Image.uri`，读写需要 HarmonyOS SDK API 22 或更高版本；图片内容不以内嵌 Base64 返回。

#### `ContactQuery` 和 `ContactResponse`

legacy `ContactQuery` 支持 `pageSize`、`pageOffset`、`fields`、`sort`、`name`、`id`、`groupId`、`containerId` 和 `rawContacts`。`ContactResponse` 包含 `data`、`hasNextPage`、`hasPreviousPage`。

#### `Email`、`PhoneNumber`、`Address`、`Date`、`Image`、`Relationship`、`InstantMessageAddress` 和 `UrlAddress`

- `Email` 返回 `email`、`label`，不返回 `id`、`isPrimary`。
- `PhoneNumber` 返回 `number`、`digits`、`label`，不返回 `id`、`isPrimary`、`countryCode`；`digits` 去除号码分隔符。标签按 HarmonyOS 系统标签映射。
- `Address` 返回 `street`、`city`、`country`、`region`、`neighborhood`、`postalCode`、`poBox`、`label`，不返回 `id`、`isoCountryCode`。`street` 可映射系统的邮政地址文本。
- `Date` 返回 `day`、`month`、`year`、`label`，不返回 `id`；省略 `year` 表示每年重复。legacy 的 `month` 从 `0` 开始。
- `Image` 返回 `uri`、`width`、`height`，不返回 `base64`。
- `Relationship` 返回 `label`、`name`，不返回 `id`。
- `InstantMessageAddress` 返回 `service`、`username`、`label`，不返回 `id`、`localizedService`；写入时 `label` 不保存。
- `UrlAddress` 返回 `url`、`label`，不返回 `id`；`label` 固定为 `url`。

#### `Group`、`GroupQuery`、`Container` 和 `ContainerQuery`

`Group` 查询结果包含 `id`、`name`。`GroupQuery` 支持 `groupId`、`groupName`、`containerId`。`Container` legacy 查询结果包含 `id`、`name`、`type`，其中 `type` 为 `unassigned`；`ContainerQuery` 支持 `contactId`、`groupId`、`containerId`。

#### 其他 legacy 类型

`ContactSort`、`FieldType`、`ContactType`、`ContainerType` 和 `CalendarFormatType` 分别表示联系人排序、字段、联系人类型、账户容器类型和日期格式。`PermissionExpiration` 在 HarmonyOS 上为 `'never'`。`SocialProfile`、`NewSocialProfile`、`ExistingSocialProfile`、`NonGregorianBirthday`、`NewExtraName` 和 `ExistingExtraName` 类型没有对应的 HarmonyOS 联系人数据。

#### `ContactQueryOptions`

对象 API 支持 `limit`、`offset`、`sortOrder`、`name` 和 `rawContacts`。`name` 还会匹配拼音姓名。`rawContacts` 只能为 `false` 或省略。

#### `ContactPatch`、`CreateContactRecord` 和 `ContactDetails`

对象 API 使用 `givenName`、`middleName`、`familyName`、`nickname`、`prefix`、`suffix`、拼音姓名、`company`、`jobTitle`、`note`、`birthday`、`image`、`emails`、`phones`、`dates`、`addresses`、`relations`、`urlAddresses` 和 `imAddresses`。`ContactDetails` 包含请求的字段和 `id`；不支持的字段会被省略。

对象 API 日期的 `month` 从 `1` 开始；列表项使用 `address`、`number`、`date`、`name` 等字段，具体见对应列表方法。地址的单独 `state`、非 `other` 的网址/即时通讯标签以及没有日期值的日期项不受支持。

#### `ContactsPermissionResponse`

包含 `status`、`granted`、`canAskAgain`、`expires` 和 `accessPrivileges`。`expires` 始终为 `'never'`；`accessPrivileges` 为 `'all'` 或 `'none'`。

#### `FormOptions` 和 `CreateFormOptions`

HarmonyOS 不支持自定义系统联系人表单；传入非空选项对象时抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `ContactAccessButtonProps`

组件不显示内容，属性不会改变 HarmonyOS 上的行为。

### Enums

#### `Fields`

可读取和写入的字段值：`id`、`contactType`、`name`、`firstName`、`middleName`、`lastName`、`namePrefix`、`nameSuffix`、`nickname`、`phoneticFirstName`、`phoneticMiddleName`、`phoneticLastName`、`birthday`、`dates`、`emails`、`phoneNumbers`、`addresses`、`instantMessageAddresses`、`urlAddresses`、`company`、`jobTitle`、`imageAvailable`、`image`、`note`、`relationships`。

- HarmonyOS 联系人服务不提供 `MaidenName`、`NonGregorianBirthday`、`SocialProfiles`、`Department`、`RawImage`、`ExtraNames` 和 `IsFavorite` 字段；读取时省略，写入时抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `ContactField`

对象 API 支持 `FULL_NAME`、`GIVEN_NAME`、`MIDDLE_NAME`、`FAMILY_NAME`、`NICKNAME`、`PREFIX`、`SUFFIX`、`PHONETIC_GIVEN_NAME`、`PHONETIC_MIDDLE_NAME`、`PHONETIC_FAMILY_NAME`、`COMPANY`、`JOB_TITLE`、`NOTE`、`IMAGE`、`THUMBNAIL`、`BIRTHDAY`、`EMAILS`、`PHONES`、`ADDRESSES`、`DATES`、`RELATIONS`、`URL_ADDRESSES` 和 `IM_ADDRESSES`。

- HarmonyOS 不支持 `IS_FAVOURITE`、`MAIDEN_NAME`、`PHONETIC_COMPANY_NAME`、`DEPARTMENT`、`NON_GREGORIAN_BIRTHDAY`、`EXTRA_NAMES` 和 `SOCIAL_PROFILES`。

#### `SortTypes` 和 `ContactsSortOrder`

支持 `userDefault`、`firstName`、`lastName`、`none`；对象 API 对应 `UserDefault`、`GivenName`、`FamilyName`、`None`。`userDefault` / `UserDefault` 和 `none` / `None` 保持系统顺序。

#### `ContactTypes`

取值为 `Person: 'person'`、`Company: 'company'`。HarmonyOS 联系人类型只支持 `person`；公司名称通过 `company` 字段保存。

#### `CalendarFormats`

HarmonyOS 只支持 `Gregorian: 'gregorian'`；写入其他格式会抛出 `ERR_CONTACTS_UNSUPPORTED`。

#### `ContainerTypes`

枚举值包括 `local`、`exchange`、`cardDAV` 和 `unassigned`。legacy 容器查询只返回 `unassigned`；对象 API `Container.getType()` 返回 `'unknown'`。

#### `PermissionStatus`

`GRANTED: 'granted'`、`DENIED: 'denied'`、`UNDETERMINED: 'undetermined'`，对应 `ContactsPermissionResponse.status` 的取值。

### Error codes

| 错误码 | HarmonyOS 触发条件 |
| --- | --- |
| `ERR_CONTACTS_UNSUPPORTED` | 系统能力、字段或操作不受支持，或功能要求更高的 HarmonyOS SDK 版本。 |
| `ERR_CONTACTS_INVALID_ARGUMENT` | 参数类型、值或字段名无效。 |
| `ERR_CONTACTS_INVALID_DATE` | 日期值无效。 |
| `ERR_CONTACTS_MISSING_PERMISSION` | 操作所需的通讯录权限未获授权。 |
| `ERR_CONTACTS_PERMISSION_REQUEST` | 未声明读权限，或系统无法申请声明的权限。 |
| `ERR_CONTACTS_NOT_FOUND` | 联系人不存在或已删除。 |
| `ERR_CONTACTS_GROUP_NOT_FOUND` | 群组不存在。 |
| `ERR_CONTACTS_GROUP_CONTAINER_MISMATCH` | 联系人与群组不属于同一账户。 |
| `ERR_CONTACTS_INVALID_IDENTIFIER` / `ERR_CONTACTS_INVALID_GROUP` / `ERR_CONTACTS_INVALID_CONTAINER` | 系统返回的联系人、群组或容器标识无效。 |
| `ERR_CONTACTS_ADD` | 新建联系人后未取得有效 ID。 |
| `ERR_CONTACTS_STALE_FIELD` | 列表项 ID 已失效或不属于该联系人。 |
| `ERR_CONTACTS_FIELD_NOT_FOUND` | 新增列表项已保存，但无法返回其 ID。 |
| `ERR_CONTACTS_PICKER` / `ERR_CONTACTS_FORM` | 系统联系人选择器或表单无法打开或返回有效结果。 |
| `ERR_CONTACTS_FILE` / `ERR_CONTACTS_FILE_WRITE` / `ERR_CONTACTS_FILE_READ` / `ERR_CONTACTS_FILE_CLEANUP` | vCard 或头像文件操作失败。 |
| `ERR_CONTACTS_OPERATION` | 联系人操作失败。 |
| `ERR_CONTACTS_DESTROYED` | 通讯录模块已销毁。 |
| `ERR_CONTACTS_UI_IN_PROGRESS` | 已有联系人选择器、表单或分享界面正在显示。 |

### Permissions

#### `Contacts.getPermissionsAsync()` / `Contacts.requestPermissionsAsync()`

均返回 `Promise<ContactsPermissionResponse>`。需要声明 `ohos.permission.READ_CONTACTS`；调用申请权限时，如应用也声明 `ohos.permission.WRITE_CONTACTS`，会同时申请读写权限。未声明读权限时，`requestPermissionsAsync()` 抛出 `ERR_CONTACTS_PERMISSION_REQUEST`。

`status` 为 `granted`、`denied` 或 `undetermined`。`granted` 仅在所需权限均获准时为 `true`；读权限获准时 `accessPrivileges` 为 `all`，否则为 `none`。HarmonyOS 不提供 `limited` 状态，`expires` 始终为 `never`。HarmonyOS SDK API 20 起可查询系统记录的拒绝状态；更低版本可能无法准确区分 `denied` 和 `undetermined`。

#### 权限要求

联系人查询、联系人数量、群组和容器查询需要读权限；创建、更新、删除联系人及群组成员变更需要读写权限。系统联系人选择器返回的所选联系人可直接读取，不要求通讯录读权限；系统联系人选择器和新建表单不要求通讯录访问权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
