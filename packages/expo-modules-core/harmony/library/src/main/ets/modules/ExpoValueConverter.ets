import { url } from '@kit.ArkTS';
import { ExpoModuleError } from './ExpoModuleError';
import { defineExpoRecordValue, hasOwnExpoRecordKey } from './ExpoRecord';

export type ExpoFunction0<Result> = () => Result;
/** A weak callback invoked on its owning JS runtime. */
export type ExpoJavaScriptCallback = (...args: ESObject[]) => void;
export type ExpoFunction1<Argument0, Result> = (argument0: Argument0) => Result;
export type ExpoFunction2<Argument0, Argument1, Result> = (argument0: Argument0, argument1: Argument1) => Result;
export type ExpoFunction3<Argument0, Argument1, Argument2, Result> = (argument0: Argument0, argument1: Argument1, argument2: Argument2) => Result;
export type ExpoFunction4<Argument0, Argument1, Argument2, Argument3, Result> = (
  argument0: Argument0,
  argument1: Argument1,
  argument2: Argument2,
  argument3: Argument3,
) => Result;
export type ExpoFunction5<Argument0, Argument1, Argument2, Argument3, Argument4, Result> = (
  argument0: Argument0,
  argument1: Argument1,
  argument2: Argument2,
  argument3: Argument3,
  argument4: Argument4,
) => Result;
export type ExpoFunction6<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result> = (
  argument0: Argument0,
  argument1: Argument1,
  argument2: Argument2,
  argument3: Argument3,
  argument4: Argument4,
  argument5: Argument5,
) => Result;
export type ExpoFunction7<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result> = (
  argument0: Argument0,
  argument1: Argument1,
  argument2: Argument2,
  argument3: Argument3,
  argument4: Argument4,
  argument5: Argument5,
  argument6: Argument6,
) => Result;
export type ExpoFunction8<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result> = (
  argument0: Argument0,
  argument1: Argument1,
  argument2: Argument2,
  argument3: Argument3,
  argument4: Argument4,
  argument5: Argument5,
  argument6: Argument6,
  argument7: Argument7,
) => Result;
export type ExpoFunction9<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Argument8, Result> = (
  argument0: Argument0,
  argument1: Argument1,
  argument2: Argument2,
  argument3: Argument3,
  argument4: Argument4,
  argument5: Argument5,
  argument6: Argument6,
  argument7: Argument7,
  argument8: Argument8,
) => Result;

export type ExpoSyncFunctionBody =
  | ExpoFunction0<ESObject | void>
  | ExpoFunction1<ESObject, ESObject | void>
  | ExpoFunction2<ESObject, ESObject, ESObject | void>
  | ExpoFunction3<ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction4<ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction5<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction6<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction7<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction8<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction9<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>;

export type ExpoAsyncFunctionBody =
  | ExpoFunction0<Promise<ESObject | void>>
  | ExpoFunction1<ESObject, Promise<ESObject | void>>
  | ExpoFunction2<ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction3<ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction4<ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction5<ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction6<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction7<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction8<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction9<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>;

export type ExpoOwnedSyncFunctionBody<Owner> =
  | ExpoFunction1<Owner, ESObject | void>
  | ExpoFunction2<Owner, ESObject, ESObject | void>
  | ExpoFunction3<Owner, ESObject, ESObject, ESObject | void>
  | ExpoFunction4<Owner, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction5<Owner, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction6<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction7<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction8<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>
  | ExpoFunction9<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>;

export type ExpoOwnedAsyncFunctionBody<Owner> =
  | ExpoFunction1<Owner, Promise<ESObject | void>>
  | ExpoFunction2<Owner, ESObject, Promise<ESObject | void>>
  | ExpoFunction3<Owner, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction4<Owner, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction5<Owner, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction6<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction7<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction8<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
  | ExpoFunction9<Owner, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>;

export interface ExpoFunctionArityRange {
  readonly required: number;
  readonly maximum: number;
}

/** Function contract used by typed fixed-arity helpers. */
export class ExpoFunctionSpec<Body> {
  readonly body: Body;
  readonly rawRequiredArity: number;
  readonly rawMaximumArity: number;
  readonly padsWithUndefined: boolean;
  readonly argumentTypes: ExpoValueType<ESObject>[];
  private resultType?: ExpoValueType<ESObject> = undefined;

  constructor(
    body: Body,
    rawRequiredArity: number,
    rawMaximumArity: number,
    padsWithUndefined: boolean,
    argumentTypes: ExpoValueType<ESObject>[] = [],
  ) {
    this.body = body;
    this.rawRequiredArity = rawRequiredArity;
    this.rawMaximumArity = rawMaximumArity;
    this.padsWithUndefined = padsWithUndefined;
    this.argumentTypes = argumentTypes;
  }

  returns<Result>(type: ExpoValueType<Result>): ExpoFunctionSpec<Body> {
    this.resultType = type as ExpoValueType<ESObject>;
    return this;
  }

  /** @internal */
  resultTypeValue(): ExpoValueType<ESObject> | undefined {
    return this.resultType;
  }
}

/** Typed fixed-arity function helpers. */
export class ExpoFunction {
  static typed0<Result>(body: ExpoFunction0<Result>): ExpoFunctionSpec<ExpoFunction0<Result>> {
    return typedFunctionSpec(body, [], 0);
  }

  static typed1<Argument0, Result>(
    argument0: ExpoValueType<Argument0>,
    body: ExpoFunction1<Argument0, Result>,
  ): ExpoFunctionSpec<ExpoFunction1<Argument0, Result>> {
    return typedFunctionSpec(body, [argument0 as ExpoValueType<ESObject>], 0);
  }

