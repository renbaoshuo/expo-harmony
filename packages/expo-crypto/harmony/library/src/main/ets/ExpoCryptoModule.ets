/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoNumericTypedArray,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoSharedObjectTypes,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { buffer, url, util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const DEFAULT_IV_LENGTH: number = 12;
const DEFAULT_TAG_LENGTH: number = 16;
const MAXIMUM_IV_LENGTH: number = 128;
const PLATFORM_INT_MAX: number = 0x7fffffff;
const MAXIMUM_AES_KEY_BYTES: number = 32;
const MAXIMUM_HEX_KEY_LENGTH: number = MAXIMUM_AES_KEY_BYTES * 2;
const MAXIMUM_BASE64_KEY_LENGTH: number = 44;
const EMPTY_BYTES: Uint8Array = new Uint8Array(0);
const AES_GCM_ALGORITHM: string = 'AES|GCM|NoPadding';

type IntegerTypedArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array;

class CryptoError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'CryptoError';
  }
}

class ByteView {
  readonly bytes: Uint8Array;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }
}

class DigestOptions {
  encoding: string = 'hex';
}

class EncryptOptions {
  nonceLength: number = DEFAULT_IV_LENGTH;
  nonce?: Uint8Array = undefined;
  tagLength: number = DEFAULT_TAG_LENGTH;
  additionalData: Uint8Array = EMPTY_BYTES;
}

class DecryptOptions {
  output: string = 'bytes';
  additionalData: Uint8Array = EMPTY_BYTES;
}

class SealedDataConfig {
  ivLength: number = DEFAULT_IV_LENGTH;
  tagLength: number = DEFAULT_TAG_LENGTH;
}

class CiphertextOptions {
  includeTag: boolean = false;
  encoding: string = 'bytes';
}

class KeyInput {
  readonly bytes?: Uint8Array;
  readonly text?: string;

  constructor(bytes?: Uint8Array, text?: string) {
    this.bytes = bytes;
    this.text = text;
  }
}

class TagArgument {
  readonly bytes?: Uint8Array;
  readonly length?: number;

  constructor(bytes?: Uint8Array, length?: number) {
    this.bytes = bytes;
    this.length = length;
  }
}

const INTEGER_TYPED_ARRAY_TYPE: ExpoValueType<IntegerTypedArray> = new ExpoValueType<IntegerTypedArray>(
  'integer TypedArray',
  (value: ESObject, path: string): IntegerTypedArray => requireIntegerTypedArray(value, path),
  (value: IntegerTypedArray): ESObject => value as ESObject,
);

const BUFFER_SOURCE_TYPE: ExpoValueType<ByteView> = new ExpoValueType<ByteView>(
  'ArrayBuffer or TypedArray',
  (value: ESObject, path: string): ByteView => new ByteView(requireBufferSource(value, path)),
  (value: ByteView): ESObject => value.bytes as ESObject,
);

const BINARY_INPUT_TYPE: ExpoValueType<Uint8Array> = new ExpoValueType<Uint8Array>(
  'base64 string, ArrayBuffer, or Uint8Array',
  (value: ESObject, path: string): Uint8Array => binaryInput(value, path),
  (value: Uint8Array): ESObject => copyBytes(value) as ESObject,
);

const BINARY_OUTPUT_TYPE: ExpoValueType<ESObject> = new ExpoValueType<ESObject>(
  'base64 string or Uint8Array',
  (value: ESObject, path: string): ESObject => {
    if (typeof value === 'string' || value instanceof Uint8Array) return value;
    throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a base64 string or Uint8Array.`);
  },
  (value: ESObject, path: string): ESObject => {
    if (typeof value === 'string' || value instanceof Uint8Array) return value;
    throw new CryptoError('ERR_INVALID_RETURN_VALUE', `${path} must be a base64 string or Uint8Array.`);
  },
);

const KEY_INPUT_TYPE: ExpoValueType<KeyInput> = new ExpoValueType<KeyInput>(
  'hex/base64 string or Uint8Array',
  (value: ESObject, path: string): KeyInput => {
    if (typeof value === 'string') return new KeyInput(undefined, value);

    if (value instanceof Uint8Array) {
      requireKeyLength(value.byteLength);

      return new KeyInput(copyBytes(value));
    }

    throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a string or Uint8Array.`);
  },
  (value: KeyInput): ESObject => value.text ?? (value.bytes as ESObject),
);

const TAG_ARGUMENT_TYPE: ExpoValueType<TagArgument> = new ExpoValueType<TagArgument>(
  'authentication tag bytes or tag length',
  (value: ESObject, path: string): TagArgument => {
    if (typeof value === 'number') return new TagArgument(undefined, requireSize(value, path));
    return new TagArgument(binaryInput(value, path));
  },
  (value: TagArgument): ESObject => value.length ?? (value.bytes as ESObject),
);

