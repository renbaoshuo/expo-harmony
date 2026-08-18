export function normalizeSMSURL(value: string): string {
  if (value.includes('?')) return value;

  const separator = value.indexOf('&');
  if (separator < 0) return value;

  return `${value.slice(0, separator)}?${value.slice(separator + 1)}`;
}
