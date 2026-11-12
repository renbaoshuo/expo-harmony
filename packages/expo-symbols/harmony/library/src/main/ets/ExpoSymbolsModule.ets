/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { resourceManager } from '@kit.LocalizationKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

enum SymbolType {
  Monochrome = 'monochrome',
  Hierarchical = 'hierarchical',
  Palette = 'palette',
  Multicolor = 'multicolor',
}

const SYMBOL_TYPE_VALUES: Record<string, SymbolType> = {
  'monochrome': SymbolType.Monochrome,
  'hierarchical': SymbolType.Hierarchical,
  'palette': SymbolType.Palette,
  'multicolor': SymbolType.Multicolor,
};
const SYMBOL_TYPE = ExpoValueTypes.enumerable<SymbolType>('SymbolType', SYMBOL_TYPE_VALUES);

const INVALID_RESOURCE_NAME = 9001003;
const RESOURCE_NOT_FOUND = 9001004;

const WEIGHTS: Record<string, number> = {
  'unspecified': 400,
  'ultraLight': 100,
  'thin': 200,
  'light': 300,
  'regular': 400,
  'medium': 500,
  'semibold': 600,
  'bold': 700,
  'heavy': 800,
  'black': 900,
};

function isSymbolAvailable(name: string): boolean {
  if (!/^[a-zA-Z0-9_]+$/.test(name)) return false;

  try {
    return resourceManager.getSysResourceManager().getSymbolByName(name) > 0;
  } catch (error) {
    const failure = error as BusinessError;
    const code = Number(failure.code);

    if (code === INVALID_RESOURCE_NAME || code === RESOURCE_NOT_FOUND) return false;

    throw new ExpoModuleError('ERR_SYMBOL_RESOURCE', `ResourceManager (${failure.code}): ${failure.message}`);
  }
}

function symbolResource(name: string): Resource | undefined {
  return isSymbolAvailable(name) ? $r(`sys.symbol.${name}`) : undefined;
}

function argbColor(color: number): string {
  // Numeric ResourceColor treats an all-zero alpha byte as RGB (opaque).
  return `#${(color >>> 0).toString(16).padStart(8, '0')}`;
}

@Observed
class SymbolView extends ExpoView {
  resource: Resource | undefined = undefined;
  size: number = 24;
  type: SymbolType = SymbolType.Monochrome;
  weight: number = 400;
  tint: number | null = null;
  colors: number[] = [];

  constructor(context: ExpoViewContext) {
    super(context);
  }

  renderingStrategy(): SymbolRenderingStrategy {
    if (this.tint !== null && this.type !== SymbolType.Hierarchical) return SymbolRenderingStrategy.SINGLE;

    switch (this.type) {
      case SymbolType.Hierarchical:
        return SymbolRenderingStrategy.MULTIPLE_OPACITY;
      case SymbolType.Palette:
        return this.colors.length > 1 ? SymbolRenderingStrategy.MULTIPLE_COLOR : SymbolRenderingStrategy.SINGLE;
      case SymbolType.Multicolor:
        return SymbolRenderingStrategy.MULTIPLE_COLOR;
      default:
        return SymbolRenderingStrategy.SINGLE;
    }
  }

  fontColors(): ResourceColor[] | undefined {
    if (this.tint !== null) return [argbColor(this.tint)];

    if (this.type === SymbolType.Palette && this.colors.length > 1) {
      return this.colors.slice(0, 3).map((color: number): ResourceColor => argbColor(color));
    }

    return undefined;
  }
}

@Component
struct SymbolViewContent {
  @ObjectLink view: SymbolView;

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      if (this.view.resource !== undefined && this.view.size > 0) {
        // API 24 retains old colors for fontColor(undefined); recreate the glyph to restore system defaults.
        if (this.view.fontColors() !== undefined) {
          SymbolGlyph(this.view.resource)
            .fontSize(`${this.view.size}vp`)
            .fontWeight(this.view.weight)
            .renderingStrategy(this.view.renderingStrategy())
            .fontColor(this.view.fontColors()!)
            .hitTestBehavior(HitTestMode.None);
        } else {
          SymbolGlyph(this.view.resource)
            .fontSize(`${this.view.size}vp`)
            .fontWeight(this.view.weight)
            .renderingStrategy(this.view.renderingStrategy())
            .hitTestBehavior(HitTestMode.None);
        }
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None);
  }
}

@Builder
function buildSymbolView(context: ExpoViewContentContext): void {
  SymbolViewContent({ view: context.nativeView as SymbolView });
}

export class ExpoSymbolsModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const view = new ExpoViewDefinition<SymbolView>(
      'SymbolView',
      (context: ExpoViewContext): SymbolView => new SymbolView(context),
      wrapBuilder(buildSymbolView),
    )
      .prop(
        'name',
        ExpoValueTypes.string(),
        (view: SymbolView, name: string): void => {
          view.resource = symbolResource(name);
        },
        '',
      )
      .prop(
        'size',
        ExpoValueTypes.number(),
        (view: SymbolView, size: number): void => {
          view.size = Number.isFinite(size) && size >= 0 ? size : 24;
        },
        24,
      )
      .prop(
        'type',
        SYMBOL_TYPE,
        (view: SymbolView, type: SymbolType): void => {
          view.type = type;
        },
        SymbolType.Monochrome,
      )
      .prop(
        'weight',
        ExpoValueTypes.string(),
        (view: SymbolView, weight: string): void => {
          const value = WEIGHTS[weight];
          if (typeof value !== 'number') throw new ExpoModuleError('ERR_SYMBOL_WEIGHT', `Unknown symbol weight: ${weight}`);

          view.weight = value;
        },
        'unspecified',
      )
      .prop(
        'tint',
        ExpoValueTypes.number().nullable(),
        (view: SymbolView, color: number | null): void => {
          view.tint = color;
        },
        null,
      )
      .prop(
        'colors',
        ExpoValueTypes.array(ExpoValueTypes.number()),
        (view: SymbolView, colors: number[]): void => {
          view.colors = colors;
        },
        [],
      );

    return new ExpoModuleDefinition()
      .name('SymbolModule')
      .syncFunction('isSymbolAvailable', ExpoFunction.typed1(ExpoValueTypes.string(), isSymbolAvailable).returns(ExpoValueTypes.boolean()))
      .view(view);
  }
}