const DIGEST_OPTIONS_TYPE: ExpoValueType<DigestOptions> = new ExpoValueType<DigestOptions>(
  'digest options object',
  (value: ESObject, path: string): DigestOptions => decodeDigestOptions(value, path),
  (value: DigestOptions): ESObject => value as ESObject,
);

const ENCRYPT_OPTIONS_TYPE: ExpoValueType<EncryptOptions> = new ExpoValueType<EncryptOptions>(
  'AES encryption options object',
  (value: ESObject, path: string): EncryptOptions => decodeEncryptOptions(value, path),
  (value: EncryptOptions): ESObject => value as ESObject,
);

const DECRYPT_OPTIONS_TYPE: ExpoValueType<DecryptOptions> = new ExpoValueType<DecryptOptions>(
  'AES decryption options object',
  (value: ESObject, path: string): DecryptOptions => decodeDecryptOptions(value, path),
  (value: DecryptOptions): ESObject => value as ESObject,
);

const SEALED_CONFIG_TYPE: ExpoValueType<SealedDataConfig> = new ExpoValueType<SealedDataConfig>(
  'SealedData configuration object',
  (value: ESObject, path: string): SealedDataConfig => decodeSealedConfig(value, path),
  (value: SealedDataConfig): ESObject => value as ESObject,
);

const CIPHERTEXT_OPTIONS_TYPE: ExpoValueType<CiphertextOptions> = new ExpoValueType<CiphertextOptions>(
  'ciphertext options object',
  (value: ESObject, path: string): CiphertextOptions => decodeCiphertextOptions(value, path),
  (value: CiphertextOptions): ESObject => value as ESObject,
);

export class ExpoCryptoModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoCrypto')
      .syncFunction(
        'getRandomValues',
        ExpoFunction.typed1(INTEGER_TYPED_ARRAY_TYPE.writable(), (target: IntegerTypedArray): void => fillRandom(target)),
      )
      .syncFunction('randomUUID', (): string => randomUuid())
      .syncFunction(
        'digestString',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          DIGEST_OPTIONS_TYPE.nullable().optional(),
          (algorithm: string, text: string, options?: DigestOptions | null): string =>
            encodedDigest(algorithm, utf8Bytes(text), options?.encoding ?? 'hex'),
        ).returns(ExpoValueTypes.string()),
      )
      .asyncFunction(
        'digestStringAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          DIGEST_OPTIONS_TYPE.nullable().optional(),
          async (algorithm: string, text: string, options?: DigestOptions | null): Promise<string> =>
            encodedDigestAsync(algorithm, utf8Bytes(text), options?.encoding ?? 'hex'),
        ).returns(ExpoValueTypes.string()),
      )
      .syncFunction(
        'digest',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          BUFFER_SOURCE_TYPE.writable(),
          BUFFER_SOURCE_TYPE,
          (algorithm: string, output: ByteView, data: ByteView): void => {
            const digest = digestBytes(algorithm, data.bytes);
            output.bytes.set(digest.subarray(0, Math.min(output.bytes.byteLength, digest.byteLength)));
          },
        ),
      );
  }
}

class EncryptionKeyObject extends ExpoSharedObject {
  readonly size: number;
  private nativeKey: cryptoFramework.SymKey | undefined;

  constructor(context: ExpoModuleContext, nativeKey: cryptoFramework.SymKey, size: number) {
    super(context);

    this.nativeKey = nativeKey;
    this.size = size;
  }

  bytes(): Uint8Array {
    return this.requireKey().getEncoded().data;
  }

  encoded(encoding: string): string {
    if (encoding !== 'hex' && encoding !== 'base64') {
      throw new CryptoError('ERR_CRYPTO_INVALID_KEY', "Key encoding must be 'hex' or 'base64'.");
    }

    const bytes = this.bytes();

    try {
      return encoding === 'hex' ? hexEncode(bytes) : base64Encode(bytes);
    } finally {
      secureErase(bytes);
    }
  }

  createCipher(mode: cryptoFramework.CryptoMode, params: cryptoFramework.ParamsSpec): cryptoFramework.Cipher {
    const cipher = cryptoFramework.createCipher(AES_GCM_ALGORITHM);
    // Initialize the cipher before an explicit JS release can clear the native key.
    cipher.initSync(mode, this.requireKey(), params);
    return cipher;
  }

  override sharedObjectWillRelease(): void {
    const native = this.nativeKey;
    this.nativeKey = undefined;
    native?.clearMem();
  }

  override getAdditionalMemoryPressure(): number {
    return this.size / 8;
  }

