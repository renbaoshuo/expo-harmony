/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Crypto from 'expo-crypto';
import { useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const harmony = String(Platform.OS) === 'harmony';
const algorithms = Object.values(Crypto.CryptoDigestAlgorithm).filter(value => !harmony || !['MD2', 'MD4'].includes(value));
const tagSizes: Crypto.GCMTagByteLength[] = [16, 15, 14, 13, 12, 8, 4];
const keySizes = [Crypto.AESKeySize.AES128, Crypto.AESKeySize.AES192, Crypto.AESKeySize.AES256];
const encodings = ['hex', 'base64'] as const;
const outputs = ['bytes', 'base64'] as const;
const nonceTypes = ['默认 nonce', '指定随机字节数', '指定 Base64 字节'] as const;
const binaryTypes = ['UTF-8 字节', 'ArrayBuffer', 'Base64'] as const;
const arrayTypes = {
  Uint8Array, Uint8ClampedArray, Uint16Array, Uint32Array, Int8Array, Int16Array, Int32Array,
};
const randomArrayTypes = Object.keys(arrayTypes) as (keyof typeof arrayTypes)[];

function Choices<T extends string | number>({ choices, value, onChange }: {
  choices: readonly T[];
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <ActionRow>
      {choices.map(item => (
        <ActionButton key={item} label={String(item)} onPress={() => onChange(item)} tone={item === value ? 'primary' : 'secondary'} />
      ))}
    </ActionRow>
  );
}

function hex(bytes: Uint8Array) {
  return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

function hexBytes(value: string) {
  const text = value.replace(/\s/g, '');
  if (!/^(?:[\da-f]{2})+$/i.test(text)) throw new Error('请输入完整的十六进制字节。');
  return Uint8Array.from(text.match(/../g) ?? [], byte => parseInt(byte, 16));
}

function binary(value: string, type: typeof binaryTypes[number]) {
  if (type === 'Base64') return value;
  const bytes = new TextEncoder().encode(value);
  return type === 'ArrayBuffer' ? bytes.buffer : bytes;
}

function output(value: string | Uint8Array) {
  return typeof value === 'string' ? value : json(Array.from(value));
}

export function CryptoDemo() {
  return (
    <>
      <DigestDemo />
      <RandomDemo />
      <AesDemo />
    </>
  );
}

function DigestDemo() {
  const [input, setInput] = useState('Expo');
  const [algorithm, setAlgorithm] = useState(Crypto.CryptoDigestAlgorithm.SHA256);
  const [encoding, setEncoding] = useState(Crypto.CryptoEncoding.HEX);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="计算摘要">
      <Field label="原文" onChangeText={setInput} value={input} />
      <Choices choices={algorithms} value={algorithm} onChange={setAlgorithm} />
      <Choices choices={Object.values(Crypto.CryptoEncoding)} value={encoding} onChange={setEncoding} />
      <ActionRow>
        <ActionButton disabled={busy} label="digestStringAsync()" onPress={() => void action.run(() => Crypto.digestStringAsync(algorithm, input, { encoding }))} />
        <ActionButton
          disabled={busy}
          label="digest() 字节"
          onPress={() => void action.run(async () => {
            const data = new TextEncoder().encode(input);
            return hex(new Uint8Array(await Crypto.digest(algorithm, data)));
          })}
        />
        <ActionButton
          disabled={busy}
          label="digest() ArrayBuffer"
          onPress={() => void action.run(async () => {
            const buffer = new TextEncoder().encode(input).buffer;
            return hex(new Uint8Array(await Crypto.digest(algorithm, buffer)));
          })}
        />
        <ActionButton
          disabled={busy}
          label="digest() DataView"
          onPress={() => void action.run(async () => {
            const data = new TextEncoder().encode(input);
            const buffer = new Uint8Array(data.length + 2);
            buffer.set(data, 1);
            return hex(new Uint8Array(await Crypto.digest(algorithm, new DataView(buffer.buffer, 1, data.length))));
          })}
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function RandomDemo() {
  const [count, setCount] = useState('16');
  const [arrayType, setArrayType] = useState<keyof typeof arrayTypes>('Uint8Array');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const size = Number(count);
  const invalid = !count.trim() || !Number.isInteger(size) || size < 0 || size > 1024;

  return (
    <Panel title="生成随机值">
      <Field label="字节数或数组长度" keyboardType="number-pad" onChangeText={setCount} value={count} />
      <Choices choices={randomArrayTypes} value={arrayType} onChange={setArrayType} />
      <ActionRow>
        <ActionButton disabled={busy || invalid} label="getRandomBytes()" onPress={() => void action.run(() => hex(Crypto.getRandomBytes(size)))} />
        <ActionButton disabled={busy || invalid} label="getRandomBytesAsync()" onPress={() => void action.run(async () => hex(await Crypto.getRandomBytesAsync(size)))} />
        <ActionButton
          disabled={busy || invalid}
          label="getRandomValues()"
          onPress={() => void action.run(() => {
            const ArrayType = arrayTypes[arrayType];
            return json(Array.from(Crypto.getRandomValues(new ArrayType(size))));
          })}
        />
        <ActionButton disabled={busy} label="randomUUID()" onPress={() => void action.run(() => Crypto.randomUUID())} />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function AesDemo() {
  const [size, setSize] = useState(Crypto.AESKeySize.AES128);
  const [keyInput, setKeyInput] = useState('00000000000000000000000000000000');
  const [keyEncoding, setKeyEncoding] = useState<typeof encodings[number]>('hex');
  const [key, setKey] = useState<Crypto.AESEncryptionKey>();
  const [plaintext, setPlaintext] = useState('Expo');
  const [inputType, setInputType] = useState<typeof binaryTypes[number]>('UTF-8 字节');
  const [aad, setAad] = useState('');
  const [nonceType, setNonceType] = useState<typeof nonceTypes[number]>('默认 nonce');
  const [nonceLength, setNonceLength] = useState('12');
  const [nonce, setNonce] = useState('');
  const [encryptTag, setEncryptTag] = useState<Crypto.GCMTagByteLength>(16);
  const [data, setData] = useState<Crypto.AESSealedData>();
  const [format, setFormat] = useState<typeof outputs[number]>('bytes');
  const [includeTag, setIncludeTag] = useState(false);
  const keyAction = useAsyncResult();
  const cipher = useAsyncResult();
  const read = useAsyncResult();

  const saveKey = (load: () => Promise<Crypto.AESEncryptionKey>) => keyAction.run(async () => {
    const value = await load();
    setKey(value);
    return json({ size: value.size });
  });
  const additionalData = aad ? new TextEncoder().encode(aad) : undefined;
  const encryptionOptions = (): Crypto.AESEncryptOptions => ({
    nonce: nonceType === '指定随机字节数'
      ? { length: Number(nonceLength) }
      : nonceType === '指定 Base64 字节' ? { bytes: nonce } : undefined,
    tagLength: encryptTag,
    additionalData,
  });

  const canUseKey = keyAction.state.phase !== 'running' && cipher.state.phase !== 'running';
  const canUseData = read.state.phase !== 'running' && cipher.state.phase !== 'running';

  return (
    <>
      <Panel title="AES 密钥">
        <Choices choices={keySizes} value={size} onChange={setSize} />
        <ActionButton disabled={!canUseKey} label="generate()" onPress={() => void saveKey(() => Crypto.AESEncryptionKey.generate(size))} />
        <Field label="示例密钥" multiline onChangeText={setKeyInput} value={keyInput} />
        <Choices choices={encodings} value={keyEncoding} onChange={setKeyEncoding} />
        <ActionRow>
          <ActionButton disabled={!canUseKey} label="import() 编码字符串" onPress={() => void saveKey(() => Crypto.AESEncryptionKey.import(keyInput, keyEncoding))} />
          <ActionButton disabled={!canUseKey} label="import() 十六进制字节" onPress={() => void saveKey(() => Crypto.AESEncryptionKey.import(hexBytes(keyInput)))} />
          <ActionButton disabled={!key || !canUseKey} label="bytes()" onPress={() => key && void keyAction.run(async () => output(await key.bytes()))} />
          <ActionButton disabled={!key || !canUseKey} label="encoded()" onPress={() => key && void keyAction.run(() => key.encoded(keyEncoding))} />
        </ActionRow>
        <ResultPanel state={keyAction.state} />
      </Panel>

      <Panel title="AES-GCM 加密与解密">
        <Field label="明文" multiline onChangeText={setPlaintext} value={plaintext} />
        <Choices choices={binaryTypes} value={inputType} onChange={setInputType} />
        <Field label="附加认证数据" onChangeText={setAad} value={aad} />
        <Choices choices={nonceTypes} value={nonceType} onChange={setNonceType} />
        {nonceType === '指定随机字节数'
          ? (
              <Field label="nonce 字节数" keyboardType="number-pad" onChangeText={setNonceLength} value={nonceLength} />
            )
          : null}
        {nonceType === '指定 Base64 字节' ? <Field label="nonce Base64" onChangeText={setNonce} value={nonce} /> : null}
        {!harmony ? <Choices choices={tagSizes} value={encryptTag} onChange={setEncryptTag} /> : null}
        <Choices choices={outputs} value={format} onChange={setFormat} />
        <ActionRow>
          <ActionButton
            disabled={!key || !canUseKey || !canUseData}
            label="aesEncryptAsync()"
            onPress={() => key && void cipher.run(async () => {
              const value = await Crypto.aesEncryptAsync(binary(plaintext, inputType), key, encryptionOptions());
              setData(value);
              return json({ combinedSize: value.combinedSize, ivSize: value.ivSize, tagSize: value.tagSize });
            })}
          />
          <ActionButton
            disabled={!key || !data || !canUseKey || !canUseData}
            label="aesDecryptAsync()"
            onPress={() => key && data && void cipher.run(async () => {
              const decrypted = await Crypto.aesDecryptAsync(data, key, { output: format, additionalData });
              return typeof decrypted === 'string'
                ? decrypted
                : json({ text: new TextDecoder().decode(decrypted), bytes: Array.from(decrypted) });
            })}
          />
        </ActionRow>
        <ResultPanel state={cipher.state} />
      </Panel>

      <SealedDataInput onImport={setData} disabled={!canUseData} />

      <Panel title="读取 AESSealedData">
        <Choices choices={outputs} value={format} onChange={setFormat} />
        <ActionButton label={includeTag ? '密文包含认证标签' : '密文省略认证标签'} onPress={() => setIncludeTag(value => !value)} tone={includeTag ? 'primary' : 'secondary'} />
        <ActionRow>
          <ActionButton disabled={!data || !canUseData} label="ciphertext()" onPress={() => data && void read.run(async () => output(await data.ciphertext({ includeTag, encoding: format })))} />
          <ActionButton disabled={!data || !canUseData} label="iv()" onPress={() => data && void read.run(async () => output(await data.iv(format)))} />
          <ActionButton disabled={!data || !canUseData} label="tag()" onPress={() => data && void read.run(async () => output(await data.tag(format)))} />
          <ActionButton disabled={!data || !canUseData} label="combined()" onPress={() => data && void read.run(async () => output(await data.combined(format)))} />
        </ActionRow>
        <ResultPanel state={read.state} />
      </Panel>
    </>
  );
}

function SealedDataInput({ disabled, onImport }: {
  disabled: boolean;
  onImport: (value: Crypto.AESSealedData) => void;
}) {
  const [combined, setCombined] = useState('AAAAAAAAAAAAAAAARvCqoWrjC8aadgDMH17jofnzaVc=');
  const [iv, setIV] = useState('AAAAAAAAAAAAAAAA');
  const [ciphertext, setCiphertext] = useState('RvCqoQ==');
  const [withTag, setWithTag] = useState('RvCqoWrjC8aadgDMH17jofnzaVc=');
  const [tag, setTag] = useState('auMLxpp2AMwfXuOh+fNpVw==');
  const [ivLength, setIVLength] = useState('12');
  const [tagLength, setTagLength] = useState<Crypto.GCMTagByteLength>(16);
  const result = useAsyncResult();
  const parse = (create: () => Crypto.AESSealedData) => result.run(() => {
    const value = create();
    onImport(value);
    return json({ combinedSize: value.combinedSize, ivSize: value.ivSize, tagSize: value.tagSize });
  });

  return (
    <Panel title="导入 AESSealedData">
      <Field label="拼接数据 Base64" multiline onChangeText={setCombined} value={combined} />
      <Field label="IV 字节数" keyboardType="number-pad" onChangeText={setIVLength} value={ivLength} />
      <Choices choices={tagSizes} value={tagLength} onChange={setTagLength} />
      <ActionButton
        disabled={disabled}
        label="fromCombined()"
        onPress={() => void parse(() => Crypto.AESSealedData.fromCombined(
          combined, { ivLength: Number(ivLength), tagLength }
        ))}
      />
      <Field label="IV Base64" onChangeText={setIV} value={iv} />
      <Field label="密文 Base64" onChangeText={setCiphertext} value={ciphertext} />
      <Field label="认证标签 Base64" onChangeText={setTag} value={tag} />
      <ActionButton disabled={disabled} label="fromParts() 独立标签" onPress={() => void parse(() => Crypto.AESSealedData.fromParts(iv, ciphertext, tag))} />
      <Field label="带标签的密文 Base64" onChangeText={setWithTag} value={withTag} />
      <ActionButton disabled={disabled} label="fromParts() 标签长度" onPress={() => void parse(() => Crypto.AESSealedData.fromParts(iv, withTag, tagLength))} />
      <ResultPanel state={result.state} />
    </Panel>
  );
}