  static typed2<Argument0, Argument1, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    body: ExpoFunction2<Argument0, Argument1, Result>,
  ): ExpoFunctionSpec<ExpoFunction2<Argument0, Argument1, Result>> {
    return typedFunctionSpec(body, [argument0 as ExpoValueType<ESObject>, argument1 as ExpoValueType<ESObject>], 0);
  }

  static typed3<Argument0, Argument1, Argument2, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    body: ExpoFunction3<Argument0, Argument1, Argument2, Result>,
  ): ExpoFunctionSpec<ExpoFunction3<Argument0, Argument1, Argument2, Result>> {
    return typedFunctionSpec(
      body,
      [argument0 as ExpoValueType<ESObject>, argument1 as ExpoValueType<ESObject>, argument2 as ExpoValueType<ESObject>],
      0,
    );
  }

  static typed4<Argument0, Argument1, Argument2, Argument3, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    body: ExpoFunction4<Argument0, Argument1, Argument2, Argument3, Result>,
  ): ExpoFunctionSpec<ExpoFunction4<Argument0, Argument1, Argument2, Argument3, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
      ],
      0,
    );
  }

  static typed5<Argument0, Argument1, Argument2, Argument3, Argument4, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    body: ExpoFunction5<Argument0, Argument1, Argument2, Argument3, Argument4, Result>,
  ): ExpoFunctionSpec<ExpoFunction5<Argument0, Argument1, Argument2, Argument3, Argument4, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
      ],
      0,
    );
  }

  static typed6<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    argument5: ExpoValueType<Argument5>,
    body: ExpoFunction6<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result>,
  ): ExpoFunctionSpec<ExpoFunction6<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
        argument5 as ExpoValueType<ESObject>,
      ],
      0,
    );
  }

  static typed7<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    argument5: ExpoValueType<Argument5>,
    argument6: ExpoValueType<Argument6>,
    body: ExpoFunction7<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result>,
  ): ExpoFunctionSpec<ExpoFunction7<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
        argument5 as ExpoValueType<ESObject>,
        argument6 as ExpoValueType<ESObject>,
      ],
      0,
    );
  }

  static typed8<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    argument5: ExpoValueType<Argument5>,
    argument6: ExpoValueType<Argument6>,
    argument7: ExpoValueType<Argument7>,
    body: ExpoFunction8<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result>,
  ): ExpoFunctionSpec<ExpoFunction8<Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
        argument5 as ExpoValueType<ESObject>,
        argument6 as ExpoValueType<ESObject>,
        argument7 as ExpoValueType<ESObject>,
      ],
      0,
    );
  }

  static ownedTyped0<Owner, Result>(body: ExpoFunction1<Owner, Result>): ExpoFunctionSpec<ExpoFunction1<Owner, Result>> {
    return typedFunctionSpec(body, [], 1);
  }

  static ownedTyped1<Owner, Argument0, Result>(
    argument0: ExpoValueType<Argument0>,
    body: ExpoFunction2<Owner, Argument0, Result>,
  ): ExpoFunctionSpec<ExpoFunction2<Owner, Argument0, Result>> {
    return typedFunctionSpec(body, [argument0 as ExpoValueType<ESObject>], 1);
  }

  static ownedTyped2<Owner, Argument0, Argument1, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    body: ExpoFunction3<Owner, Argument0, Argument1, Result>,
  ): ExpoFunctionSpec<ExpoFunction3<Owner, Argument0, Argument1, Result>> {
    return typedFunctionSpec(body, [argument0 as ExpoValueType<ESObject>, argument1 as ExpoValueType<ESObject>], 1);
  }

  static ownedTyped3<Owner, Argument0, Argument1, Argument2, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    body: ExpoFunction4<Owner, Argument0, Argument1, Argument2, Result>,
  ): ExpoFunctionSpec<ExpoFunction4<Owner, Argument0, Argument1, Argument2, Result>> {
    return typedFunctionSpec(
      body,
      [argument0 as ExpoValueType<ESObject>, argument1 as ExpoValueType<ESObject>, argument2 as ExpoValueType<ESObject>],
      1,
    );
  }

  static ownedTyped4<Owner, Argument0, Argument1, Argument2, Argument3, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    body: ExpoFunction5<Owner, Argument0, Argument1, Argument2, Argument3, Result>,
  ): ExpoFunctionSpec<ExpoFunction5<Owner, Argument0, Argument1, Argument2, Argument3, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
      ],
      1,
    );
  }

  static ownedTyped5<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    body: ExpoFunction6<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Result>,
  ): ExpoFunctionSpec<ExpoFunction6<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
      ],
      1,
    );
  }

  static ownedTyped6<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    argument5: ExpoValueType<Argument5>,
    body: ExpoFunction7<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result>,
  ): ExpoFunctionSpec<ExpoFunction7<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
        argument5 as ExpoValueType<ESObject>,
      ],
      1,
    );
  }

  static ownedTyped7<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    argument5: ExpoValueType<Argument5>,
    argument6: ExpoValueType<Argument6>,
    body: ExpoFunction8<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result>,
  ): ExpoFunctionSpec<ExpoFunction8<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
        argument5 as ExpoValueType<ESObject>,
        argument6 as ExpoValueType<ESObject>,
      ],
      1,
    );
  }

  static ownedTyped8<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result>(
    argument0: ExpoValueType<Argument0>,
    argument1: ExpoValueType<Argument1>,
    argument2: ExpoValueType<Argument2>,
    argument3: ExpoValueType<Argument3>,
    argument4: ExpoValueType<Argument4>,
    argument5: ExpoValueType<Argument5>,
    argument6: ExpoValueType<Argument6>,
    argument7: ExpoValueType<Argument7>,
    body: ExpoFunction9<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result>,
  ): ExpoFunctionSpec<ExpoFunction9<Owner, Argument0, Argument1, Argument2, Argument3, Argument4, Argument5, Argument6, Argument7, Result>> {
    return typedFunctionSpec(
      body,
      [
        argument0 as ExpoValueType<ESObject>,
        argument1 as ExpoValueType<ESObject>,
        argument2 as ExpoValueType<ESObject>,
        argument3 as ExpoValueType<ESObject>,
        argument4 as ExpoValueType<ESObject>,
        argument5 as ExpoValueType<ESObject>,
        argument6 as ExpoValueType<ESObject>,
        argument7 as ExpoValueType<ESObject>,
      ],
      1,
    );
  }
}

export type ExpoSyncFunction = ExpoFunction0<ESObject | void> | ExpoFunctionSpec<ExpoSyncFunctionBody>;
export type ExpoAsyncFunction = ExpoFunction0<Promise<ESObject | void>> | ExpoFunctionSpec<ExpoAsyncFunctionBody>;
export type ExpoOwnedSyncFunction<Owner> = ExpoFunction1<Owner, ESObject | void> | ExpoFunctionSpec<ExpoOwnedSyncFunctionBody<Owner>>;
export type ExpoOwnedAsyncFunction<Owner> = ExpoFunction1<Owner, Promise<ESObject | void>> | ExpoFunctionSpec<ExpoOwnedAsyncFunctionBody<Owner>>;

const MAX_VALUE_DEPTH: number = 64;

/** Decoder used by reusable author-defined value types. */
export type ExpoValueDecoder<Value> = (value: ESObject, path: string) => Value;
/** Encoder used by reusable author-defined value types. */
export type ExpoValueEncoder<Value> = (value: Value, path: string) => ESObject | void;

/** Runtime type token for values with erased ArkTS generics. */
export class ExpoValueType<Value> {
  readonly expectedType: string;
  readonly acceptsUndefined: boolean;
  /** Whether a trailing function argument using this token may be omitted. */
  readonly isOmittable: boolean;
  /** Explicit copy-back contract for a synchronous module binary argument. */
  readonly isWritable: boolean;
  private readonly decoder: ExpoValueDecoder<Value>;
  private readonly encoder: ExpoValueEncoder<Value>;

  constructor(
    expectedType: string,
    decoder: ExpoValueDecoder<Value>,
    encoder: ExpoValueEncoder<Value>,
    acceptsUndefined: boolean = false,
    isOmittable: boolean = false,
    isWritable: boolean = false,
  ) {
    this.expectedType = expectedType;
    this.decoder = decoder;
    this.encoder = encoder;
    this.acceptsUndefined = acceptsUndefined;
    this.isOmittable = isOmittable;
    this.isWritable = isWritable;
  }

