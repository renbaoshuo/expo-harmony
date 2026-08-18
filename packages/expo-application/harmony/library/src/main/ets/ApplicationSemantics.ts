export function selectInstallationTimestamp(
  sdkApiVersion: number,
  firstInstallTime: number | undefined,
  installTime: number
): number {
  return sdkApiVersion >= 18 && firstInstallTime !== undefined
    ? firstInstallTime
    : installTime;
}

export function literalApplicationLabel(label: string): string | null {
  return label.length === 0 || label.startsWith('$') ? null : label;
}
