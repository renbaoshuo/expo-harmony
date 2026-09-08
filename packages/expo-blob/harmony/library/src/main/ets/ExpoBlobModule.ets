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

const BLOB_OPTIONS_TYPE = ExpoValueTypes.shapedRecord<BlobOptions>(
  'BlobOptions',
  new ExpoRecordShape().field('type', ExpoValueTypes.string().nullable().optional()).field(
    'endings',
    ExpoValueTypes.enumerable<EndingType>('EndingType', {
      transparent: EndingType.Transparent,
      native: EndingType.Native,
    })
      .nullable()
      .optional(),
  ),
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

class BlobObject extends ExpoSharedObject {
  private readonly parts: Uint8Array[];
  readonly size: number;
  readonly type: string;

  constructor(context: ExpoModuleContext, parts: Uint8Array[], type: string) {
    super(context);

    let size = 0;
    for (const part of parts) {
      if (part.byteLength > Number.MAX_SAFE_INTEGER - size) {
        throw new RangeError('Blob size exceeds the safe integer range.');
      }
      size += part.byteLength;
    }

    this.parts = parts;
    this.size = size;
    this.type = normalizeContentType(type);
  }

  static fromParts(context: ExpoModuleContext, input: BlobPart[], options: BlobOptions): BlobObject {
    const parts: Uint8Array[] = [];

    for (const part of input) {
      if (part.first !== undefined) {
        const text = options.endings === EndingType.Native ? part.first.replace(/\r\n|\r/g, '\n') : part.first;

        // Harmony's encodeInto('') may return undefined despite its declared type.
        if (text.length > 0) parts.push(new util.TextEncoder('utf-8').encodeInto(text));
      } else if (part.second !== undefined) {
        for (const bytes of part.second.parts) parts.push(bytes);
      } else {
        const view = part.third as ExpoNumericTypedArray;
        if (view.byteLength > 0) {
          parts.push(new Uint8Array(new Uint8Array(view.buffer, view.byteOffset, view.byteLength)));
        }
      }
    }

    return new BlobObject(context, parts, options.type);
  }

  slice(start?: number | null, end?: number | null, type?: string | null): BlobObject {
    const from = start === undefined || start === null ? 0 : resolveSliceIndex(start, this.size);
    const to = end === undefined || end === null ? this.size : resolveSliceIndex(end, this.size);
    const parts: Uint8Array[] = [];

    if (from < to) {
      let offset = 0;
      for (const part of this.parts) {
        const next = offset + part.byteLength;
        if (next > from && offset < to) {
          const begin = Math.max(from - offset, 0);
          const stop = Math.min(to - offset, part.byteLength);

          // Copy partial parts so small slices cannot retain unreported backing memory.
          parts.push(begin === 0 && stop === part.byteLength ? part : part.slice(begin, stop));
        }

        offset = next;
        if (offset >= to) break;
      }
    }

    return new BlobObject(this.context, parts, type ?? '');
  }

  bytes(): Uint8Array {
    const bytes = new Uint8Array(this.size);
    let offset = 0;

    for (const part of this.parts) {
      bytes.set(part, offset);
      offset += part.byteLength;
    }

    return bytes;
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
          BLOB_OPTIONS_TYPE.nullable().optional(),
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