  /** @internal */
  decode(value: ESObject, path: string): Value {
    return this.decoder(value, path);
  }

  /** @internal */
  encode(value: Value, path: string): ESObject | void {
    return this.encoder(value, path);
  }

  /**
   * Writes the original binary argument's native snapshot back after a successful
   * synchronous module call. Decoders may wrap its storage, but must not copy it.
   * Argument encoders do not participate in write-back.
   */
  writable(): ExpoValueType<Value> {
    return new ExpoValueType<Value>(this.expectedType, this.decoder, this.encoder, this.acceptsUndefined, this.isOmittable, true);
  }

  optional(): ExpoValueType<Value | undefined> {
    return new ExpoValueType<Value | undefined>(
      `${this.expectedType} or undefined`,
      (value: ESObject, path: string): Value | undefined => {
        if (value === undefined) return undefined;
        return this.decode(value, path);
      },
      (value: Value | undefined, path: string): ESObject | void => {
        if (value === undefined) return undefined;
        return this.encode(value, path);
      },
      true,
      true,
      this.isWritable,
    );
  }

  defaulted(defaultValue: Value): ExpoValueType<Value> {
    return new ExpoValueType<Value>(
      `${this.expectedType} or undefined`,
      (value: ESObject, path: string): Value => (value === undefined ? defaultValue : this.decode(value, path)),
      (value: Value, path: string): ESObject | void => this.encode(value, path),
      true,
      true,
      this.isWritable,
    );
  }

  nullable(): ExpoValueType<Value | null> {
    return new ExpoValueType<Value | null>(
      `${this.expectedType} or null`,
      (value: ESObject, path: string): Value | null => {
        if (value === null) return null;
        return this.decode(value, path);
      },
      (value: Value | null, path: string): ESObject | void => {
        if (value === null) return null;
        return this.encode(value, path);
      },
      false,
      false,
      this.isWritable,
    );
  }

  /** Accepts either this value type or another one. */
  or<Other>(other: ExpoValueType<Other>): ExpoValueType<Value | Other> {
    return new ExpoValueType<Value | Other>(
      `${this.expectedType} or ${other.expectedType}`,
      (value: ESObject, path: string): Value | Other => {
        try {
          return this.decode(value, path);
        } catch (_) {
          try {
            return other.decode(value, path);
          } catch (_) {
            throw new ExpoArgumentTypeError(path, `${this.expectedType} or ${other.expectedType}`, value);
          }
        }
      },
      (value: Value | Other, path: string): ESObject | void => {
        try {
          return this.encode(value as Value, path);
        } catch (_) {
          try {
            return other.encode(value as Other, path);
          } catch (_) {
            throw new ExpoModuleError(
              'ERR_INVALID_RETURN_VALUE',
              `${path} expected ${this.expectedType} or ${other.expectedType}, received ${ExpoValueConverter.actualType(value as ESObject)}.`,
            );
          }
        }
      },
      this.acceptsUndefined || other.acceptsUndefined,
      false,
      this.isWritable || other.isWritable,
    );
  }
}

/** Distinguishes JavaScript `undefined` from a present nullable value. */
export class ExpoValueOrUndefined<Value> {
  readonly isUndefined: boolean;
  readonly value?: Value;

  private constructor(isUndefined: boolean, value?: Value) {
    this.isUndefined = isUndefined;
    this.value = value;
  }

  static undefined<Value>(): ExpoValueOrUndefined<Value> {
    return new ExpoValueOrUndefined<Value>(true);
  }

  static value<Value>(value: Value): ExpoValueOrUndefined<Value> {
    return new ExpoValueOrUndefined<Value>(false, value);
  }
}

/** Typed union result matching Expo's Either conversion semantics. */
export class ExpoEither<First, Second> {
  readonly first?: First;
  readonly second?: Second;
  readonly isFirst: boolean;

  private constructor(isFirst: boolean, first?: First, second?: Second) {
    this.isFirst = isFirst;
    this.first = first;
    this.second = second;
  }

  static first<First, Second>(value: First): ExpoEither<First, Second> {
    return new ExpoEither<First, Second>(true, value);
  }

  static second<First, Second>(value: Second): ExpoEither<First, Second> {
    return new ExpoEither<First, Second>(false, undefined, value);
  }
}

/** Three-way counterpart to Expo's `EitherOfThree`. */
export class ExpoEitherOfThree<First, Second, Third> {
  readonly first?: First;
  readonly second?: Second;
  readonly third?: Third;
  readonly branch: number;

  private constructor(branch: number, first?: First, second?: Second, third?: Third) {
    this.branch = branch;
    this.first = first;
    this.second = second;
    this.third = third;
  }

  static first<First, Second, Third>(value: First): ExpoEitherOfThree<First, Second, Third> {
    return new ExpoEitherOfThree<First, Second, Third>(0, value);
  }

  static second<First, Second, Third>(value: Second): ExpoEitherOfThree<First, Second, Third> {
    return new ExpoEitherOfThree<First, Second, Third>(1, undefined, value);
  }

  static third<First, Second, Third>(value: Third): ExpoEitherOfThree<First, Second, Third> {
    return new ExpoEitherOfThree<First, Second, Third>(2, undefined, undefined, value);
  }
}

/** Four-way counterpart to Expo's `EitherOfFour`. */
export class ExpoEitherOfFour<First, Second, Third, Fourth> {
  readonly first?: First;
  readonly second?: Second;
  readonly third?: Third;
  readonly fourth?: Fourth;
  readonly branch: number;

  private constructor(branch: number, first?: First, second?: Second, third?: Third, fourth?: Fourth) {
    this.branch = branch;
    this.first = first;
    this.second = second;
    this.third = third;
    this.fourth = fourth;
  }

  static first<First, Second, Third, Fourth>(value: First): ExpoEitherOfFour<First, Second, Third, Fourth> {
    return new ExpoEitherOfFour<First, Second, Third, Fourth>(0, value);
  }

  static second<First, Second, Third, Fourth>(value: Second): ExpoEitherOfFour<First, Second, Third, Fourth> {
    return new ExpoEitherOfFour<First, Second, Third, Fourth>(1, undefined, value);
  }

  static third<First, Second, Third, Fourth>(value: Third): ExpoEitherOfFour<First, Second, Third, Fourth> {
    return new ExpoEitherOfFour<First, Second, Third, Fourth>(2, undefined, undefined, value);
  }

  static fourth<First, Second, Third, Fourth>(value: Fourth): ExpoEitherOfFour<First, Second, Third, Fourth> {
    return new ExpoEitherOfFour<First, Second, Third, Fourth>(3, undefined, undefined, undefined, value);
  }
}

class ExpoRecordField {
  readonly name: string;
  readonly type: ExpoValueType<ESObject>;

  constructor(name: string, type: ExpoValueType<ESObject>) {
    this.name = name;
    this.type = type;
  }
}

/** Runtime field schema for ArkTS records and classes. */
export class ExpoRecordShape {
  private readonly fields: Map<string, ExpoValueType<ESObject>> = new Map<string, ExpoValueType<ESObject>>();

