import * as Crypto from 'expo-crypto';
import { ActionButton, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function CryptoDemo() {
  const primitives = useAsyncResult();
  const aes = useAsyncResult();
  const busy = primitives.state.phase === 'running' || aes.state.phase === 'running';

  const runPrimitives = () => primitives.run(async () => {
    const digest = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, 'abc');
    const expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    if (digest !== expected) throw new Error(`SHA-256 摘要不符合预期：${digest}`);

    const bytes = await Crypto.getRandomBytesAsync(16);
    const uuid = Crypto.randomUUID();
    if (bytes.length !== 16) throw new Error(`预期 16 个随机字节，实际收到 ${bytes.length} 个。`);
    if (!/^[0-9a-f-]{36}$/i.test(uuid)) throw new Error(`无效的 UUID：${uuid}`);

    return json({ digest, randomBytes: Array.from(bytes), uuid });
  });

  const runAes = () => aes.run(async () => {
    const key = await Crypto.AESEncryptionKey.generate(Crypto.AESKeySize.AES128);
    const plaintext = new Uint8Array([0, 1, 2, 3, 250, 251, 252, 253]);
    const sealed = await Crypto.aesEncryptAsync(plaintext, key, {
      nonce: { length: 128 },
      tagLength: 16,
    });
    const decrypted = await Crypto.aesDecryptAsync(sealed, key);
    if (decrypted.length !== plaintext.length || decrypted.some((value, index) => value !== plaintext[index])) {
      throw new Error('AES-GCM 往返结果与原始字节不一致。');
    }

    return json({ bytes: Array.from(decrypted), ivSize: sealed.ivSize, tagSize: sealed.tagSize });
  });

  return (
    <>
      <Panel eyebrow="摘要与随机" title="校验摘要、随机字节与 UUID">
        <ActionButton disabled={busy} label="运行基础加密检测" onPress={() => void runPrimitives()} />
        <ResultPanel state={primitives.state} />
      </Panel>
      <Panel eyebrow="AES-GCM" title="加解密一段精确字节序列">
        <ActionButton disabled={busy} label="运行 AES 往返" onPress={() => void runAes()} />
        <ResultPanel state={aes.state} />
      </Panel>
    </>
  );
}
