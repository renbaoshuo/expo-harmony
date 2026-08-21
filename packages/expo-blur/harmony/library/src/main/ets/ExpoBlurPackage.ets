import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNComponentContext, RNPackageContext } from '@rnoh/react-native-openharmony';
import { ExpoViewAdapterRegistry } from '@expo-harmony/expo-modules-core';
import type { ExpoViewAdapter, ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

const COMPONENT_NAME: string = 'ViewManagerAdapter_ExpoBlur_ExpoBlurView';
const DEFAULT_INTENSITY: number = 50;
const DEFAULT_TINT: string = 'default';

@Observed
class ExpoBlurViewState {
  intensity: number = DEFAULT_INTENSITY;
  tint: string = DEFAULT_TINT;
}

function normalizeIntensity(value: ESObject, fallback: number): number {
  if (value === undefined || value === null) return DEFAULT_INTENSITY;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    console.warn(`Expo Blur ignored an invalid intensity value: ${String(value)}`);
    return fallback;
  }

  const intensity = Number(value);

  return Math.min(100, Math.max(0, intensity));
}

function normalizeTint(value: ESObject, fallback: string): string {
  if (value === undefined || value === null) return DEFAULT_TINT;
  if (typeof value !== 'string') {
    console.warn(`Expo Blur ignored an invalid tint value: ${String(value)}`);
    return fallback;
  }

  if (!isSupportedTint(value)) {
    console.warn(`Expo Blur ignored an invalid tint value: ${value}`);
    return fallback;
  }

  return value;
}

function isSupportedTint(tint: string): boolean {
  try {
    blurStyleForTint(tint);
    return true;
  } catch (_) {
    return false;
  }
}

function blurStyleForTint(tint: string): BlurStyle {
  switch (tint) {
    case 'systemUltraThinMaterial':
    case 'systemUltraThinMaterialLight':
    case 'systemUltraThinMaterialDark':
      return BlurStyle.COMPONENT_ULTRA_THIN;

    case 'light':
    case 'extraLight':
    case 'systemThinMaterial':
    case 'systemThinMaterialLight':
    case 'systemThinMaterialDark':
      return BlurStyle.COMPONENT_THIN;

    case 'systemThickMaterial':
    case 'systemThickMaterialLight':
    case 'systemThickMaterialDark':
      return BlurStyle.COMPONENT_THICK;

    case 'prominent':
    case 'systemChromeMaterial':
    case 'systemChromeMaterialLight':
    case 'systemChromeMaterialDark':
      return BlurStyle.COMPONENT_ULTRA_THICK;

    case 'default':
    case 'regular':
    case 'dark':
    case 'systemMaterial':
    case 'systemMaterialLight':
    case 'systemMaterialDark':
      return BlurStyle.COMPONENT_REGULAR;

    default:
      throw new Error(`Invalid tint value provided: ${tint}`);
  }
}

function resolveBlurStyle(tint: string, intensity: number): BlurStyle {
  if (intensity <= 0) return BlurStyle.NONE;

  return blurStyleForTint(tint);
}

function resolveColorMode(tint: string): ThemeColorMode {
  switch (tint) {
    case 'light':
    case 'extraLight':
    case 'systemUltraThinMaterialLight':
    case 'systemThinMaterialLight':
    case 'systemMaterialLight':
    case 'systemThickMaterialLight':
    case 'systemChromeMaterialLight':
      return ThemeColorMode.LIGHT;

    case 'dark':
    case 'systemUltraThinMaterialDark':
    case 'systemThinMaterialDark':
    case 'systemMaterialDark':
    case 'systemThickMaterialDark':
    case 'systemChromeMaterialDark':
      return ThemeColorMode.DARK;

    default:
      return ThemeColorMode.SYSTEM;
  }
}

@Component
struct ExpoBlurViewContent {
  @ObjectLink state: ExpoBlurViewState;

  build(): void {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundBlurStyle(resolveBlurStyle(this.state.tint, this.state.intensity), {
        colorMode: resolveColorMode(this.state.tint),
        adaptiveColor: AdaptiveColor.DEFAULT,
        scale: this.state.intensity / 100,
      })
      .hitTestBehavior(HitTestMode.None);
  }
}

@Builder
function buildExpoBlurView(context: ExpoViewContentContext): void {
  ExpoBlurViewContent({ state: context.nativeView as ExpoBlurViewState });
}

class ExpoBlurViewAdapter implements ExpoViewAdapter {
  readonly componentName: string = COMPONENT_NAME;
  readonly content: WrappedBuilder<[ExpoViewContentContext]> = wrapBuilder(buildExpoBlurView);

  create(_context: RNComponentContext, _tag: number, _name: string): ESObject {
    return new ExpoBlurViewState();
  }

  updateProps(view: ESObject, props: Record<string, ESObject>): void {
    const state = view as ExpoBlurViewState;
    const intensity = normalizeIntensity(props.intensity, state.intensity);
    const tint = normalizeTint(props.tint, state.tint);

    state.intensity = intensity;
    state.tint = tint;
  }
}

let registered: boolean = false;

function registerExpoBlurView(): void {
  if (registered) return;
  ExpoViewAdapterRegistry.register(new ExpoBlurViewAdapter());
  registered = true;
}

export class ExpoBlurPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
    registerExpoBlurView();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-blur';
  }
}