  field<Value>(name: string, type: ExpoValueType<Value>): ExpoRecordShape {
    if (name.length === 0) throw new Error('Expo record field names cannot be empty.');
    if (this.fields.has(name)) throw new Error(`Expo record field '${name}' was declared more than once.`);
    this.fields.set(name, type as ExpoValueType<ESObject>);
    return this;
  }

  /** @internal */
  fieldValues(): ExpoRecordField[] {
    const values: ExpoRecordField[] = [];
    this.fields.forEach((type: ExpoValueType<ESObject>, name: string): void => {
      values.push(new ExpoRecordField(name, type));
    });
    return values;
  }
}

/** Numeric JavaScript TypedArrays preserved by the Core bridge. */
export type ExpoNumericTypedArray =
  | Int8Array
  | Uint8Array
  | Uint8ClampedArray
  | Int16Array
  | Uint16Array
  | Int32Array
  | Uint32Array
  | Float32Array
  | Float64Array
  | BigInt64Array
  | BigUint64Array;

/** Common reusable type tokens. */
export class ExpoValueTypes {
  static callback(): ExpoValueType<ExpoJavaScriptCallback> {
    return new ExpoValueType<ExpoJavaScriptCallback>(
      'JavaScript callback',
      (value: ESObject, path: string): ExpoJavaScriptCallback => {
        if (typeof value !== 'function') {
          throw new ExpoArgumentTypeError(path, 'JavaScript callback', value);
        }
        return value as ExpoJavaScriptCallback;
      },
      (_value: ExpoJavaScriptCallback, path: string): ESObject => {
        throw new ExpoModuleError('ERR_INVALID_RETURN_VALUE', `${path} cannot return an ArkTS function to JavaScript.`, undefined, path);
      },
    );
  }

  /** Reusable custom conversion boundary for platform/domain-specific values. */
  static custom<Value>(expectedType: string, decoder: ExpoValueDecoder<Value>, encoder: ExpoValueEncoder<Value>): ExpoValueType<Value> {
    if (expectedType.length === 0) throw new Error('Expo custom value type names cannot be empty.');
    return new ExpoValueType<Value>(expectedType, decoder, encoder);
  }

  /** Validates a shaped record and constructs the author value. */
  static shapedRecord<Value>(
    name: string,
    shape: ExpoRecordShape,
    decoder: (fields: Record<string, ESObject>) => Value,
    encoder: (value: Value) => Record<string, ESObject>,
  ): ExpoValueType<Value> {
    const fields: ExpoRecordField[] = shape.fieldValues();
    return new ExpoValueType<Value>(
      name,
      (value: ESObject, path: string): Value => {
        if (!isRecordValue(value)) throw new ExpoArgumentTypeError(path, name, value);

        const input = value as Record<string, ESObject>;
        const decoded: Record<string, ESObject> = {};

        fields.forEach((field: ExpoRecordField): void => {
          const fieldValue: ESObject = hasOwnExpoRecordKey(input, field.name) ? input[field.name] : undefined;
          defineExpoRecordValue(decoded, field.name, field.type.decode(fieldValue, `${path}.${field.name}`));
        });

        return decoder(decoded);
      },
      (value: Value, path: string): ESObject => {
        const input: Record<string, ESObject> = encoder(value);
        if (!isRecordValue(input)) throw new ExpoArgumentTypeError(path, name, input);

        const encoded: Record<string, ESObject> = {};

        fields.forEach((field: ExpoRecordField): void => {
          const fieldValue: ESObject = hasOwnExpoRecordKey(input, field.name) ? input[field.name] : undefined;
          defineExpoRecordValue(encoded, field.name, field.type.encode(fieldValue, `${path}.${field.name}`) as ESObject);
        });

        return encoded;
      },
    );
  }

  static boolean(): ExpoValueType<boolean> {
    return primitiveType<boolean>('boolean', 'boolean');
  }

  static number(): ExpoValueType<number> {
    return new ExpoValueType<number>(
      'number',
      (value: ESObject, path: string): number => requireNumber(value, path),
      (value: number, path: string): ESObject => requireNumber(value, path),
    );
  }

  static string(): ExpoValueType<string> {
    return primitiveType<string>('string', 'string');
  }

  static array<Value>(element: ExpoValueType<Value>): ExpoValueType<Value[]> {
    return new ExpoValueType<Value[]>(
      `array of ${element.expectedType}`,
      (value: ESObject, path: string): Value[] => {
        if (!Array.isArray(value)) throw new ExpoArgumentTypeError(path, `array of ${element.expectedType}`, value);
        return value.map((item: ESObject, index: number): Value => element.decode(item, `${path}[${index}]`));
      },
      (value: Value[], path: string): ESObject =>
        value.map((item: Value, index: number): ESObject => element.encode(item, `${path}[${index}]`) as ESObject),
    );
  }

  static record<Value>(valueType: ExpoValueType<Value>): ExpoValueType<Record<string, Value>> {
    return new ExpoValueType<Record<string, Value>>(
      `record of ${valueType.expectedType}`,
      (value: ESObject, path: string): Record<string, Value> => {
        if (!isRecordValue(value)) throw new ExpoArgumentTypeError(path, `record of ${valueType.expectedType}`, value);

        const input = value as Record<string, ESObject>;
        const output: Record<string, Value> = {};

        Object.keys(input).forEach((key: string): void => {
          defineExpoRecordValue(output, key, valueType.decode(input[key], `${path}.${key}`));
        });

        return output;
      },
      (value: Record<string, Value>, path: string): ESObject => {
        if (!isRecordValue(value as ESObject)) {
          throw new ExpoArgumentTypeError(path, `record of ${valueType.expectedType}`, value as ESObject);
        }

        const output: Record<string, ESObject> = {};

        Object.keys(value).forEach((key: string): void => {
          defineExpoRecordValue(output, key, valueType.encode(value[key], `${path}.${key}`) as ESObject);
        });

        return output;
      },
    );
  }

  static valueOrUndefined<Value>(inner: ExpoValueType<Value>): ExpoValueType<ExpoValueOrUndefined<Value>> {
    return new ExpoValueType<ExpoValueOrUndefined<Value>>(
      `${inner.expectedType} or undefined`,
      (value: ESObject, path: string): ExpoValueOrUndefined<Value> =>
        value === undefined ? ExpoValueOrUndefined.undefined<Value>() : ExpoValueOrUndefined.value<Value>(inner.decode(value, path)),
      (value: ExpoValueOrUndefined<Value>, path: string): ESObject | void =>
        value.isUndefined ? undefined : inner.encode(value.value as Value, path),
      true,
    );
  }

  static either<First, Second>(first: ExpoValueType<First>, second: ExpoValueType<Second>): ExpoValueType<ExpoEither<First, Second>> {
    return new ExpoValueType<ExpoEither<First, Second>>(
      `${first.expectedType} or ${second.expectedType}`,
      (value: ESObject, path: string): ExpoEither<First, Second> => {
        try {
          return ExpoEither.first<First, Second>(first.decode(value, path));
        } catch (_) {
          try {
            return ExpoEither.second<First, Second>(second.decode(value, path));
          } catch (_) {
            throw new ExpoArgumentTypeError(path, `${first.expectedType} or ${second.expectedType}`, value);
          }
        }
      },
      (value: ExpoEither<First, Second>, path: string): ESObject | void =>
        value.isFirst ? first.encode(value.first as First, path) : second.encode(value.second as Second, path),
      first.acceptsUndefined || second.acceptsUndefined,
    );
  }

