import { Directory, File, Paths } from 'expo-file-system';
import * as LegacyFileSystem from 'expo-file-system/legacy';

function assertBytes(actual: Uint8Array, expected: Uint8Array, label: string): void {
  if (actual.length !== expected.length || actual.some((value, index) => value !== expected[index])) {
    throw new Error(`${label}: expected [${Array.from(expected)}], received [${Array.from(actual)}].`);
  }
}

function assertValue(actual: unknown, expected: unknown, label: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}.`);
  }
}

function assertThrows(action: () => void, label: string): void {
  try {
    action();
  } catch {
    return;
  }
  throw new Error(`${label}: expected an error.`);
}

/** Exercises the public JS API against the real native module without opening a picker. */
export async function assertFileSystemReadContracts(): Promise<Record<string, unknown>> {
  const directory = new Directory(Paths.cache, `filesystem-contracts-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  directory.create();
  const file = new File(directory, 'bytes.bin');
  const expected = Uint8Array.from({ length: 37 }, (_, index) => index);

  try {
    file.create({ intermediates: true });
    await LegacyFileSystem.makeDirectoryAsync(directory.uri, { intermediates: true });
    await LegacyFileSystem.makeDirectoryAsync(directory.uri, { intermediates: true });
    const nested = new File(directory, 'nested', 'empty.bin');
    nested.create({ intermediates: true });
    assertValue(nested.exists, true, 'creation with missing intermediate directory');
    file.write(expected);
    const handle = file.open();
    try {
      assertBytes(handle.readBytes(7), expected.slice(0, 7), 'first chunk');
      assertBytes(handle.readBytes(11), expected.slice(7, 18), 'second chunk');
      assertValue(handle.offset, 18, 'offset after consecutive reads');
      handle.offset = 4;
      assertBytes(handle.readBytes(3), expected.slice(4, 7), 'seek read');
      assertValue(handle.offset, 7, 'offset after seek read');
      handle.offset = expected.length - 2;
      assertBytes(handle.readBytes(8), expected.slice(-2), 'read across EOF');
      assertValue(handle.offset, expected.length, 'offset at EOF');
      assertBytes(handle.readBytes(1), new Uint8Array(), 'read at EOF');
      handle.offset = 0;
      assertBytes(handle.readBytes(64 * 1024 * 1024 + 1), expected, 'large request against small file');
      assertBytes(handle.readBytes(64 * 1024 * 1024 + 1), new Uint8Array(), 'large request at EOF');
    } finally {
      handle.close();
    }

    const range = await LegacyFileSystem.readAsStringAsync(file.uri, {
      encoding: LegacyFileSystem.EncodingType.Base64,
      position: 4,
      length: 3,
    });
    assertValue(range, 'BAUG', 'legacy Base64 range');
    assertBytes(await file.bytes(), expected, 'read contracts preserve file content');
    const copy = new File(directory, 'copy.bin');
    file.copy(copy);
    assertThrows(() => file.copy(copy), 'copy must reject an existing file');
    assertBytes(await copy.bytes(), expected, 'copy preserves existing destination contents');
    copy.rename('renamed.bin');
    assertValue(copy.name, 'renamed.bin', 'rename updates file URI');
    copy.move(new File(directory, 'moved.bin'));
    assertValue(copy.name, 'moved.bin', 'move updates file URI');
    assertBytes(await copy.bytes(), expected, 'move preserves contents');
    const copiedDirectory = new Directory(directory, 'nested-copy');
    new Directory(directory, 'nested').copy(copiedDirectory);
    assertValue(new File(copiedDirectory, 'empty.bin').exists, true, 'directory copy publishes its complete contents');
    copiedDirectory.rename('nested-renamed');
    copiedDirectory.move(new Directory(directory, 'nested-moved'));
    assertValue(new File(copiedDirectory, 'empty.bin').exists, true, 'directory rename and move preserve contents');
    assertValue(new File(directory, 'missing.bin').md5, null, 'missing file MD5');
    return {
      bytes: expected.length,
      consecutiveReads: true,
      eof: true,
      largeRequest: true,
      legacyRange: range,
      seek: true,
      intermediates: true,
      copyMoveRename: true,
    };
  } finally {
    if (directory.exists) directory.delete();
  }
}

/** The existing withAudioFixture plugin supplies audio/probe.wav in every Harmony demo build. */
export async function assertFileSystemRawDirectoryContracts(): Promise<Record<string, unknown>> {
  const results: Record<string, unknown>[] = [];
  for (const scheme of ['asset', 'rawfile']) {
    const directory = new Directory(`${scheme}:///audio`);
    assertValue(directory.exists, true, `${scheme} fixture directory exists`);
    const roundTrip = new Directory(directory.uri);
    assertValue(roundTrip.exists, true, `${scheme} directory URI round trip`);
    const info = roundTrip.info();
    const entries = roundTrip.list();
    const fixture = entries.find(entry => entry instanceof File && entry.name === 'probe.wav');
    if (!(fixture instanceof File)) throw new Error(`${scheme} directory list omitted the bundled WAV fixture.`);
    assertValue(info.files?.includes('probe.wav'), true, `${scheme} directory info entries`);
    assertValue(typeof roundTrip.size, 'number', `${scheme} directory size`);
    const bytes = await fixture.bytes();
    assertBytes(bytes.slice(0, 4), new Uint8Array([82, 73, 70, 70]), `${scheme} WAV fixture header`);
    if (bytes.length <= 44) throw new Error(`${scheme} fixture did not contain WAV sample data.`);
    results.push({ bytes: bytes.length, entries: entries.length, scheme, uri: roundTrip.uri });
  }
  return { resources: results };
}