  private requireKey(): cryptoFramework.SymKey {
    if (this.nativeKey === undefined) {
      throw new CryptoError('ERR_SHARED_OBJECT_RELEASED', 'The AES encryption key has been released.');
    }

    return this.nativeKey;
  }
}

class SealedDataObject extends ExpoSharedObject {
  readonly ivSize: number;
  readonly tagSize: number;
  private readonly data: Uint8Array;

  constructor(context: ExpoModuleContext, data: Uint8Array, ivLength: number, tagLength: number) {
    super(context);

    requireTagLength(tagLength, 'ERR_CRYPTO_INVALID_SEALED_DATA');
    requireSealedDataLength(data.byteLength, ivLength, tagLength);

    this.data = data;
    this.ivSize = ivLength;
    this.tagSize = tagLength;
  }

  get combinedSize(): number {
    return this.data.byteLength;
  }

  iv(): Uint8Array {
    return this.data.subarray(0, this.ivSize);
  }

  tag(): Uint8Array {
    return this.data.subarray(this.combinedSize - this.tagSize);
  }

  ciphertext(includeTag: boolean = false): Uint8Array {
    return this.data.subarray(this.ivSize, includeTag ? this.combinedSize : this.combinedSize - this.tagSize);
  }

  combined(): Uint8Array {
    return this.data;
  }

  override getAdditionalMemoryPressure(): number {
    return this.combinedSize;
  }
}

const KEY_OBJECT_TYPE: ExpoValueType<EncryptionKeyObject> = ExpoSharedObjectTypes.named<EncryptionKeyObject>('ExpoCryptoAES', 'EncryptionKey');

const SEALED_OBJECT_TYPE: ExpoValueType<SealedDataObject> = ExpoSharedObjectTypes.named<SealedDataObject>('ExpoCryptoAES', 'SealedData');