  static either3<First, Second, Third>(
    first: ExpoValueType<First>,
    second: ExpoValueType<Second>,
    third: ExpoValueType<Third>,
  ): ExpoValueType<ExpoEitherOfThree<First, Second, Third>> {
    const expected: string = `${first.expectedType}, ${second.expectedType}, or ${third.expectedType}`;
    return new ExpoValueType<ExpoEitherOfThree<First, Second, Third>>(
      expected,
      (value: ESObject, path: string): ExpoEitherOfThree<First, Second, Third> => {
        try {
          return ExpoEitherOfThree.first<First, Second, Third>(first.decode(value, path));
        } catch (_) {
          try {
            return ExpoEitherOfThree.second<First, Second, Third>(second.decode(value, path));
          } catch (_) {
            try {
              return ExpoEitherOfThree.third<First, Second, Third>(third.decode(value, path));
            } catch (_) {
              throw new ExpoArgumentTypeError(path, expected, value);
            }
          }
        }
      },
      (value: ExpoEitherOfThree<First, Second, Third>, path: string): ESObject | void => {
        if (value.branch === 0) return first.encode(value.first as First, path);
        if (value.branch === 1) return second.encode(value.second as Second, path);
        if (value.branch === 2) return third.encode(value.third as Third, path);
        throw new ExpoModuleError('ERR_INVALID_RETURN_VALUE', `${path} returned an invalid EitherOfThree branch.`);
      },
      first.acceptsUndefined || second.acceptsUndefined || third.acceptsUndefined,
    );
  }

  static either4<First, Second, Third, Fourth>(
    first: ExpoValueType<First>,
    second: ExpoValueType<Second>,
    third: ExpoValueType<Third>,
    fourth: ExpoValueType<Fourth>,
  ): ExpoValueType<ExpoEitherOfFour<First, Second, Third, Fourth>> {
    const expected: string = `${first.expectedType}, ${second.expectedType}, ${third.expectedType}, or ${fourth.expectedType}`;
    return new ExpoValueType<ExpoEitherOfFour<First, Second, Third, Fourth>>(
      expected,
      (value: ESObject, path: string): ExpoEitherOfFour<First, Second, Third, Fourth> => {
        try {
          return ExpoEitherOfFour.first<First, Second, Third, Fourth>(first.decode(value, path));
        } catch (_) {
          try {
            return ExpoEitherOfFour.second<First, Second, Third, Fourth>(second.decode(value, path));
          } catch (_) {
            try {
              return ExpoEitherOfFour.third<First, Second, Third, Fourth>(third.decode(value, path));
            } catch (_) {
              try {
                return ExpoEitherOfFour.fourth<First, Second, Third, Fourth>(fourth.decode(value, path));
              } catch (_) {
                throw new ExpoArgumentTypeError(path, expected, value);
              }
            }
          }
        }
      },
      (value: ExpoEitherOfFour<First, Second, Third, Fourth>, path: string): ESObject | void => {
        if (value.branch === 0) return first.encode(value.first as First, path);
        if (value.branch === 1) return second.encode(value.second as Second, path);
        if (value.branch === 2) return third.encode(value.third as Third, path);
        if (value.branch === 3) return fourth.encode(value.fourth as Fourth, path);
        throw new ExpoModuleError('ERR_INVALID_RETURN_VALUE', `${path} returned an invalid EitherOfFour branch.`);
      },
      first.acceptsUndefined || second.acceptsUndefined || third.acceptsUndefined || fourth.acceptsUndefined,
    );
  }

  static enumerable<Value>(name: string, values: Record<string, Value>): ExpoValueType<Value> {
    return new ExpoValueType<Value>(
      name,
      (value: ESObject, path: string): Value => {
        if (typeof value !== 'string' || !Object.keys(values).includes(value)) {
          throw new ExpoArgumentTypeError(path, name, value);
        }
        return values[value];
      },
      (value: Value, path: string): ESObject => {
        const keys: string[] = Object.keys(values);
        for (let index = 0; index < keys.length; index += 1) {
          if (values[keys[index]] === value) return keys[index];
        }
        throw new ExpoModuleError('ERR_INVALID_RETURN_VALUE', `${path} returned an unknown ${name} value.`);
      },
    );
  }

  static date(): ExpoValueType<Date> {
    return new ExpoValueType<Date>(
      'Date epoch milliseconds or ISO-8601 string',
      (value: ESObject, path: string): Date => decodeDate(value, path),
      (value: Date): ESObject => value.getTime(),
    );
  }

  static uri(): ExpoValueType<url.URL> {
    return new ExpoValueType<url.URL>(
      'URL string',
      (value: ESObject, path: string): url.URL => {
        if (typeof value !== 'string') throw new ExpoArgumentTypeError(path, 'URL string', value);
        return url.URL.parseURL(value);
      },
      (value: url.URL): ESObject => value.toString(),
    );
  }

  static arrayBuffer(): ExpoValueType<ArrayBuffer> {
    return new ExpoValueType<ArrayBuffer>(
      'ArrayBuffer',
      (value: ESObject, path: string): ArrayBuffer => {
        if (!(value instanceof ArrayBuffer)) throw new ExpoArgumentTypeError(path, 'ArrayBuffer', value);
        return value;
      },
      (value: ArrayBuffer, path: string): ESObject => {
        if (!(value instanceof ArrayBuffer)) throw new ExpoArgumentTypeError(path, 'ArrayBuffer', value);
        return value as ESObject;
      },
    );
  }

  static typedArray(): ExpoValueType<ExpoNumericTypedArray> {
    return numericTypedArrayType<ExpoNumericTypedArray>('numeric TypedArray', (value: ESObject): boolean => isNumericTypedArray(value));
  }

  static int8Array(): ExpoValueType<Int8Array> {
    return numericTypedArrayType<Int8Array>('Int8Array', (value: ESObject): boolean => value instanceof Int8Array);
  }

  static uint8Array(): ExpoValueType<Uint8Array> {
    return numericTypedArrayType<Uint8Array>('Uint8Array', (value: ESObject): boolean => value instanceof Uint8Array);
  }

  static uint8ClampedArray(): ExpoValueType<Uint8ClampedArray> {
    return numericTypedArrayType<Uint8ClampedArray>('Uint8ClampedArray', (value: ESObject): boolean => value instanceof Uint8ClampedArray);
  }

  static int16Array(): ExpoValueType<Int16Array> {
    return numericTypedArrayType<Int16Array>('Int16Array', (value: ESObject): boolean => value instanceof Int16Array);
  }

