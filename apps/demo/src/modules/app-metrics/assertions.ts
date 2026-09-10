export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function errorCode(error: unknown): string | undefined {
  if (!isRecord(error)) return undefined;

  return typeof error.code === 'string' ? error.code : undefined;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (isRecord(error) && typeof error.message === 'string') return error.message;

  return String(error);
}

export async function expectErrorCode(
  label: string,
  expectedCode: string,
  operation: () => Promise<unknown>
): Promise<{ code: string; label: string }> {
  try {
    await operation();
  } catch (error) {
    const code = errorCode(error);
    if (code !== expectedCode) {
      throw new Error(`${label} 以 ${code ?? errorMessage(error)} 拒绝，而非 ${expectedCode}。`);
    }

    return { code, label };
  }

  throw new Error(`${label} 不应成功返回。`);
}
