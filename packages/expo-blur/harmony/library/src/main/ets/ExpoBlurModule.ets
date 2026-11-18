/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

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
const DEFAULT_TINT: string = 'default';

interface BlurMaterial {
  readonly style: BlurStyle;
  readonly colorMode?: ThemeColorMode;
}

const BLUR_MATERIALS: Record<string, BlurMaterial> = {
  'default': { style: BlurStyle.COMPONENT_REGULAR },
  'extraLight': { style: BlurStyle.COMPONENT_ULTRA_THIN, colorMode: ThemeColorMode.LIGHT },
  'light': { style: BlurStyle.COMPONENT_THIN, colorMode: ThemeColorMode.LIGHT },
  'dark': { style: BlurStyle.COMPONENT_REGULAR, colorMode: ThemeColorMode.DARK },
  'regular': { style: BlurStyle.COMPONENT_REGULAR },
  'prominent': { style: BlurStyle.COMPONENT_ULTRA_THICK },
  'systemUltraThinMaterial': { style: BlurStyle.COMPONENT_ULTRA_THIN },
  'systemThinMaterial': { style: BlurStyle.COMPONENT_THIN },
  'systemMaterial': { style: BlurStyle.COMPONENT_REGULAR },
  'systemThickMaterial': { style: BlurStyle.COMPONENT_THICK },
  'systemChromeMaterial': { style: BlurStyle.COMPONENT_ULTRA_THICK },
  'systemUltraThinMaterialLight': { style: BlurStyle.COMPONENT_ULTRA_THIN, colorMode: ThemeColorMode.LIGHT },
  'systemThinMaterialLight': { style: BlurStyle.COMPONENT_THIN, colorMode: ThemeColorMode.LIGHT },
  'systemMaterialLight': { style: BlurStyle.COMPONENT_REGULAR, colorMode: ThemeColorMode.LIGHT },
  'systemThickMaterialLight': { style: BlurStyle.COMPONENT_THICK, colorMode: ThemeColorMode.LIGHT },
  'systemChromeMaterialLight': { style: BlurStyle.COMPONENT_ULTRA_THICK, colorMode: ThemeColorMode.LIGHT },
  'systemUltraThinMaterialDark': { style: BlurStyle.COMPONENT_ULTRA_THIN, colorMode: ThemeColorMode.DARK },
  'systemThinMaterialDark': { style: BlurStyle.COMPONENT_THIN, colorMode: ThemeColorMode.DARK },
  'systemMaterialDark': { style: BlurStyle.COMPONENT_REGULAR, colorMode: ThemeColorMode.DARK },
  'systemThickMaterialDark': { style: BlurStyle.COMPONENT_THICK, colorMode: ThemeColorMode.DARK },
  'systemChromeMaterialDark': { style: BlurStyle.COMPONENT_ULTRA_THICK, colorMode: ThemeColorMode.DARK },
};
const BLUR_TINT_VALUES: Record<string, string> = {};
Object.keys(BLUR_MATERIALS).forEach((tint: string): void => {
  BLUR_TINT_VALUES[tint] = tint;
});

const BLUR_TINT_TYPE = ExpoValueTypes.enumerable<string>('BlurTint', BLUR_TINT_VALUES);

@Observed
class ExpoBlurView extends ExpoView {
  intensity: number = DEFAULT_INTENSITY;
  material: BlurMaterial = BLUR_MATERIALS[DEFAULT_TINT];

  constructor(context: ExpoViewContext) {
    super(context);
  }
}

@Component
struct ExpoBlurViewContent {
  // The Expo host gives this component one observed view for its lifetime.
  @State view: ExpoBlurView | undefined = undefined;

  build(): void {
    if (this.view !== undefined) {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundBlurStyle(this.view.intensity === 0 ? BlurStyle.NONE : this.view.material.style, {
          colorMode: this.view.material.colorMode,
          scale: this.view.intensity / 100,
        })
        .hitTestBehavior(HitTestMode.None);
    }
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
    const view = new ExpoViewDefinition<ExpoBlurView>(
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
        (view: ExpoBlurView, tint: string): void => {
          view.material = BLUR_MATERIALS[tint];
        },
        DEFAULT_TINT,
      );

    return new ExpoModuleDefinition().name('ExpoBlur').view(view);
  }
}