  static uint16Array(): ExpoValueType<Uint16Array> {
    return numericTypedArrayType<Uint16Array>('Uint16Array', (value: ESObject): boolean => value instanceof Uint16Array);
  }

  static int32Array(): ExpoValueType<Int32Array> {
    return numericTypedArrayType<Int32Array>('Int32Array', (value: ESObject): boolean => value instanceof Int32Array);
  }

  static uint32Array(): ExpoValueType<Uint32Array> {
    return numericTypedArrayType<Uint32Array>('Uint32Array', (value: ESObject): boolean => value instanceof Uint32Array);
  }

  static float32Array(): ExpoValueType<Float32Array> {
    return numericTypedArrayType<Float32Array>('Float32Array', (value: ESObject): boolean => value instanceof Float32Array);
  }

  static float64Array(): ExpoValueType<Float64Array> {
    return numericTypedArrayType<Float64Array>('Float64Array', (value: ESObject): boolean => value instanceof Float64Array);
  }

  static bigInt64Array(): ExpoValueType<BigInt64Array> {
    return numericTypedArrayType<BigInt64Array>('BigInt64Array', (value: ESObject): boolean => value instanceof BigInt64Array);
  }

  static bigUint64Array(): ExpoValueType<BigUint64Array> {
    return numericTypedArrayType<BigUint64Array>('BigUint64Array', (value: ESObject): boolean => value instanceof BigUint64Array);
  }
}

/** Converts values across the common JS/ArkTS boundary. */
export class ExpoValueConverter {
  static fromBridge<Value>(value: ESObject, type?: ExpoValueType<Value>, path: string = 'value'): Value {
    if (type !== undefined) {
      try {
        return type.decode(value, path);
      } catch (error) {
        if (error instanceof ExpoModuleError) {
          throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
        }

        throw new ExpoModuleError(
          'ERR_INVALID_ARGUMENT_TYPE',
          `${path} expected ${type.expectedType}, received ${ExpoValueConverter.actualType(value)}.`,
        );
      }
    }

    validateCopyValue(value, path, 0);

    return value as Value;
  }

  static toBridge<Value>(value: Value, type?: ExpoValueType<Value>, path: string = 'return value'): ESObject | void {
    if (type !== undefined) {
      try {
        return type.encode(value, path);
      } catch (error) {
        if (error instanceof ExpoModuleError) {
          if (error.code !== 'ERR_INVALID_ARGUMENT_TYPE') {
            throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
          }

          throw new ExpoModuleError('ERR_INVALID_RETURN_VALUE', error.message);
        }

        throw new ExpoModuleError(
          'ERR_INVALID_RETURN_VALUE',
          `${path} expected ${type.expectedType}, received ${ExpoValueConverter.actualType(value as ESObject)}.`,
        );
      }
    }

    const bridgeValue: ESObject = value as ESObject;

    validateCopyValue(bridgeValue, path, 0);

    return bridgeValue;
  }

  static actualType(value: ESObject): string {
    if (value === undefined) return 'undefined';
    if (value === null) return 'null';
    if (Array.isArray(value)) return 'array';
    if (value instanceof ArrayBuffer) return 'ArrayBuffer';
    const typedArrayName: string | undefined = numericTypedArrayName(value);
    if (typedArrayName !== undefined) return typedArrayName;
    if (ArrayBuffer.isView(value)) return 'non-numeric ArrayBuffer view';
    if (value instanceof Date) return 'Date';
    if (value instanceof url.URL) return 'URL';
    return typeof value;
  }
}

export function functionArity(body: ExpoSyncFunction | ExpoAsyncFunction): ExpoFunctionArityRange {
  return functionArityWithOwner(body, 0);
}

export function ownedFunctionArity<Owner>(body: ExpoOwnedSyncFunction<Owner> | ExpoOwnedAsyncFunction<Owner>): ExpoFunctionArityRange {
  return functionArityWithOwner(body, 1);
}

/** @internal Writable argument positions in the module transport descriptor. */
export function writableFunctionArguments<Body>(body: Body | ExpoFunctionSpec<Body>): number[] {
  if (!(body instanceof ExpoFunctionSpec)) return [];
  const indices: number[] = [];
  body.argumentTypes.forEach((type: ExpoValueType<ESObject>, index: number): void => {
    if (!type.isWritable) return;
    if (type.acceptsUndefined || type.isOmittable) {
      throw new ExpoModuleError('ERR_WRITABLE_ARGUMENT', 'Writable binary arguments must be required.');
    }
    indices.push(index);
  });
  return indices;
}

function writableBinaryLength(value: ESObject, path: string): number {
  if (!(value instanceof ArrayBuffer) && !isNumericTypedArray(value)) {
    throw new ExpoArgumentTypeError(path, 'writable ArrayBuffer or numeric TypedArray', value);
  }
  return (value as ArrayBuffer).byteLength;
}

export function invokeSyncFunction(body: ExpoSyncFunction, args: ESObject[], path: string = 'Expo function'): ESObject | void {
  writableFunctionArguments(body).forEach((index: number): void => {
    writableBinaryLength(args[index], `${path} argument ${index + 1}`);
  });
  const values: ESObject[] = prepareArguments(body, args, 0, path);
  const result: ESObject | void = invokeRawSyncFunction(unwrapSyncFunction(body), values);
  return encodeFunctionResult(body, result, `${path} return value`);
}

function invokeRawSyncFunction(body: ExpoSyncFunctionBody, args: ESObject[]): ESObject | void {
  switch (args.length) {
    case 0:
      return (body as ExpoFunction0<ESObject | void>)();
    case 1:
      return (body as ExpoFunction1<ESObject, ESObject | void>)(args[0]);
    case 2:
      return (body as ExpoFunction2<ESObject, ESObject, ESObject | void>)(args[0], args[1]);
    case 3:
      return (body as ExpoFunction3<ESObject, ESObject, ESObject, ESObject | void>)(args[0], args[1], args[2]);
    case 4:
      return (body as ExpoFunction4<ESObject, ESObject, ESObject, ESObject, ESObject | void>)(args[0], args[1], args[2], args[3]);
    case 5:
      return (body as ExpoFunction5<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>)(args[0], args[1], args[2], args[3], args[4]);
    case 6:
      return (body as ExpoFunction6<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
      );
    case 7:
      return (body as ExpoFunction7<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
      );
    case 8:
      return (body as ExpoFunction8<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7],
      );
    case 9:
      return (body as ExpoFunction9<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject | void>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7],
        args[8],
      );
    default:
      throw new Error(`Expo ArkTS function bridge received unsupported arity ${args.length}.`);
  }
}

export async function invokeAsyncFunction(body: ExpoAsyncFunction, args: ESObject[], path: string = 'Expo function'): Promise<ESObject | void> {
  if (writableFunctionArguments(body).length > 0) {
    throw new ExpoModuleError('ERR_WRITABLE_ARGUMENT', 'Writable arguments are supported only by synchronous module functions.');
  }
  const values: ESObject[] = prepareArguments(body, args, 0, path);
  const result: ESObject | void = await invokeRawAsyncFunction(unwrapAsyncFunction(body), values);

  return encodeFunctionResult(body, result, `${path} return value`);
}

