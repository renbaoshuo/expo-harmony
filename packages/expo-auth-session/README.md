# @expo-harmony/expo-auth-session

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-auth-session) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/auth-session/)

为 HarmonyOS 上的 React Native 应用提供 Expo AuthSession 的 HarmonyOS 实现，与官方同版本的 `expo-auth-session` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo-auth-session expo-auth-session \
  @expo-harmony/expo-constants expo-constants \
  @expo-harmony/expo-crypto expo-crypto \
  @expo-harmony/expo-linking expo-linking \
  @expo-harmony/expo-web-browser expo-web-browser
```

使用 Google 提供方时，还需安装：

```bash
npm install @expo-harmony/expo-application expo-application
```

## API 对照表

### Hooks

#### `useAuthRequest(config, discovery)`

参数：`config` 为 `AuthRequestConfig`，`discovery` 为 `DiscoveryDocument | null`，其中请求授权码只需提供 `authorizationEndpoint`。

返回 `[request, response, promptAsync]`。`request` 在加载完成前为 `null`，`response` 在调用 `promptAsync` 前为 `null`；`promptAsync(options?)` 返回 `Promise<AuthSessionResult>`，并在 HarmonyOS 上打开系统浏览器。

#### `useAuthRequestResult(request, discovery, customOptions?)`

参数：`request` 为 `AuthRequest | null`，`discovery` 为 `DiscoveryDocument | null`，`customOptions` 为 `AuthRequestPromptOptions`。

返回 `[response, promptAsync]`。`promptAsync(options?)` 返回 `Promise<AuthSessionResult>`；它在 HarmonyOS 上通过系统浏览器启动认证。

#### `useAutoDiscovery(issuerOrDiscovery)`

参数：`issuerOrDiscovery` 为 HTTPS issuer 字符串或 `DiscoveryDocument`。

返回 `DiscoveryDocument | null`。发现文档加载完成前返回 `null`。

#### `useLoadedAuthRequest(config, discovery, AuthRequestInstance)`

参数：`config` 为 `AuthRequestConfig`，`discovery` 为 `DiscoveryDocument | null`，`AuthRequestInstance` 为 `AuthRequest` 类。

返回 `AuthRequest | null`；请求加载完成前返回 `null`。

### 常量

本包没有独立常量 API；固定值见“枚举”。

### 方法

#### `AuthRequest(config)`

参数：`AuthRequestConfig`。返回 `AuthRequest` 实例。

#### `AuthRequest.promptAsync(discovery, promptOptions?)`

参数：`discovery` 至少包含 `authorizationEndpoint`；`promptOptions` 为 `AuthRequestPromptOptions`。

返回 `Promise<AuthSessionResult>`。收到回跳时解析 URL 并返回 `success` 或 `error`；应用回到前台但没有匹配回跳时返回 `dismiss`；已有认证请求进行中时返回 `locked`。

#### `AuthRequest.getAuthRequestConfigAsync()`

参数：无。返回 `Promise<AuthRequestConfig>`。

#### `AuthRequest.makeAuthUrlAsync(discovery)`

参数：`discovery` 至少包含 `authorizationEndpoint`。返回 `Promise<string>`，即授权 URL。

#### `AuthRequest.parseReturnUrl(url)`

参数：回跳 URL 字符串。返回 `AuthSessionResult`；若返回的 `state` 与请求不匹配，结果类型为 `error`。

#### `AuthSession.dismiss()`

参数：无。返回 `void`，结束当前认证等待；没有进行中的认证会话时不做任何操作，不关闭系统浏览器。

#### `AuthSession.getDefaultReturnUrl(urlPath?, options?)`

参数：可选路径和 `expo-linking` 的 URI 创建选项。返回 `string`，用于 Expo AuthSession 代理回跳。此方法已弃用。

#### `AuthSession.getRedirectUrl(path?)`

参数：可选路径。返回 `string`，用于 Expo AuthSession 代理回跳；HarmonyOS 应用配置中没有项目全名时会抛出错误。此方法已弃用。

#### `AuthSession.makeRedirectUri(options?)`

参数：`AuthSessionRedirectUriOptions`，可指定 `scheme`、`path`、`queryParams`、`isTripleSlashed`、`native` 或 `preferLocalhost`。返回 `string`，作为授权请求的回跳地址。HarmonyOS 应用需有可处理该 scheme 的回跳配置；原生构建中指定 `native` 时直接返回原值。

#### `AuthSession.loadAsync(config, issuerOrDiscovery)`

参数：授权请求配置和 issuer 字符串或 `DiscoveryDocument`。返回 `Promise<AuthRequest>`，请求加载完成后返回。

#### `AuthSession.exchangeCodeAsync(config, discovery)`

参数：`AccessTokenRequestConfig` 和含 `tokenEndpoint` 的发现文档。返回 `Promise<TokenResponse>`。

#### `AuthSession.fetchDiscoveryAsync(issuer)`

参数：issuer URL。返回 `Promise<DiscoveryDocument>`。

#### `AuthSession.fetchUserInfoAsync(config, discovery)`

参数：含 `accessToken` 的配置和含 `userInfoEndpoint` 的发现文档。返回 `Promise<Record<string, any>>`。

#### `AuthSession.getCurrentTimeInSeconds()`

参数：无。返回当前 Unix 时间秒数 `number`。

#### `AuthSession.issuerWithWellKnownUrl(issuer)`

参数：issuer URL。返回其 OpenID Connect discovery 文档 URL `string`。

#### `AuthSession.refreshAsync(config, discovery)`

参数：`RefreshTokenRequestConfig` 和含 `tokenEndpoint` 的发现文档。返回 `Promise<TokenResponse>`。

#### `AuthSession.resolveDiscoveryAsync(issuerOrDiscovery)`

参数：issuer URL 或 `DiscoveryDocument`。返回 `Promise<DiscoveryDocument>`。

#### `AuthSession.revokeAsync(config, discovery)`

参数：`RevokeTokenRequestConfig` 和含 `revocationEndpoint` 的发现文档。返回 `Promise<boolean>`；发现文档没有撤销端点或请求失败时 Promise 拒绝。

#### `AuthSession.requestAsync(requestUrl, fetchRequest)`

参数：请求 URL 和 `FetchRequest`。返回 `Promise<T>`。

#### `TokenResponse.fromQueryParams(params)`

参数：授权回跳中的查询参数。返回 `TokenResponse`。

#### `TokenResponse.isTokenFresh(token, secondsMargin?)`

参数：包含 `expiresIn` 和 `issuedAt` 的 token，以及可选秒数边界（默认 `-600`）。返回 `boolean`。

#### `TokenResponse.shouldRefresh()`

参数：无。返回 `boolean`，表示令牌是否需要刷新。

#### `TokenResponse.refreshAsync(config, discovery)`

参数：刷新配置和含 `tokenEndpoint` 的发现文档。返回 `Promise<TokenResponse>`，并更新当前实例。

#### `TokenResponse.getRequestConfig()`

参数：无。返回 `TokenResponseConfig`。

#### `TokenResponse(response, rawResponse?)`

参数：`TokenResponseConfig` 和可选原始响应对象。返回 `TokenResponse` 实例。

#### `AccessTokenRequest(config)` / `RefreshTokenRequest(config)` / `RevokeTokenRequest(config)`

参数分别为 `AccessTokenRequestConfig`、`RefreshTokenRequestConfig` 和 `RevokeTokenRequestConfig`。返回对应令牌请求实例。

#### `AccessTokenRequest.performAsync(discovery)` / `RefreshTokenRequest.performAsync(discovery)`

参数：含 `tokenEndpoint` 的发现文档。返回 `Promise<TokenResponse>`。

#### `RevokeTokenRequest.performAsync(discovery)`

参数：含 `revocationEndpoint` 的发现文档。返回 `Promise<boolean>`。

#### `AccessTokenRequest` / `RefreshTokenRequest` / `RevokeTokenRequest`

`getHeaders()` 返回 `Headers`，`getQueryBody()` 返回 `Record<string, string>`，`getRequestConfig()` 返回对应请求配置。

#### `TokenRequest`

`grantType` 为 `GrantType`。`getHeaders()` 返回 `Headers`，`getQueryBody()` 返回 `Record<string, string>`，`getRequestConfig()` 返回 `TokenRequestConfig`，`performAsync(discovery)` 返回 `Promise<TokenResponse>`。

### 事件

认证结果通过 `promptAsync()` 的 Promise 返回；本包没有单独的 HarmonyOS 认证事件 API。

### 类型

#### `AuthRequestConfig`

授权请求参数。必填 `clientId` 和 `redirectUri`；可选 `responseType`、`scopes`、`clientSecret`、`codeChallengeMethod`、`codeChallenge`、`prompt`、`state`、`extraParams` 和 `usePKCE`。`responseType` 默认 `code`，`codeChallengeMethod` 默认 `S256`，`usePKCE` 默认 `true`。

#### `AuthRequest`

请求对象公开 `state`、`codeVerifier`、`codeChallenge` 和授权 URL `url`。

#### `TokenResponse`

令牌对象公开 `accessToken`、`tokenType`、`expiresIn`、`refreshToken`、`scope`、`state`、`idToken`、`issuedAt` 和 `rawResponse`。

#### `AuthRequestPromptOptions`

`promptAsync()` 的选项，包括可选授权 `url` 和浏览器打开选项。

- `toolbarColor`、`showTitle`、`presentationStyle`、`browserPackage` 和 `windowFeatures` 不生效，因为 HarmonyOS 由系统选择和控制外部浏览器的外观与窗口。
- `preferEphemeralSession` 不生效，因为 Cookie 和登录状态由系统浏览器管理。
- `preferUniversalLinks` 不改变回跳行为；HarmonyOS 根据应用注册的 URI 处理回跳。

#### `AuthSessionRedirectUriOptions`

`makeRedirectUri()` 的选项：`path`、`scheme`、`queryParams`、`isTripleSlashed`、`preferLocalhost` 和 `native`。HarmonyOS 使用应用 scheme 生成回跳地址；独立构建中指定 `native` 时直接返回该地址。

#### `AuthSessionResult`

`promptAsync()` 的结果。HarmonyOS 上 `type` 为 `success`、`error`、`dismiss` 或 `locked`；`success` 和 `error` 结果包含 `url`、`params`、`authentication`（可为 `null`）和 `errorCode`，`error` 字段可选。

- HarmonyOS 无法区分用户关闭浏览器与切回应用，两种情况均为 `dismiss`，不会返回 `cancel`。

#### `DiscoveryDocument` / `AuthDiscoveryDocument`

发现文档包含可选的 `authorizationEndpoint`、`tokenEndpoint`、`revocationEndpoint`、`userInfoEndpoint` 和 `endSessionEndpoint`；`AuthDiscoveryDocument` 只要求 `authorizationEndpoint`。

#### `Issuer` / `IssuerOrDiscovery`

`Issuer` 是 issuer URL 字符串；`IssuerOrDiscovery` 是 issuer URL 或 `DiscoveryDocument`。

#### `ProviderMetadata` / `ProviderMetadataEndpoints`

OpenID Connect 提供方元数据及其端点字段类型。

#### `AuthErrorConfig` / `ResponseErrorConfig`

认证响应错误参数，包含必填 `error` 及可选错误描述、错误详情 URI 和 `state`。

#### `AccessTokenRequestConfig` / `RefreshTokenRequestConfig` / `RevokeTokenRequestConfig`

分别用于授权码交换、令牌刷新和令牌撤销；撤销配置必填 `token`，其他字段按类型定义可选。

#### `TokenRequestConfig` / `ServerTokenResponseConfig` / `TokenResponseConfig`

分别表示令牌请求参数、服务端原始令牌响应和 `TokenResponse` 配置。

#### `FetchRequest` / `Headers`

`FetchRequest` 包含可选请求头、请求体、数据类型和 HTTP 方法；`Headers` 是字符串键值映射，包含 `Content-Type`。

#### `ProviderAuthRequestConfig` / `GoogleAuthRequestConfig` / `FacebookAuthRequestConfig`

提供方请求配置。HarmonyOS 上 Google 和 Facebook hook 使用 `webClientId`，未提供时使用 `clientId`。Google 与 Facebook 配置类型在 Expo SDK 57 中已弃用。

#### `PromptMethod`

`(options?: AuthRequestPromptOptions) => Promise<AuthSessionResult>`。

#### `TokenType`

`'bearer' | 'mac'`。

### 枚举

#### `CodeChallengeMethod`

`S256` 和 `Plain`。

- `AuthRequest` 不接受 `Plain`，因为该模式不符合安全要求。

#### `ResponseType`

`Code`（`'code'`）、`Token`（`'token'`）和 `IdToken`（`'id_token'`）。

#### `Prompt`

`None`、`Login`、`Consent` 和 `SelectAccount`。

#### `GrantType`

`AuthorizationCode`、`Implicit`、`RefreshToken` 和 `ClientCredentials`。

#### `TokenTypeHint`

`AccessToken`（`'access_token'`）和 `RefreshToken`（`'refresh_token'`）。

### 错误码

#### `AuthRequest.promptAsync()` 的浏览器错误

浏览器 URL 无效、应用不在前台、已有认证会话、发起会话的 UIAbility 已销毁或系统浏览器启动失败时，Promise 以对应错误拒绝：`ERR_WEB_BROWSER_INVALID_URL`、`ERR_WEB_BROWSER_UNAVAILABLE`、`ERR_WEB_BROWSER_ALREADY_OPEN`、`ERR_WEB_BROWSER_DESTROYED` 或 `ERR_WEB_AUTH_SESSION_FAILED_TO_START`。

#### `AuthError.code`

回跳中的授权错误码；服务端返回的常见值包括 `invalid_request`、`unauthorized_client`、`access_denied`、`unsupported_response_type`、`invalid_scope`、`server_error`、`temporarily_unavailable`、`interaction_required`、`login_required`、`account_selection_required`、`consent_required`、`invalid_request_uri`、`invalid_request_object`、`request_not_supported`、`request_uri_not_supported` 和 `registration_not_supported`。返回的 `state` 与请求不一致时为 `state_mismatch`。

#### `TokenError.code`

令牌端点返回的错误码；常见值包括 `invalid_request`、`invalid_client`、`invalid_grant`、`unauthorized_client` 和 `unsupported_grant_type`。

#### `ResponseError` / `AuthError` / `TokenError`

错误对象的 `code` 为错误码，`description`、`info` 和 `uri` 可选，`params` 为原始响应参数。

### 权限

认证和回跳不需要额外声明 HarmonyOS 系统权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
