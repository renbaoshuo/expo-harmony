/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoEitherOfThree,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoNumericTypedArray,
  ExpoRecordShape,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { util } from '@kit.ArkTS';

type BlobPart = ExpoEitherOfThree<string, BlobObject, ExpoNumericTypedArray>;

enum EndingType {
  Transparent = 'transparent',
  Native = 'native',
}

class BlobOptions {
  type: string = '';
  endings: EndingType = EndingType.Transparent;
}

const ENDING_TYPE_VALUES: Record<string, EndingType> = {
  'transparent': EndingType.Transparent,
  'native': EndingType.Native,
};

const OPTIONS = ExpoValueTypes.shapedRecord<BlobOptions>(
  'BlobOptions',
  new ExpoRecordShape()
    .field('type', ExpoValueTypes.string().nullable().optional())
    .field('endings', ExpoValueTypes.enumerable<EndingType>('EndingType', ENDING_TYPE_VALUES).nullable().optional()),
  (fields: Record<string, ESObject>): BlobOptions => {
    const options = new BlobOptions();
    options.type = (fields['type'] as string | undefined | null) ?? '';
    options.endings = (fields['endings'] as EndingType | undefined | null) ?? EndingType.Transparent;

    return options;
  },
  (options: BlobOptions): Record<string, ESObject> => {
    const fields: Record<string, ESObject> = {};
    fields['type'] = options.type;
    fields['endings'] = options.endings;

    return fields;
  },
);

type BlobDataPart = Uint8Array | BlobData;

class BlobDataCursor {
  index: number = 0;
  offset: number;
  readonly data: BlobData;

  constructor(data: BlobData, offset: number) {
    this.data = data;
    this.offset = offset;
  }
}

class BlobData {
  private readonly parts: BlobDataPart[];
  readonly size: number;

  constructor(parts: BlobDataPart[]) {
    let size = 0;

    for (const part of parts) {
      const length = part instanceof BlobData ? part.size : part.byteLength;
      if (length > Number.MAX_SAFE_INTEGER - size) {
        throw new RangeError('Blob size exceeds the safe integer range.');
      }

      size += length;
    }

    this.parts = parts;
    this.size = size;
  }

  slice(start: number, end: number): BlobData {
    if (start === 0 && end === this.size) return this;

    const parts: BlobDataPart[] = [];
    this.visitRange(start, end, (part: BlobDataPart, from: number, to: number): boolean => {
      if (part instanceof BlobData) {
        if (from !== 0 || to !== part.size) return false;
        parts.push(part);
      } else {
        // A short slice must not retain the original backing buffer.
        parts.push(from === 0 && to === part.byteLength ? part : part.slice(from, to));
      }
      return true;
    });

    return new BlobData(parts);
  }

  bytes(): Uint8Array {
    const bytes = new Uint8Array(this.size);
    let offset = 0;

    this.visitRange(0, this.size, (part: BlobDataPart): boolean => {
      if (part instanceof BlobData) return false;
      bytes.set(part, offset);
      offset += part.byteLength;

      return true;
    });

    return bytes;
  }

  private visitRange(start: number, end: number, visit: (part: BlobDataPart, start: number, end: number) => boolean): void {
    if (start >= end) return;

    // Keep nested data shared and traverse it without using the call stack.
    const stack: BlobDataCursor[] = [new BlobDataCursor(this, 0)];

    while (stack.length > 0) {
      const cursor = stack[stack.length - 1];
      if (cursor.index === cursor.data.parts.length || cursor.offset >= end) {
        stack.pop();
        continue;
      }

      const part = cursor.data.parts[cursor.index++];
      const offset = cursor.offset;
      const length = part instanceof BlobData ? part.size : part.byteLength;
      cursor.offset += length;
      if (cursor.offset <= start) continue;

      const handled = visit(part, Math.max(start - offset, 0), Math.min(end - offset, length));
      if (!handled && part instanceof BlobData) stack.push(new BlobDataCursor(part, offset));
    }
  }
}

class BlobObject extends ExpoSharedObject {
  private readonly data: BlobData;
  readonly type: string;