export class ExpoCryptoAESModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    const keyClass = new ExpoSharedObjectClassDefinition<EncryptionKeyObject>('EncryptionKey');
    keyClass
      .construct((_context: ExpoModuleContext): EncryptionKeyObject => {
        throw new CryptoError('ERR_INVALID_ARGUMENT', 'EncryptionKey constructor cannot be used directly.');
      })
      .staticAsyncFunction(
        'generate',
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.number().nullable().optional(),
          async (context: ExpoModuleContext, size?: number | null): Promise<EncryptionKeyObject> => {
            const resolved = size ?? 256;
            requireKeySize(resolved);

            try {
              const key = await cryptoFramework.createSymKeyGenerator(`AES${resolved}`).generateSymKey();

              return attachEncryptionKey(keyClass, context, key, resolved);
            } catch (error) {
              throw new CryptoError('ERR_CRYPTO_AES_KEY', `Unable to generate the AES key. ${errorMessage(error as Object)}`, error as Object);
            }
          },
        ).returns(KEY_OBJECT_TYPE),
      )
      .staticAsyncFunction(
        'import',
        ExpoFunction.ownedTyped2(
          KEY_INPUT_TYPE,
          ExpoValueTypes.string().nullable().optional(),
          async (context: ExpoModuleContext, input: KeyInput, encoding?: string | null): Promise<EncryptionKeyObject> => {
            let bytes: Uint8Array | undefined = undefined;

            try {
              if (input.text !== undefined) {
                if (encoding === undefined || encoding === null) {
                  throw new CryptoError('ERR_CRYPTO_INVALID_KEY', 'Encoding must be provided for string key input.');
                }

                if (encoding === 'hex') {
                  requireHexKeyTextLength(input.text);
                  bytes = hexDecode(input.text);
                } else if (encoding === 'base64') {
                  bytes = base64Decode(input.text, MAXIMUM_BASE64_KEY_LENGTH);
                } else {
                  throw new CryptoError('ERR_CRYPTO_INVALID_KEY', "Key encoding must be 'hex' or 'base64'.");
                }
              } else {
                bytes = input.bytes as Uint8Array;
              }

              requireKeyLength(bytes.byteLength);

              const size = bytes.byteLength * 8;
              const key = await cryptoFramework.createSymKeyGenerator(`AES${size}`).convertKey({ data: bytes });

              return attachEncryptionKey(keyClass, context, key, size);
            } finally {
              if (bytes !== undefined) secureErase(bytes);
            }
          },
        ).returns(KEY_OBJECT_TYPE),
      )
      .asyncFunction(
        'bytes',
        ExpoFunction.ownedTyped0(async (key: EncryptionKeyObject): Promise<Uint8Array> => key.bytes()).returns(ExpoValueTypes.uint8Array()),
      )
      .asyncFunction(
        'encoded',
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string(),
          async (key: EncryptionKeyObject, encoding: string): Promise<string> => key.encoded(encoding),
        ).returns(ExpoValueTypes.string()),
      )
      .property('size', ExpoValueTypes.number(), (key: EncryptionKeyObject): number => key.size);

    const sealedClass = new ExpoSharedObjectClassDefinition<SealedDataObject>('SealedData');
    sealedClass
      .construct((_context: ExpoModuleContext): SealedDataObject => {
        throw new CryptoError('ERR_INVALID_ARGUMENT', 'SealedData constructor cannot be used directly.');
      })
      .staticSyncFunction(
        'fromCombined',
        ExpoFunction.ownedTyped2(
          BINARY_INPUT_TYPE,
          SEALED_CONFIG_TYPE.nullable().optional(),
          (context: ExpoModuleContext, combined: Uint8Array, config?: SealedDataConfig | null): SealedDataObject => {
            const resolved = config ?? new SealedDataConfig();
            return sealedClass.instance(new SealedDataObject(context, combined, resolved.ivLength, resolved.tagLength));
          },
        ).returns(SEALED_OBJECT_TYPE),
      )
      .staticSyncFunction(
        'fromParts',
        ExpoFunction.ownedTyped3(
          BINARY_INPUT_TYPE,
          BINARY_INPUT_TYPE,
          TAG_ARGUMENT_TYPE.nullable().optional(),
          (context: ExpoModuleContext, iv: Uint8Array, ciphertext: Uint8Array, tag?: TagArgument | null): SealedDataObject => {
            const object = sealedFromParts(context, iv, ciphertext, tag ?? undefined);
            return sealedClass.instance(object);
          },
        ).returns(SEALED_OBJECT_TYPE),
      )
      .asyncFunction(
        'iv',
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string().nullable().optional(),
          async (sealed: SealedDataObject, encoding?: string | null): Promise<ESObject> => formatBytes(sealed.iv(), encoding ?? 'bytes'),
        ).returns(BINARY_OUTPUT_TYPE),
      )
      .asyncFunction(
        'tag',
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string().nullable().optional(),
          async (sealed: SealedDataObject, encoding?: string | null): Promise<ESObject> => formatBytes(sealed.tag(), encoding ?? 'bytes'),
        ).returns(BINARY_OUTPUT_TYPE),
      )
      .asyncFunction(
        'combined',
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string().nullable().optional(),
          async (sealed: SealedDataObject, encoding?: string | null): Promise<ESObject> => formatBytes(sealed.combined(), encoding ?? 'bytes'),
        ).returns(BINARY_OUTPUT_TYPE),
      )
      .asyncFunction(
        'ciphertext',
        ExpoFunction.ownedTyped1(
          CIPHERTEXT_OPTIONS_TYPE.nullable().optional(),
          async (sealed: SealedDataObject, options?: CiphertextOptions | null): Promise<ESObject> => {
            const resolved = options ?? new CiphertextOptions();
            return formatBytes(sealed.ciphertext(resolved.includeTag), resolved.encoding);
          },
        ).returns(BINARY_OUTPUT_TYPE),
      )
      .property('combinedSize', ExpoValueTypes.number(), (sealed: SealedDataObject): number => sealed.combinedSize)
      .property('ivSize', ExpoValueTypes.number(), (sealed: SealedDataObject): number => sealed.ivSize)
      .property('tagSize', ExpoValueTypes.number(), (sealed: SealedDataObject): number => sealed.tagSize);

    return new ExpoModuleDefinition()
      .name('ExpoCryptoAES')
      .sharedObjectClass(keyClass)
      .sharedObjectClass(sealedClass)
      .asyncFunction(
        'encryptAsync',
        ExpoFunction.typed3(
          BINARY_INPUT_TYPE,
          KEY_OBJECT_TYPE,
          ENCRYPT_OPTIONS_TYPE.nullable().optional(),
          async (plaintext: Uint8Array, key: EncryptionKeyObject, options?: EncryptOptions | null): Promise<SealedDataObject> => {
            try {
              const sealed = await encryptAesGcm(plaintext, key, options ?? new EncryptOptions());
              return sealedClass.instance(sealed);
            } finally {
              secureErase(plaintext);
            }
          },
        ).returns(SEALED_OBJECT_TYPE),
      )
      .asyncFunction(
        'decryptAsync',
        ExpoFunction.typed3(
          SEALED_OBJECT_TYPE,
          KEY_OBJECT_TYPE,
          DECRYPT_OPTIONS_TYPE.nullable().optional(),
          async (sealed: SealedDataObject, key: EncryptionKeyObject, options?: DecryptOptions | null): Promise<ESObject> => {
            const config = options ?? new DecryptOptions();
            const bytes = await decryptAesGcm(sealed, key, config.additionalData);

            try {
              return config.output === 'bytes' ? copyBytes(bytes) : base64Encode(bytes);
            } finally {
              secureErase(bytes);
            }
          },
        ).returns(BINARY_OUTPUT_TYPE),
      );
  }
}