async function invokeRawAsyncFunction(body: ExpoAsyncFunctionBody, args: ESObject[]): Promise<ESObject | void> {
  switch (args.length) {
    case 0:
      return await (body as ExpoFunction0<Promise<ESObject | void>>)();
    case 1:
      return await (body as ExpoFunction1<ESObject, Promise<ESObject | void>>)(args[0]);
    case 2:
      return await (body as ExpoFunction2<ESObject, ESObject, Promise<ESObject | void>>)(args[0], args[1]);
    case 3:
      return await (body as ExpoFunction3<ESObject, ESObject, ESObject, Promise<ESObject | void>>)(args[0], args[1], args[2]);
    case 4:
      return await (body as ExpoFunction4<ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>)(args[0], args[1], args[2], args[3]);
    case 5:
      return await (body as ExpoFunction5<ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
      );
    case 6:
      return await (body as ExpoFunction6<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
      );
    case 7:
      return await (body as ExpoFunction7<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
      );
    case 8:
      return await (body as ExpoFunction8<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>)(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7],
      );
    case 9:
      return await (
        body as ExpoFunction9<ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, ESObject, Promise<ESObject | void>>
      )(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8]);
    default:
      throw new Error(`Expo ArkTS function bridge received unsupported arity ${args.length}.`);
  }
}

export function invokeOwnedSyncFunction<Owner>(
  owner: Owner,
  body: ExpoOwnedSyncFunction<Owner>,
  args: ESObject[],
  path: string = 'Expo function',
): ESObject | void {
  const values: ESObject[] = [owner as ESObject];
  values.push(...prepareArguments(body, args, 1, path));

  const result: ESObject | void = invokeRawSyncFunction(unwrapOwnedSyncFunction(body) as ExpoSyncFunctionBody, values);

  return encodeFunctionResult(body, result, `${path} return value`);
}

/** @internal Invokes an owned function without encoding its author object. */
export function invokeOwnedSyncFunctionForAuthorObject<Owner>(
  owner: Owner,
  body: ExpoOwnedSyncFunction<Owner>,
  args: ESObject[],
  path: string,
): ESObject | void {
  const values: ESObject[] = [owner as ESObject];
  values.push(...prepareArguments(body, args, 1, path));

  return invokeRawSyncFunction(unwrapOwnedSyncFunction(body) as ExpoSyncFunctionBody, values);
}

export async function invokeOwnedAsyncFunction<Owner>(
  owner: Owner,
  body: ExpoOwnedAsyncFunction<Owner>,
  args: ESObject[],
  path: string = 'Expo function',
): Promise<ESObject | void> {
  const values: ESObject[] = [owner as ESObject];
  values.push(...prepareArguments(body, args, 1, path));

  const result: ESObject | void = await invokeRawAsyncFunction(unwrapOwnedAsyncFunction(body) as ExpoAsyncFunctionBody, values);

  return encodeFunctionResult(body, result, `${path} return value`);
}

function encodeFunctionResult<Body>(body: Body | ExpoFunctionSpec<Body>, value: ESObject | void, path: string): ESObject | void {
  if (body instanceof ExpoFunctionSpec) {
    const resultType: ExpoValueType<ESObject> | undefined = body.resultTypeValue();
    if (resultType !== undefined) {
      return ExpoValueConverter.toBridge(value as ESObject, resultType, path);
    }
  }

  return ExpoValueConverter.toBridge(value, undefined, path);
}

function functionArityWithOwner<Body>(body: Body | ExpoFunctionSpec<Body>, ownerArity: number): ExpoFunctionArityRange {
  if (body instanceof ExpoFunctionSpec) {
    if (ownerArity !== 0 && writableFunctionArguments(body).length > 0) {
      throw new ExpoModuleError('ERR_WRITABLE_ARGUMENT', 'Writable arguments are supported only by synchronous module functions.');
    }
    const required: number = body.rawRequiredArity - ownerArity;
    const maximum: number = body.rawMaximumArity - ownerArity;

    requireArityRange(required, maximum);

    return { required, maximum };
  }

  const arity: number = rawFunctionLength(body) - ownerArity;
  if (arity !== 0) {
    throw new ExpoModuleError('ERR_VALUE_CONVERTER_REQUIRED', 'Expo functions with arguments must use ExpoFunction.typed* converter tokens.');
  }

  requireArityRange(arity, arity);

  return { required: arity, maximum: arity };
}

function prepareArguments<Body>(body: Body | ExpoFunctionSpec<Body>, args: ESObject[], ownerArity: number, path: string): ESObject[] {
  const decoded: ESObject[] = args.slice();

  if (!(body instanceof ExpoFunctionSpec)) {
    return decoded.map(
      (value: ESObject, index: number): ESObject => ExpoValueConverter.fromBridge<ESObject>(value, undefined, `${path} argument ${index + 1}`),
    );
  }

  const maximum: number = body.rawMaximumArity - ownerArity;

  for (let index = 0; index < maximum; index += 1) {
    if (index < decoded.length && decoded[index] !== undefined) continue;
    if (index >= decoded.length && body.padsWithUndefined) {
      decoded[index] = undefined as ESObject;
    }
  }

  for (let index = 0; index < decoded.length; index += 1) {
    const type: ExpoValueType<ESObject> | undefined = body.argumentTypes[index];
    decoded[index] = ExpoValueConverter.fromBridge<ESObject>(decoded[index], type, `${path} argument ${index + 1}`);
  }

  return decoded;
}

function unwrapSyncFunction(body: ExpoSyncFunction): ExpoSyncFunctionBody {
  return body instanceof ExpoFunctionSpec ? body.body : body;
}

function unwrapAsyncFunction(body: ExpoAsyncFunction): ExpoAsyncFunctionBody {
  return body instanceof ExpoFunctionSpec ? body.body : body;
}

function unwrapOwnedSyncFunction<Owner>(body: ExpoOwnedSyncFunction<Owner>): ExpoOwnedSyncFunctionBody<Owner> {
  return body instanceof ExpoFunctionSpec ? body.body : body;
}

function unwrapOwnedAsyncFunction<Owner>(body: ExpoOwnedAsyncFunction<Owner>): ExpoOwnedAsyncFunctionBody<Owner> {
  return body instanceof ExpoFunctionSpec ? body.body : body;
}

function rawFunctionLength<Body>(body: Body): number {
  const length: number = (body as ExpoFunction0<ESObject>).length;
  if (!Number.isInteger(length) || length < 0) {
    throw new Error('Expo function closure has an invalid runtime length.');
  }
  return length;
}

function typedFunctionSpec<Body>(body: Body, argumentTypes: ExpoValueType<ESObject>[], ownerArity: number): ExpoFunctionSpec<Body> {
  // Use converter metadata for maximum arity; Function.length omits defaulted parameters.
  const rawMaximum: number = ownerArity + argumentTypes.length;
  let requiredArguments: number = argumentTypes.length;

  while (requiredArguments > 0 && argumentTypes[requiredArguments - 1].isOmittable) {
    requiredArguments -= 1;
  }

  for (let index = 0; index < requiredArguments; index += 1) {
    if (argumentTypes[index].isOmittable) {
      throw new Error('Expo function optional/default arguments must be trailing.');
    }
  }

  return new ExpoFunctionSpec<Body>(body, ownerArity + requiredArguments, rawMaximum, requiredArguments < argumentTypes.length, argumentTypes);
}

