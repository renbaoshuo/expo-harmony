import * as Haptics from 'expo-haptics';

const CHECK_PREFIX = 'EXPO_HARMONY_HAPTICS_CHECK';
const ARGUMENT_CHECK_PREFIX = 'EXPO_HARMONY_HAPTICS_ARGUMENT_CHECK';
const INVALID_ARGUMENT_CODE = 'ERR_HAPTICS_INVALID_ARGUMENT';
const UNKNOWN_ERROR_TEXT = '未知的触感反馈错误。';

type ProbeStatus = 'manual' | 'pass';

type ProbeStep = {
  detail: string;
  status: ProbeStatus;
  value?: unknown;
};

type HapticCase = {
  detail: string;
  id: string;
  label: string;
  run: () => Promise<void>;
};

export const HAPTICS_MANUAL_CASES: readonly HapticCase[] = [
  {
    detail: '一次选择变化脉冲；在亲手感受到之前，该结果只是一次 Promise 检查。',
    id: 'selection',
    label: '选择',
    run: () => Haptics.selectionAsync(),
  },
  {
    detail: '成功通知预设或 HarmonyOS 兜底效果。',
    id: 'notification-success',
    label: '成功',
    run: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success),
  },
  {
    detail: '警告通知预设或 HarmonyOS 兜底效果。',
    id: 'notification-warning',
    label: '警告',
    run: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning),
  },
  {
    detail: '错误通知预设或 HarmonyOS 兜底效果。',
    id: 'notification-error',
    label: '错误',
    run: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error),
  },
  {
    detail: '轻度冲击；HarmonyOS 将其映射为低强度柔和效果。',
    id: 'impact-light',
    label: '轻度',
    run: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light),
  },
  {
    detail: '中度冲击；HarmonyOS 将其映射为中强度硬朗效果。',
    id: 'impact-medium',
    label: '中度',
    run: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium),
  },
  {
    detail: '重度冲击；HarmonyOS 将其映射为高强度硬朗效果。',
    id: 'impact-heavy',
    label: '重度',
    run: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy),
  },
  {
    detail: '柔和冲击；HarmonyOS 将其映射为低强度柔和效果。',
    id: 'impact-soft',
    label: '柔和',
    run: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft),
  },
  {
    detail: '刚性冲击；HarmonyOS 将其映射为中强度锐利效果。',
    id: 'impact-rigid',
    label: '刚性',
    run: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid),
  },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function errorCode(error: unknown): string | undefined {
  if (!isRecord(error)) return undefined;

  try {
    const code = error.code;
    return typeof code === 'string' ? code : undefined;
  } catch (_) {
    return undefined;
  }
}

function errorText(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;

  try {
    return JSON.stringify(error) ?? String(error);
  } catch (_) {
    return UNKNOWN_ERROR_TEXT;
  }
}

function report(title: string, value: unknown): string {
  return `${title}\n${JSON.stringify(value, null, 2)}`;
}

async function runCase(item: HapticCase): Promise<ProbeStep> {
  const started = Date.now();
  await item.run();

  return {
    detail: '官方 Promise 已完成；此处不断言实际体感。',
    status: 'pass',
    value: { elapsedMs: Date.now() - started },
  };
}

async function expectInvalid(label: string, run: () => Promise<void>): Promise<ProbeStep> {
  let rejected = false;
  let reason: unknown;

  try {
    await run();
  } catch (error) {
    rejected = true;
    reason = error;
  }

  if (!rejected) {
    throw new Error(`${label} 接受了非法的反馈值。`);
  }

  const code = errorCode(reason);
  if (code !== INVALID_ARGUMENT_CODE) {
    throw new Error(`${label} 以 ${code ?? errorText(reason)} 拒绝，而非 ${INVALID_ARGUMENT_CODE}。`);
  }

  return {
    detail: '原生校验在发起任何震动请求之前就拒绝了非法值。',
    status: 'pass',
    value: { code },
  };
}

export async function runHapticsMatrix(): Promise<string> {
  const automatic: Record<string, ProbeStep> = {};

  for (const item of HAPTICS_MANUAL_CASES) {
    automatic[item.id] = await runCase(item);
  }

  const manual: Record<string, ProbeStep> = {};
  for (const item of HAPTICS_MANUAL_CASES) {
    manual[item.id] = { detail: item.detail, status: 'manual' };
  }

  return report(`${CHECK_PREFIX}:PASS`, { automatic, manual });
}

export async function runHapticsArgumentProbe(): Promise<string> {
  const steps: Record<string, ProbeStep> = {
    invalidNotification: await expectInvalid(
      'notificationAsync()',
      () => Haptics.notificationAsync('invalid' as Haptics.NotificationFeedbackType)
    ),
    invalidImpact: await expectInvalid(
      'impactAsync()',
      () => Haptics.impactAsync('invalid' as Haptics.ImpactFeedbackStyle)
    ),
    nonStringNotification: await expectInvalid(
      'notificationAsync(null)',
      () => Haptics.notificationAsync(null as unknown as Haptics.NotificationFeedbackType)
    ),
    nonStringImpact: await expectInvalid(
      'impactAsync(null)',
      () => Haptics.impactAsync(null as unknown as Haptics.ImpactFeedbackStyle)
    ),
  };

  return report(`${ARGUMENT_CHECK_PREFIX}:PASS`, steps);
}
