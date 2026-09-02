/** Internal record helpers kept in TypeScript because ArkTS restricts Object.defineProperty. */
export function hasOwnExpoRecordKey<Value>(value: Record<string, Value>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

export function defineExpoRecordValue<Value>(output: Record<string, Value>, key: string, value: Value): void {
  Object.defineProperty(output, key, {
    value,
    writable: true,
    enumerable: true,
    configurable: true,
  });
}