function attachEncryptionKey(
  keyClass: ExpoSharedObjectClassDefinition<EncryptionKeyObject>,
  context: ExpoModuleContext,
  native: cryptoFramework.SymKey,
  size: number,
): EncryptionKeyObject {
  try {
    return keyClass.instance(new EncryptionKeyObject(context, native, size));
  } catch (error) {
    native.clearMem();

    throw new CryptoError('ERR_CRYPTO_AES_KEY', 'Unable to attach the AES key.', error as Object);
  }
}

function requireIntegerTypedArray(value: ESObject, path: string): IntegerTypedArray {
  if (
    value instanceof Int8Array ||
    value instanceof Uint8Array ||
    value instanceof Uint8ClampedArray ||
    value instanceof Int16Array ||
    value instanceof Uint16Array ||
    value instanceof Int32Array ||
    value instanceof Uint32Array
  ) {
    return value;
  }

  throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be an integer TypedArray.`);
}

function requireBufferSource(value: ESObject, path: string): Uint8Array {
  if (value instanceof ArrayBuffer) return new Uint8Array(value);

  if (
    value instanceof Int8Array ||
    value instanceof Uint8Array ||
    value instanceof Uint8ClampedArray ||
    value instanceof Int16Array ||
    value instanceof Uint16Array ||
    value instanceof Int32Array ||
    value instanceof Uint32Array ||
    value instanceof Float32Array ||
    value instanceof Float64Array ||
    value instanceof BigInt64Array ||
    value instanceof BigUint64Array
  ) {
    const typed = value as ExpoNumericTypedArray;
    return new Uint8Array(typed.buffer, typed.byteOffset, typed.byteLength);
  }

  throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be an ArrayBuffer or TypedArray.`);
}

function binaryInput(value: ESObject, path: string): Uint8Array {
  if (typeof value === 'string') return base64Decode(value);
  if (value instanceof ArrayBuffer) return new Uint8Array(value.slice(0));
  if (value instanceof Uint8Array) return copyBytes(value);
  throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a base64 string, ArrayBuffer, or Uint8Array.`);
}

function requireRecord(value: ESObject, path: string): Record<string, ESObject> {
  if (
    value === null ||
    value === undefined ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    value instanceof ArrayBuffer ||
    ArrayBuffer.isView(value) ||
    value instanceof Date ||
    value instanceof url.URL
  ) {
    throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be an object.`);
  }

  return value as Record<string, ESObject>;
}

function decodeDigestOptions(value: ESObject, path: string): DigestOptions {
  const input = requireRecord(value, path);
  const result = new DigestOptions();
  result.encoding = optionalString(input['encoding'], `${path}.encoding`) ?? 'hex';
  if (result.encoding !== 'hex' && result.encoding !== 'base64') {
    throw new CryptoError('ERR_CRYPTO_DIGEST', `Unsupported digest encoding '${result.encoding}'.`);
  }

  return result;
}

function decodeEncryptOptions(value: ESObject, path: string): EncryptOptions {
  const input = requireRecord(value, path);
  const result = new EncryptOptions();

  const tagLength = optionalSize(input['tagLength'], `${path}.tagLength`);
  if (tagLength !== undefined) result.tagLength = tagLength;
  requireTagLength(result.tagLength, 'ERR_CRYPTO_UNSUPPORTED_TAG_LENGTH');

  const nonce: ESObject = input['nonce'];
  if (nonce !== undefined && nonce !== null) {
    if (typeof nonce === 'number') result.nonceLength = requireSize(nonce, `${path}.nonce`);
    else result.nonce = binaryInput(nonce, `${path}.nonce`);
  }
  requireNonceLength(result.nonce?.byteLength ?? result.nonceLength);

  const aad: ESObject = input['additionalData'];
  if (aad !== undefined && aad !== null) {
    result.additionalData = binaryInput(aad, `${path}.additionalData`);
  }

  return result;
}

function decodeDecryptOptions(value: ESObject, path: string): DecryptOptions {
  const input = requireRecord(value, path);
  const result = new DecryptOptions();
  result.output = optionalString(input['output'], `${path}.output`) ?? 'bytes';
  requireBinaryEncoding(result.output);

  const aad: ESObject = input['additionalData'];
  if (aad !== undefined && aad !== null) {
    result.additionalData = binaryInput(aad, `${path}.additionalData`);
  }

  return result;
}

function decodeSealedConfig(value: ESObject, path: string): SealedDataConfig {
  const input = requireRecord(value, path);
  const result = new SealedDataConfig();
  result.ivLength = optionalSize(input['ivLength'], `${path}.ivLength`) ?? DEFAULT_IV_LENGTH;
  result.tagLength = optionalSize(input['tagLength'], `${path}.tagLength`) ?? DEFAULT_TAG_LENGTH;

  return result;
}