  constructor(context: ExpoModuleContext, data: BlobData, type: string) {
    super(context);
    this.data = data;
    this.type = normalizeContentType(type);
  }

  get size(): number {
    return this.data.size;
  }

  static fromParts(context: ExpoModuleContext, input: BlobPart[], options: BlobOptions): BlobObject {
    const parts: BlobDataPart[] = [];

    for (const part of input) {
      if (part.first !== undefined) {
        const text = options.endings === EndingType.Native ? part.first.replace(/\r\n|\r/g, '\n') : part.first;

        // Harmony's encodeInto('') may return undefined despite its declared type.
        if (text.length > 0) parts.push(new util.TextEncoder('utf-8').encodeInto(text));
      } else if (part.second !== undefined) {
        if (part.second.size > 0) parts.push(part.second.data);
      } else {
        const view = part.third as ExpoNumericTypedArray;

        if (view.byteLength > 0) {
          parts.push(new Uint8Array(new Uint8Array(view.buffer, view.byteOffset, view.byteLength)));
        }
      }
    }

    return new BlobObject(context, new BlobData(parts), options.type);
  }

  slice(start?: number | null, end?: number | null, type?: string | null): BlobObject {
    const from = start === undefined || start === null ? 0 : resolveSliceIndex(start, this.size);
    const to = end === undefined || end === null ? this.size : resolveSliceIndex(end, this.size);

    return new BlobObject(this.context, this.data.slice(from, to), type ?? '');
  }

  bytes(): Uint8Array {
    return this.data.bytes();
  }

  text(): string {
    if (this.size === 0) return '';

    // Harmony ignoreBOM=false retains U+FEFF, matching Expo's native decoders.
    return util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: false }).decodeToString(this.bytes());
  }

  override getAdditionalMemoryPressure(): number {
    return this.size;
  }
}

export class ExpoBlobModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    const definition = new ExpoSharedObjectClassDefinition<BlobObject>('Blob');
    const type = definition.valueType();
    const part = ExpoValueTypes.either3(ExpoValueTypes.string(), type, ExpoValueTypes.typedArray());

    definition
      .construct(
        ExpoFunction.ownedTyped2(
          ExpoValueTypes.array(part).nullable().optional(),
          OPTIONS.nullable().optional(),
          (context: ExpoModuleContext, parts?: BlobPart[] | null, options?: BlobOptions | null): BlobObject =>
            BlobObject.fromParts(context, parts ?? [], options ?? new BlobOptions()),
        ),
      )
      .property('size', ExpoValueTypes.number(), (blob: BlobObject): number => blob.size)
      .property('type', ExpoValueTypes.string(), (blob: BlobObject): string => blob.type)
      .syncFunction(
        'slice',
        ExpoFunction.ownedTyped3(
          ExpoValueTypes.number().nullable().optional(),
          ExpoValueTypes.number().nullable().optional(),
          ExpoValueTypes.string().nullable().optional(),
          (blob: BlobObject, start?: number | null, end?: number | null, type?: string | null): BlobObject =>
            definition.instance(blob.slice(start, end, type)),
        ).returns(type),
      )
      .asyncFunction(
        'bytes',
        ExpoFunction.ownedTyped0(async (blob: BlobObject): Promise<Uint8Array> => blob.bytes()).returns(ExpoValueTypes.uint8Array()),
      )
      .asyncFunction('text', ExpoFunction.ownedTyped0(async (blob: BlobObject): Promise<string> => blob.text()).returns(ExpoValueTypes.string()));

    return new ExpoModuleDefinition().name('ExpoBlob').sharedObjectClass(definition);
  }
}

function resolveSliceIndex(index: number, size: number): number {
  // The upstream API uses signed 32-bit indices (Kotlin Double.toInt semantics).
  const min = -0x80000000;
  const max = 0x7fffffff;
  const integer = Number.isNaN(index) ? 0 : Math.min(Math.max(Math.trunc(index), min), max);

  return integer < 0 ? Math.max(size + integer, 0) : Math.min(integer, size);
}

function normalizeContentType(type: string): string {
  return /[^\x20-\x7e]/.test(type) ? '' : type.toLowerCase();
}