function requireArityRange(required: number, maximum: number): void {
  if (!Number.isInteger(required) || !Number.isInteger(maximum) || required < 0 || maximum < required || maximum > 9) {
    throw new Error(`Expo function has invalid argument range ${required}...${maximum}.`);
  }
}

function primitiveType<Value>(expected: string, typeName: string): ExpoValueType<Value> {
  return new ExpoValueType<Value>(
    expected,
    (value: ESObject, path: string): Value => {
      if (typeof value !== typeName) throw new ExpoArgumentTypeError(path, expected, value);
      return value as Value;
    },
    (value: Value, path: string): ESObject => {
      const bridgeValue: ESObject = value as ESObject;
      if (typeof bridgeValue !== typeName) throw new ExpoArgumentTypeError(path, expected, bridgeValue);
      return bridgeValue;
    },
  );
}

function requireNumber(value: ESObject, path: string): number {
  if (typeof value !== 'number') {
    throw new ExpoArgumentTypeError(path, 'number', value);
  }
  return value;
}

function decodeDate(value: ESObject, path: string): Date {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new ExpoArgumentTypeError(path, 'finite Date epoch milliseconds', value);
    return new Date(value);
  }

  if (typeof value !== 'string') {
    throw new ExpoArgumentTypeError(path, 'Date epoch milliseconds or ISO-8601 string', value);
  }

  const match: RegExpMatchArray | null = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$/);
  if (match === null) {
    throw new ExpoArgumentTypeError(path, 'ISO-8601 date-time string', value);
  }

  const year: number = Number(match[1]);
  const month: number = Number(match[2]);
  const day: number = Number(match[3]);
  const hour: number = Number(match[4]);
  const minute: number = Number(match[5]);
  const second: number = Number(match[6]);
  const milliseconds: number = Number(`${match[7] ?? ''}000`.slice(0, 3));
  const offsetHour: number = match[8] === 'Z' ? 0 : Number(match[10]);
  const offsetMinute: number = match[8] === 'Z' ? 0 : Number(match[11]);

  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth(year, month) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    offsetHour > 23 ||
    offsetMinute > 59
  ) {
    throw new ExpoArgumentTypeError(path, 'valid ISO-8601 date-time string', value);
  }

  const result = new Date(0);
  result.setUTCFullYear(year, month - 1, day);
  result.setUTCHours(hour, minute, second, milliseconds);

  const offsetSign: number = match[8] === 'Z' || match[9] === '+' ? 1 : -1;
  const epochMilliseconds: number = result.getTime() - offsetSign * (offsetHour * 60 + offsetMinute) * 60_000;
  if (!Number.isFinite(epochMilliseconds)) {
    throw new ExpoArgumentTypeError(path, 'valid ISO-8601 date-time string', value);
  }
  return new Date(epochMilliseconds);
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    const leap: boolean = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    return leap ? 29 : 28;
  }
  return month === 4 || month === 6 || month === 9 || month === 11 ? 30 : 31;
}

function numericTypedArrayType<Value>(name: string, predicate: (value: ESObject) => boolean): ExpoValueType<Value> {
  return new ExpoValueType<Value>(
    name,
    (value: ESObject, path: string): Value => {
      if (!predicate(value)) throw new ExpoArgumentTypeError(path, name, value);
      return value as Value;
    },
    (value: Value, path: string): ESObject => {
      const bridgeValue: ESObject = value as ESObject;
      if (!predicate(bridgeValue)) throw new ExpoArgumentTypeError(path, name, bridgeValue);
      return bridgeValue;
    },
  );
}

function isNumericTypedArray(value: ESObject): boolean {
  return numericTypedArrayName(value) !== undefined;
}

function numericTypedArrayName(value: ESObject): string | undefined {
  if (value instanceof Int8Array) return 'Int8Array';
  if (value instanceof Uint8Array) return 'Uint8Array';
  if (value instanceof Uint8ClampedArray) return 'Uint8ClampedArray';
  if (value instanceof Int16Array) return 'Int16Array';
  if (value instanceof Uint16Array) return 'Uint16Array';
  if (value instanceof Int32Array) return 'Int32Array';
  if (value instanceof Uint32Array) return 'Uint32Array';
  if (value instanceof Float32Array) return 'Float32Array';
  if (value instanceof Float64Array) return 'Float64Array';
  if (value instanceof BigInt64Array) return 'BigInt64Array';
  if (value instanceof BigUint64Array) return 'BigUint64Array';
  return undefined;
}

function validateCopyValue(value: ESObject, path: string, depth: number): void {
  if (depth > MAX_VALUE_DEPTH) {
    throw new ExpoModuleError('ERR_VALUE_NESTING', `${path} exceeds the maximum copy-value depth of ${MAX_VALUE_DEPTH}.`);
  }

  if (value === undefined || value === null || typeof value === 'boolean' || typeof value === 'string') return;

  if (typeof value === 'number') {
    requireNumber(value, path);
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((item: ESObject, index: number): void => validateCopyValue(item, `${path}[${index}]`, depth + 1));
    return;
  }

  if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) {
    throw new ExpoModuleError(
      'ERR_VALUE_CONVERTER_REQUIRED',
      `${path} is ${ExpoValueConverter.actualType(value)} and requires its explicit ExpoValueTypes converter.`,
    );
  }

  if (value instanceof Date || value instanceof url.URL) {
    throw new ExpoModuleError(
      'ERR_VALUE_CONVERTER_REQUIRED',
      `${path} is ${ExpoValueConverter.actualType(value)} and requires its explicit ExpoValueTypes converter.`,
    );
  }

  if (typeof value === 'function') {
    throw new ExpoModuleError(
      'ERR_UNSUPPORTED_VALUE_TYPE',
      `${path} is a function/callback. Harmony callback values are not supported; use module or SharedObject events.`,
    );
  }

  if (typeof value === 'symbol' || typeof value === 'bigint') {
    throw new ExpoModuleError('ERR_UNSUPPORTED_VALUE_TYPE', `${path} has unsupported type '${typeof value}'.`);
  }

  Object.keys(value).forEach((key: string): void => {
    validateCopyValue(value[key], `${path}.${key}`, depth + 1);
  });
}

function isRecordValue(value: ESObject): boolean {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    !(value instanceof ArrayBuffer) &&
    !ArrayBuffer.isView(value) &&
    !(value instanceof Date) &&
    !(value instanceof url.URL)
  );
}

class ExpoArgumentTypeError extends ExpoModuleError {
  constructor(path: string, expected: string, value: ESObject) {
    super('ERR_INVALID_ARGUMENT_TYPE', `${path} expected ${expected}, received ${ExpoValueConverter.actualType(value)}.`, undefined, path);
  }
}