function decodeCiphertextOptions(value: ESObject, path: string): CiphertextOptions {
  const input = requireRecord(value, path);
  const result = new CiphertextOptions();
  result.includeTag = optionalBoolean(input['includeTag'], `${path}.includeTag`) ?? false;
  // The iOS and Android bridges also accept the native outputFormat key.
  result.encoding = optionalString(input['encoding'], `${path}.encoding`) ??
    optionalString(input['outputFormat'], `${path}.outputFormat`) ?? 'bytes';
  requireBinaryEncoding(result.encoding);

  return result;
}

function optionalString(value: ESObject, path: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a string.`);
  return value;
}

function optionalBoolean(value: ESObject, path: string): boolean | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'boolean') throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a boolean.`);
  return value;
}

function optionalSize(value: ESObject, path: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number') throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a non-negative integer.`);
  return requireSize(value, path);
}

function requireSize(value: number, path: string): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new CryptoError('ERR_INVALID_ARGUMENT', `${path} must be a non-negative integer.`);
  }

  return value;
}

function fillRandom(target: IntegerTypedArray): void {
  const bytes = new Uint8Array(target.buffer, target.byteOffset, target.byteLength);
  if (bytes.byteLength > 0) bytes.set(randomBytes(bytes.byteLength));
}

function randomBytes(length: number): Uint8Array {
  if (length > PLATFORM_INT_MAX) {
    throw new CryptoError('ERR_CRYPTO_RANDOM', 'The requested random buffer is too large.');
  }

  try {
    const bytes = cryptoFramework.createRandom().generateRandomSync(length).data;
    requireRandomLength(bytes, length);

    return bytes;
  } catch (error) {
    throw new CryptoError('ERR_CRYPTO_RANDOM', `Unable to generate secure random bytes. ${errorMessage(error as Object)}`, error as Object);
  }
}

function randomUuid(): string {
  try {
    return util.generateRandomUUID().toLowerCase();
  } catch (error) {
    throw new CryptoError('ERR_CRYPTO_RANDOM', `Unable to generate a secure random UUID. ${errorMessage(error as Object)}`, error as Object);
  }
}

function digestBytes(algorithm: string, data: Uint8Array): Uint8Array {
  const name = digestAlgorithm(algorithm);

  try {
    const digest = cryptoFramework.createMd(name);
    if (data.byteLength > 0) digest.updateSync({ data });

    return copyBytes(digest.digestSync().data);
  } catch (error) {
    throw new CryptoError('ERR_CRYPTO_DIGEST', `Unable to compute the ${algorithm} digest. ${errorMessage(error as Object)}`, error as Object);
  }
}

async function digestBytesAsync(algorithm: string, data: Uint8Array): Promise<Uint8Array> {
  const name = digestAlgorithm(algorithm);

  try {
    const digest = cryptoFramework.createMd(name);
    if (data.byteLength > 0) await digest.update({ data });

    return copyBytes((await digest.digest()).data);
  } catch (error) {
    throw new CryptoError('ERR_CRYPTO_DIGEST', `Unable to compute the ${algorithm} digest. ${errorMessage(error as Object)}`, error as Object);
  }
}

function digestAlgorithm(algorithm: string): string {
  if (algorithm === 'SHA-1') return 'SHA1';
  if (algorithm === 'SHA-256') return 'SHA256';
  if (algorithm === 'SHA-384') return 'SHA384';
  if (algorithm === 'SHA-512') return 'SHA512';
  if (algorithm === 'MD5') return 'MD5';
  throw new CryptoError('ERR_CRYPTO_DIGEST', `Unsupported digest algorithm '${algorithm}'.`);
}

function encodedDigest(algorithm: string, data: Uint8Array, encoding: string): string {
  const digest = digestBytes(algorithm, data);

  if (encoding === 'hex') return hexEncode(digest);
  if (encoding === 'base64') return base64Encode(digest);
  throw new CryptoError('ERR_CRYPTO_DIGEST', `Unsupported digest encoding '${encoding}'.`);
}

async function encodedDigestAsync(algorithm: string, data: Uint8Array, encoding: string): Promise<string> {
  const digest = await digestBytesAsync(algorithm, data);

  if (encoding === 'hex') return hexEncode(digest);
  if (encoding === 'base64') return base64Encode(digest);
  throw new CryptoError('ERR_CRYPTO_DIGEST', `Unsupported digest encoding '${encoding}'.`);
}

