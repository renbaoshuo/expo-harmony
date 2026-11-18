/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ColorMetrics } from '@kit.ArkUI';
import { convertColorValueToHex, Descriptor, ViewDescriptorWrapperBase } from '@rnoh/react-native-openharmony';
import {
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoValueType,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

type GradientStop = [string, number];

// Validate jointly so a malformed stop or point cannot abort the Expo view's entire prop update.
const GRADIENT_PROP: ExpoValueType<ESObject> = ExpoValueTypes.any();

interface Gradient {
  readonly stops: GradientStop[];
  readonly startPoint: number[];
  readonly endPoint: number[];
}

@Observed
class ExpoLinearGradientView extends ExpoView {
  colors: ESObject = [];
  locations: ESObject = null;
  startPoint: number[] = [0.5, 0];
  endPoint: number[] = [0.5, 1];
  gradient?: Gradient;
  private redraw?: () => void;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  attachRedraw(callback: () => void): void {
    this.redraw = callback;
  }

  detachRedraw(callback: () => void): void {
    if (this.redraw === callback) this.redraw = undefined;
  }

  updateGradient(): void {
    const stops: GradientStop[] | undefined = gradientStops(this.colors, this.locations);

    if (stops === undefined) {
      // Keep the last valid gradient for canvas resizes.
      console.warn('ExpoLinearGradient ignored an invalid colors or locations update.');
      return;
    }

    this.gradient = { stops, startPoint: this.startPoint, endPoint: this.endPoint };
    this.redraw?.();
  }
}

function colorToString(color: ESObject): string | undefined {
  if (typeof color === 'number') {
    if (!Number.isInteger(color) || color < -0x80000000 || color > 0xffffffff) {
      return undefined;
    }
    return convertColorValueToHex(color);
  }
  if (typeof color !== 'string') return undefined;

  const value: string = color.trim();
  if (value.length === 0) return undefined;

  try {
    return ColorMetrics.resourceColor(value).color;
  } catch {
    return undefined;
  }
}

function gradientStops(colors: ESObject, locations: ESObject): GradientStop[] | undefined {
  if (!Array.isArray(colors) || colors.length < 2) return undefined;
  if (locations != null && (!Array.isArray(locations) || locations.length < colors.length)) return undefined;

  const stops: GradientStop[] = [];
  let last: number = -1;

  for (let index = 0; index < colors.length; index += 1) {
    const color: string | undefined = colorToString(colors[index]);
    if (color === undefined) return undefined;

    const offset: ESObject = locations == null ? index / (colors.length - 1) : locations[index];
    if (typeof offset !== 'number' || !Number.isFinite(offset) || offset < 0 || offset > 1 || offset < last) {
      return undefined;
    }

    last = offset;
    stops.push([color, offset]);
  }

  return stops;
}

function normalizePoint(point: ESObject, defaultX: number, defaultY: number): number[] | undefined {
  if (point == null) return [defaultX, defaultY];
  if (!Array.isArray(point) || point.length !== 2) return undefined;

  const x: ESObject = point[0];
  const y: ESObject = point[1];
  if (typeof x !== 'number' || typeof y !== 'number' || !Number.isFinite(x) || !Number.isFinite(y)) {
    return undefined;
  }

  return [x, y];
}

@Component
struct ExpoLinearGradientViewContent {
  @ObjectLink view: ExpoLinearGradientView;
  @State private borderRadii: BorderRadiuses = {};
  private unsubscribeDescriptor?: () => void;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;
  private readonly redraw = (): void => {
    if (this.ready) this.drawGradient();
  };

  aboutToAppear(): void {
    const tag = this.view.context.tag;
    const registry = this.view.context.rnComponentContext.descriptorRegistry;

    const update = (descriptor: Descriptor): void => {
      this.borderRadii = new ViewDescriptorWrapperBase(descriptor).borderRadius;
    };
    this.unsubscribeDescriptor = registry.subscribeToDescriptorChanges(tag, update);
    const descriptor = registry.getDescriptor(tag);
    if (descriptor !== undefined) update(descriptor);

    this.view.attachRedraw(this.redraw);
  }

  aboutToDisappear(): void {
    this.ready = false;
    this.view.detachRedraw(this.redraw);
    this.unsubscribeDescriptor?.();
    this.unsubscribeDescriptor = undefined;
  }

  private drawGradient(): void {
    const width: number = this.context.width;
    const height: number = this.context.height;
    const gradient: Gradient | undefined = this.view.gradient;
    if (!(width > 0 && height > 0) || gradient === undefined) return;

    const startX: number = gradient.startPoint[0] * width;
    const startY: number = gradient.startPoint[1] * height;
    const endX: number = gradient.endPoint[0] * width;
    const endY: number = gradient.endPoint[1] * height;
    if (![startX, startY, endX, endY].every(Number.isFinite)) return;

    try {
      const fill: CanvasGradient = this.context.createLinearGradient(startX, startY, endX, endY);
      gradient.stops.forEach((stop: GradientStop): void => fill.addColorStop(stop[1], stop[0]));

      this.context.clearRect(0, 0, width, height);
      this.context.fillStyle = fill;
      this.context.fillRect(0, 0, width, height);
    } catch (error) {
      console.warn(`ExpoLinearGradient ignored a gradient rejected by ArkUI Canvas: ${String(error)}`);
    }
  }

  build(): void {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .borderRadius(this.borderRadii)
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
      .onReady((): void => {
        this.ready = true;
        this.drawGradient();
      });
  }
}

@Builder
function buildExpoLinearGradientView(context: ExpoViewContentContext): void {
  ExpoLinearGradientViewContent({ view: context.nativeView as ExpoLinearGradientView });
}

export class ExpoLinearGradientModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const view = new ExpoViewDefinition<ExpoLinearGradientView>(
      'ExpoLinearGradientView',
      (context: ExpoViewContext): ExpoLinearGradientView => new ExpoLinearGradientView(context),
      wrapBuilder(buildExpoLinearGradientView),
    )
      .groupView()
      .prop(
        'colors',
        GRADIENT_PROP,
        (view: ExpoLinearGradientView, colors: ESObject): void => {
          view.colors = colors;
        },
        [],
      )
      .prop(
        'locations',
        GRADIENT_PROP,
        (view: ExpoLinearGradientView, locations: ESObject): void => {
          view.locations = locations;
        },
        null,
      )
      .prop(
        'startPoint',
        GRADIENT_PROP,
        (view: ExpoLinearGradientView, point: ESObject): void => {
          const coords: number[] | undefined = normalizePoint(point, 0.5, 0);
          if (coords !== undefined) view.startPoint = coords;
        },
        null,
      )
      .prop(
        'endPoint',
        GRADIENT_PROP,
        (view: ExpoLinearGradientView, point: ESObject): void => {
          const coords: number[] | undefined = normalizePoint(point, 0.5, 1);
          if (coords !== undefined) view.endPoint = coords;
        },
        null,
      )
      .onDidUpdateProps((view: ExpoLinearGradientView): void => view.updateGradient());

    return new ExpoModuleDefinition().name('ExpoLinearGradient').view(view);
  }
}
