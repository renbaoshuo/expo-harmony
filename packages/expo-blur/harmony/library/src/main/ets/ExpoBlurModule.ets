import {
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

const DEFAULT_INTENSITY: number = 50;

enum ExpoBlurTint {
  DEFAULT = 'default',
  EXTRA_LIGHT = 'extraLight',
  LIGHT = 'light',
  DARK = 'dark',
  REGULAR = 'regular',
  PROMINENT = 'prominent',
  SYSTEM_ULTRA_THIN_MATERIAL = 'systemUltraThinMaterial',
  SYSTEM_THIN_MATERIAL = 'systemThinMaterial',
  SYSTEM_MATERIAL = 'systemMaterial',
  SYSTEM_THICK_MATERIAL = 'systemThickMaterial',
  SYSTEM_CHROME_MATERIAL = 'systemChromeMaterial',
  SYSTEM_ULTRA_THIN_MATERIAL_LIGHT = 'systemUltraThinMaterialLight',
  SYSTEM_THIN_MATERIAL_LIGHT = 'systemThinMaterialLight',
  SYSTEM_MATERIAL_LIGHT = 'systemMaterialLight',
  SYSTEM_THICK_MATERIAL_LIGHT = 'systemThickMaterialLight',
  SYSTEM_CHROME_MATERIAL_LIGHT = 'systemChromeMaterialLight',
  SYSTEM_ULTRA_THIN_MATERIAL_DARK = 'systemUltraThinMaterialDark',
  SYSTEM_THIN_MATERIAL_DARK = 'systemThinMaterialDark',
  SYSTEM_MATERIAL_DARK = 'systemMaterialDark',
  SYSTEM_THICK_MATERIAL_DARK = 'systemThickMaterialDark',
  SYSTEM_CHROME_MATERIAL_DARK = 'systemChromeMaterialDark',
}

const BLUR_TINT_TYPE = ExpoValueTypes.enumerable<ExpoBlurTint>('BlurTint', {
  default: ExpoBlurTint.DEFAULT,
  extraLight: ExpoBlurTint.EXTRA_LIGHT,
  light: ExpoBlurTint.LIGHT,
  dark: ExpoBlurTint.DARK,
  regular: ExpoBlurTint.REGULAR,
  prominent: ExpoBlurTint.PROMINENT,
  systemUltraThinMaterial: ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL,
  systemThinMaterial: ExpoBlurTint.SYSTEM_THIN_MATERIAL,
  systemMaterial: ExpoBlurTint.SYSTEM_MATERIAL,
  systemThickMaterial: ExpoBlurTint.SYSTEM_THICK_MATERIAL,
  systemChromeMaterial: ExpoBlurTint.SYSTEM_CHROME_MATERIAL,
  systemUltraThinMaterialLight: ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL_LIGHT,
  systemThinMaterialLight: ExpoBlurTint.SYSTEM_THIN_MATERIAL_LIGHT,
  systemMaterialLight: ExpoBlurTint.SYSTEM_MATERIAL_LIGHT,
  systemThickMaterialLight: ExpoBlurTint.SYSTEM_THICK_MATERIAL_LIGHT,
  systemChromeMaterialLight: ExpoBlurTint.SYSTEM_CHROME_MATERIAL_LIGHT,
  systemUltraThinMaterialDark: ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL_DARK,
  systemThinMaterialDark: ExpoBlurTint.SYSTEM_THIN_MATERIAL_DARK,
  systemMaterialDark: ExpoBlurTint.SYSTEM_MATERIAL_DARK,
  systemThickMaterialDark: ExpoBlurTint.SYSTEM_THICK_MATERIAL_DARK,
  systemChromeMaterialDark: ExpoBlurTint.SYSTEM_CHROME_MATERIAL_DARK,
});

@Observed
class ExpoBlurView extends ExpoView {
  intensity: number = DEFAULT_INTENSITY;
  tint: ExpoBlurTint = ExpoBlurTint.DEFAULT;

  constructor(context: ExpoViewContext) {
    super(context);
  }
}

function blurStyleForTint(tint: ExpoBlurTint): BlurStyle {
  switch (tint) {
    case ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL:
    case ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL_DARK:
    case ExpoBlurTint.EXTRA_LIGHT:
      return BlurStyle.COMPONENT_ULTRA_THIN;

    case ExpoBlurTint.LIGHT:
    case ExpoBlurTint.SYSTEM_THIN_MATERIAL:
    case ExpoBlurTint.SYSTEM_THIN_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_THIN_MATERIAL_DARK:
      return BlurStyle.COMPONENT_THIN;

    case ExpoBlurTint.SYSTEM_THICK_MATERIAL:
    case ExpoBlurTint.SYSTEM_THICK_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_THICK_MATERIAL_DARK:
      return BlurStyle.COMPONENT_THICK;

    case ExpoBlurTint.PROMINENT:
    case ExpoBlurTint.SYSTEM_CHROME_MATERIAL:
    case ExpoBlurTint.SYSTEM_CHROME_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_CHROME_MATERIAL_DARK:
      return BlurStyle.COMPONENT_ULTRA_THICK;

    case ExpoBlurTint.DEFAULT:
    case ExpoBlurTint.REGULAR:
    case ExpoBlurTint.DARK:
    case ExpoBlurTint.SYSTEM_MATERIAL:
    case ExpoBlurTint.SYSTEM_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_MATERIAL_DARK:
      return BlurStyle.COMPONENT_REGULAR;
  }
}

function resolveBlurStyle(tint: ExpoBlurTint, intensity: number): BlurStyle {
  return intensity <= 0 ? BlurStyle.NONE : blurStyleForTint(tint);
}

function resolveColorMode(tint: ExpoBlurTint): ThemeColorMode {
  switch (tint) {
    case ExpoBlurTint.LIGHT:
    case ExpoBlurTint.EXTRA_LIGHT:
    case ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_THIN_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_THICK_MATERIAL_LIGHT:
    case ExpoBlurTint.SYSTEM_CHROME_MATERIAL_LIGHT:
      return ThemeColorMode.LIGHT;

    case ExpoBlurTint.DARK:
    case ExpoBlurTint.SYSTEM_ULTRA_THIN_MATERIAL_DARK:
    case ExpoBlurTint.SYSTEM_THIN_MATERIAL_DARK:
    case ExpoBlurTint.SYSTEM_MATERIAL_DARK:
    case ExpoBlurTint.SYSTEM_THICK_MATERIAL_DARK:
    case ExpoBlurTint.SYSTEM_CHROME_MATERIAL_DARK:
      return ThemeColorMode.DARK;

    default:
      return ThemeColorMode.SYSTEM;
  }
}

@Component
struct ExpoBlurViewContent {
  @ObjectLink view: ExpoBlurView;

  build(): void {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundBlurStyle(resolveBlurStyle(this.view.tint, this.view.intensity), {
        colorMode: resolveColorMode(this.view.tint),
        adaptiveColor: AdaptiveColor.DEFAULT,
        scale: this.view.intensity / 100,
      })
      .hitTestBehavior(HitTestMode.None);
  }
}

@Builder
function buildExpoBlurView(context: ExpoViewContentContext): void {
  ExpoBlurViewContent({ view: context.nativeView as ExpoBlurView });
}

export class ExpoBlurModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const blurView = new ExpoViewDefinition<ExpoBlurView>(
      'ExpoBlurView',
      (context: ExpoViewContext): ExpoBlurView => new ExpoBlurView(context),
      wrapBuilder(buildExpoBlurView),
    )
      .prop(
        'intensity',
        ExpoValueTypes.number(),
        (view: ExpoBlurView, intensity: number): void => {
          if (!Number.isFinite(intensity)) {
            console.warn('ExpoBlur ignored a non-finite intensity update.');
            return;
          }
          view.intensity = Math.min(100, Math.max(0, intensity));
        },
        DEFAULT_INTENSITY,
      )
      .prop(
        'tint',
        BLUR_TINT_TYPE,
        (view: ExpoBlurView, tint: ExpoBlurTint): void => {
          view.tint = tint;
        },
        ExpoBlurTint.DEFAULT,
      )
      // These props are Android-specific in upstream expo-blur. Harmony accepts
      // them so the shared JS facade remains portable, but native blur does not
      // use an Android BlurTarget or blur implementation selector.
      .prop('blurTargetId', ExpoValueTypes.number().nullable(), (_view: ExpoBlurView, _blurTargetId: number | null): void => {}, null)
      .prop('blurReductionFactor', ExpoValueTypes.number(), (_view: ExpoBlurView, _blurReductionFactor: number): void => {}, 4)
      .prop('blurMethod', ExpoValueTypes.string(), (_view: ExpoBlurView, _blurMethod: string): void => {}, 'none');

    return new ExpoModuleDefinition().name('ExpoBlur').view(blurView);
  }
}