async function encryptAesGcm(plaintext: Uint8Array, key: EncryptionKeyObject, options: EncryptOptions): Promise<SealedDataObject> {
  try {
    const nonce = options.nonce ?? randomBytes(options.nonceLength);
    const params = gcmParams(nonce, options.additionalData, options.tagLength);
    const cipher = key.createCipher(cryptoFramework.CryptoMode.ENCRYPT_MODE, params);

    if (plaintext.byteLength === 0 && options.tagLength === DEFAULT_TAG_LENGTH && options.additionalData.byteLength > 0) {
      // The legacy GCM implementation commits AAD on update, including for an empty message.
      await cipher.update({ data: plaintext });
    }

    const result = await cipher.doFinal(plaintext.byteLength === 0 ? null : { data: plaintext });
    if (result === null || result.data.byteLength !== plaintext.byteLength + options.tagLength) {
      throw new CryptoError('ERR_CRYPTO_ENCRYPT', 'Harmony returned an invalid AES-GCM ciphertext or tag length.');
    }

    return new SealedDataObject(key.context, concatBytes([nonce, result.data]), nonce.byteLength, options.tagLength);
  } catch (error) {
    if (error instanceof CryptoError) {
      throw new CryptoError(error.code, error.message, error.cause);
    }

    throw new CryptoError('ERR_CRYPTO_ENCRYPT', `AES-GCM encryption failed. ${errorMessage(error as Object)}`, error as Object);
  }
}

async function decryptAesGcm(sealed: SealedDataObject, key: EncryptionKeyObject, aad: Uint8Array): Promise<Uint8Array> {
  requireNonceLength(sealed.ivSize);

  try {
    const legacy = sealed.tagSize === DEFAULT_TAG_LENGTH;
    const params = gcmParams(sealed.iv(), aad, sealed.tagSize, legacy ? sealed.tag() : undefined);
    const cipher = key.createCipher(cryptoFramework.CryptoMode.DECRYPT_MODE, params);

    const ciphertext = sealed.ciphertext(!legacy);
    const size = legacy ? ciphertext.byteLength : ciphertext.byteLength - sealed.tagSize;
    if (ciphertext.byteLength === 0 && aad.byteLength > 0) {
      await cipher.update({ data: ciphertext });
    }

    const result = await cipher.doFinal(ciphertext.byteLength === 0 ? null : { data: ciphertext });
    if (result === null) {
      if (size === 0) return EMPTY_BYTES;
      throw new CryptoError('ERR_CRYPTO_DECRYPT', 'Harmony returned no AES-GCM plaintext.');
    }
    if (result.data.byteLength !== size) {
      secureErase(result.data);

      throw new CryptoError('ERR_CRYPTO_DECRYPT', 'Harmony returned an invalid AES-GCM plaintext length.');
    }

    return result.data;
  } catch (error) {
    if (error instanceof CryptoError) {
      throw new CryptoError(error.code, error.message, error.cause);
    }

    throw new CryptoError('ERR_CRYPTO_DECRYPT', `AES-GCM authentication failed. ${errorMessage(error as Object)}`, error as Object);
  }
}

function gcmParams(iv: Uint8Array, aad: Uint8Array, tagLength: number, tag?: Uint8Array): cryptoFramework.ParamsSpec {
  if (tagLength === DEFAULT_TAG_LENGTH) {
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: aad },
      authTag: { data: tag ?? new Uint8Array(DEFAULT_TAG_LENGTH) },
    };
    return params;
  }

  if (typeof deviceInfo.apiAvailable !== 'function' || !deviceInfo.apiAvailable('26.0.0')) {
    throw new CryptoError(
      'ERR_CRYPTO_UNSUPPORTED_TAG_LENGTH',
      `${tagLength}-byte AES-GCM tags require HarmonyOS SDK 26.0.0 or later.`,
    );
  }

  const params: cryptoFramework.AeadParamsSpec = {
    algName: 'AeadParamsSpec',
    nonce: iv,
    tagLen: tagLength,
  };
  if (aad.byteLength > 0) params.authenticatedData = aad;

  return params;
}

function sealedFromParts(context: ExpoModuleContext, iv: Uint8Array, ciphertext: Uint8Array, tag?: TagArgument): SealedDataObject {
  if (tag?.bytes !== undefined) {
    return new SealedDataObject(context, concatBytes([iv, ciphertext, tag.bytes]), iv.byteLength, tag.bytes.byteLength);
  }

  const length = tag?.length ?? DEFAULT_TAG_LENGTH;
  return new SealedDataObject(context, concatBytes([iv, ciphertext]), iv.byteLength, length);
}

function requireSealedDataLength(length: number, ivLength: number, tagLength: number): void {
  if (length < ivLength + tagLength) {
    throw new CryptoError(
      'ERR_INVALID_SEALED_DATA_CONFIG',
      `Sealed data is ${length} bytes, which is too short to hold a ${ivLength}-byte IV and a ${tagLength}-byte authentication tag.`,
    );
  }
}

