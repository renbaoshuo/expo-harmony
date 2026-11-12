# @expo-harmony/expo-structured-headers

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-structured-headers)

为 HarmonyOS 上的 React Native 应用提供 Expo Structured Headers 的原生实现，与官方同版本的 `expo-structured-headers` 配套使用。

## 安装

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-structured-headers
```

## API 对照表

### Methods

除 `parseDictionary`、`parseList` 和 `parseItem` 可接受单个字符串或非空字符串数组外，顶层解析函数均接受单个字符串。字符串数组表示同一字段的多行内容，按逗号连接；字符串不能跨行。解析输入须为 ASCII，解析函数会检查完整内容；格式错误或存在未解析字符时抛出 `ParseError`。

#### `parseDictionary(input: string | string[]): Dictionary`

解析字典字段。无取值成员的值为 `[true, 参数]`；重复键使用最后一次的值，并保留首次插入位置。空字符串返回空字典，尾随逗号会导致 `ParseError`。

#### `parseList(input: string | string[]): List`

解析列表字段，成员为 `Item` 或 `InnerList`；空字符串返回空列表，尾随逗号会导致 `ParseError`。

#### `parseItem(input: string | string[]): Item`

解析单项字段，返回 `[取值, 参数]`；空输入会导致 `ParseError`。

#### `parseBareItem(input: string): BareItem`

解析整数、小数、字符串、Token、字节序列或布尔值，不包含参数。

#### `parseParameters(input: string): Parameters`

解析参数；空字符串返回空 `Map`。重复参数使用最后一次的值，并保留首次插入位置。

#### `parseKey(input: string): string`

解析一个字典键或参数名。

#### `parseString(input: string): Item`

解析字符串及其参数，返回值为字符串。

#### `parseToken(input: string): Item`

解析 Token 及其参数，返回值为 `Token`。

#### `parseByteSequence(input: string): Item`

解析 Base64 字节序列及其参数，返回值为 `ByteSequence`。

#### `parseBoolean(input: string): Item`

解析布尔值及其参数，返回值为 `boolean`。

#### `parseIntegerOrDecimal(input: string): Item`

解析整数或小数及其参数；小数以 `Decimal` 返回。

#### `parseInnerList(input: string): InnerList`

解析内嵌列表及其列表参数。

#### `parseItemOrInnerList(input: string): Item | InnerList`

解析单项或内嵌列表；输入以 `(` 开始时解析为内嵌列表。

#### `serializeDictionary(input: Dictionary): string`

序列化字典，成员按 `Map` 插入顺序输出。键和参数名须以小写字母或 `*` 开头，后续字符可为小写字母、数字、`_`、`-`、`.` 或 `*`。值为 `true` 的成员只输出键名，值为 `false` 的成员输出为 `key=?0`。

#### `serializeList(input: List): string`

序列化列表，成员之间以 `, ` 分隔。

#### `serializeItem(input: Item): string`

序列化取值和参数。整数范围为 ±999,999,999,999,999；字符串只接受 ASCII 空格和可打印字符，并会转义引号和反斜线。布尔值输出为 `?1` 或 `?0`，字节序列用冒号包围 Base64。普通数值作为小数时按三位小数精度舍入；使用 `Decimal` 可保留小数类型，例如 `1.0` 不会序列化为 `1`。无法序列化的输入会抛出 `SerializeError`。

#### `new Parser(input: string | string[])`

创建分步解析器。字符串数组表示同一字段的多行内容，各行以逗号连接；数组不能为空，输入必须为 ASCII。解析器方法从当前游标读取内容；除完整字段方法外，不会检查输入是否已结束。

#### `Parser.parseDictionary(): Dictionary`

从当前游标解析字典字段并返回字典。

#### `Parser.parseList(): List`

从当前游标解析列表字段并返回列表。

#### `Parser.parseItem(standalone = true): Item`

从当前游标解析单项。`standalone` 为 `true` 时允许首尾空格并要求输入解析完毕；设为 `false` 时只读取当前单项。

#### `Parser.parseItemOrInnerList(): Item | InnerList`

从当前游标解析单项或内嵌列表，并返回对应结构。

#### `Parser.parseInnerList(): InnerList`

从当前游标解析内嵌列表及其参数。

#### `Parser.parseBareItem(): BareItem`

从当前游标解析一个不带参数的值。

#### `Parser.parseParameters(): Parameters`

从当前游标解析连续参数；当前位置没有参数时返回空 `Map`。

#### `Parser.parseKey(): string`

从当前游标解析一个键。

#### `Parser.parseString(): string`

从当前游标解析字符串值，不读取其后的参数。

#### `Parser.parseToken(): Token`

从当前游标解析 Token 值，不读取其后的参数。

#### `Parser.parseByteSequence(): ByteSequence`

从当前游标解析字节序列值，不读取其后的参数。

#### `Parser.parseBoolean(): boolean`

从当前游标解析布尔值，不读取其后的参数。

#### `Parser.parseIntegerOrDecimal(): number | Decimal`

从当前游标解析整数或小数，不读取其后的参数。

#### `Parser.checkTrail(): void`

检查输入是否已解析完毕；仍有未解析字符时抛出 `ParseError`。

#### `Decimal.valueOf(value: number): Decimal`

按 RFC 8941 精度将有限数值舍入到三位小数，恰好居中时舍入到偶数。

#### `Decimal.fromPermille(permille: number): Decimal`

按千分值构造小数。`permille` 必须是范围为 ±999,999,999,999,999 的整数；否则抛出 `TypeError`。

#### `Decimal#valueOf(): number`

返回该小数对应的普通数值。

#### `Decimal#toNumber(): number`

返回该小数对应的普通数值。

#### `ByteSequence#toBase64(): string`

返回标准 Base64 字符串；空字节序列返回空字符串。

#### `ByteSequence#toBytes(): Uint8Array`

返回字节内容的副本。

#### `Token#toString(): string`

返回 Token 字符串。

#### `new ByteSequence(value: string | Uint8Array): ByteSequence`

使用 Base64 字符串或字节数组构造字节序列；无效 Base64 会抛出 `TypeError`。

#### `new Token(value: string): Token`

构造 Token；不符合 Token 格式时抛出 `TypeError`。

### Types

#### `Parser`

分步解析器。构造参数为一个字符串，或表示同一字段多行内容的字符串数组。数组行以逗号连接；空数组或非 ASCII 输入会导致 `ParseError`。解析失败时也抛出 `ParseError`；`position` 为从零开始、相对于拼接后输入的偏移量。

#### `Dictionary`

`Map<string, Item | InnerList>`，按插入顺序保存字典成员。

#### `List`

`(Item | InnerList)[]`。

#### `Item`

`[BareItem, Parameters]`，由取值和参数组成。

#### `InnerList`

`[Item[], Parameters]`，由内嵌项和该列表的参数组成。

#### `Parameters`

`Map<string, BareItem>`。值为 `true` 表示参数只有名称，没有取值。

#### `BareItem`

`number | Decimal | string | Token | ByteSequence | boolean`。

#### `Decimal`

表示 RFC 8941 小数，范围为 ±999,999,999,999.999，精度为三位小数。使用 `Decimal` 序列化时保留小数类型，例如 `1.0` 不会变为 `1`；普通 `number` 表示小数时按三位小数舍入。非法或超出范围的值会抛出 `TypeError`。

#### `ByteSequence`

表示字节序列。构造参数为 Base64 字符串或 `Uint8Array`，字节数组会被复制。字符串接受标准 Base64，可省略末尾填充；Base64URL 字符、空白和错误填充会被拒绝。序列化时以冒号包围 Base64，空字节序列输出为 `::`。输入无效时抛出 `TypeError`。

#### `Token`

表示 Structured Field Token。首字符须为字母或 `*`，其余字符须符合 Token 格式；不合法时抛出 `TypeError`。作为值序列化时不加引号。

#### `ParseError`

解析失败时抛出的 `Error`，`name` 为 `'ParseError'`，并提供从零开始的 `position`。非 ASCII 字符或格式无效时会抛出此错误；顶层解析函数发现未解析字符时也会抛出此错误。

#### `SerializeError`

序列化失败时抛出的 `Error`，`name` 为 `'SerializeError'`；`cause` 在可用时保留导致失败的错误。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