function requireKeySize(size: number): void {
  if (size !== 128 && size !== 192 && size !== 256) {
    throw new CryptoError('ERR_CRYPTO_INVALID_KEY', 'AES key size must be 128, 192, or 256 bits.');
  }
}

function requireKeyLength(length: number): void {
  if (length !== 16 && length !== 24 && length !== 32) {
    throw new CryptoError('ERR_CRYPTO_INVALID_KEY', `Invalid AES key byte length '${length}'.`);
  }
}

function requireNonceLength(length: number): void {
  if (length < 1 || length > MAXIMUM_IV_LENGTH) {
    throw new CryptoError('ERR_CRYPTO_INVALID_NONCE', 'AES-GCM nonce length must be in the range 1...128 on HarmonyOS.');
  }
}

function requireTagLength(length: number, code: string): void {
  if (length !== 4 && length !== 8 && (length < 12 || length > 16)) {
    throw new CryptoError(code, `AES-GCM authentication tag length must be 4, 8, or 12...16 bytes; received ${length} bytes.`);
  }
}

function requireRandomLength(bytes: Uint8Array, expected: number): void {
  if (bytes.byteLength !== expected) {
    throw new CryptoError('ERR_CRYPTO_RANDOM', `Harmony returned ${bytes.byteLength} random bytes for a ${expected}-byte request.`);
  }
}

function requireHexKeyTextLength(value: string): void {
  const prefix = value.startsWith('0x') || value.startsWith('0X') ? 2 : 0;
  if (value.length - prefix > MAXIMUM_HEX_KEY_LENGTH) {
    throw new CryptoError('ERR_CRYPTO_INVALID_KEY', 'The hexadecimal AES key string is too long.');
  }
}

function requireBinaryEncoding(encoding: string): void {
  if (encoding !== 'bytes' && encoding !== 'base64') {
    throw new CryptoError('ERR_INVALID_ARGUMENT', `Unsupported binary output encoding '${encoding}'.`);
  }
}

function formatBytes(bytes: Uint8Array, encoding: string): ESObject {
  if (encoding === 'bytes') return copyBytes(bytes) as ESObject;
  if (encoding === 'base64') return base64Encode(bytes);
  throw new CryptoError('ERR_INVALID_ARGUMENT', `Unsupported binary output encoding '${encoding}'.`);
}

function copyBytes(bytes: Uint8Array): Uint8Array {
  return new Uint8Array(bytes);
}

function utf8Bytes(value: string): Uint8Array {
  // TextEncoder.encodeInto may return undefined for an empty string.
  if (value.length === 0) return new Uint8Array(0);
  return new util.TextEncoder('utf-8').encodeInto(value);
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  const combined = buffer.concat(parts);
  return new Uint8Array(combined.buffer, combined.byteOffset, combined.length);
}

function secureErase(bytes: Uint8Array): void {
  bytes.fill(0);
}

function base64Encode(bytes: Uint8Array): string {
  if (bytes.byteLength === 0) return '';
  return new util.Base64Helper().encodeToStringSync(bytes);
}

function base64Decode(text: string, maximumLength?: number): Uint8Array {
  const compact = text.replace(/[\t\n\f\r ]/g, '');
  if (compact.length === 0) return new Uint8Array(0);
  if (maximumLength !== undefined && compact.length > maximumLength) {
    throw new CryptoError('ERR_CRYPTO_INVALID_KEY', 'The base64 AES key string is too long.');
  }

  // The system decoder expects complete quartets and can silently truncate an incomplete one.
  const remainder = compact.length % 4;
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(compact) || remainder === 1 || (remainder !== 0 && compact.endsWith('='))) {
    throw new CryptoError('ERR_CRYPTO_INVALID_BASE64', 'Invalid base64 string.');
  }

  const padded = remainder === 0 ? compact : compact.padEnd(compact.length + 4 - remainder, '=');

  try {
    return new util.Base64Helper().decodeSync(padded);
  } catch (error) {
    throw new CryptoError('ERR_CRYPTO_INVALID_BASE64', 'Invalid base64 string.', error as Object);
  }
}

function hexEncode(bytes: Uint8Array): string {
  return buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('hex');
}

function hexDecode(value: string): Uint8Array {
  const text = value.startsWith('0x') || value.startsWith('0X') ? value.slice(2) : value;
  // The platform hex decoder can truncate malformed input, so validate before decoding.
  if (text.length % 2 !== 0 || /[^0-9a-fA-F]/.test(text)) {
    throw new CryptoError('ERR_CRYPTO_INVALID_KEY', 'Invalid hexadecimal key string.');
  }

  const decoded = buffer.from(text, 'hex');
  return new Uint8Array(decoded.buffer, decoded.byteOffset, decoded.length);
}

function errorMessage(error: Object): string {
  return String(error).replace(/^Error: /, '');
}
