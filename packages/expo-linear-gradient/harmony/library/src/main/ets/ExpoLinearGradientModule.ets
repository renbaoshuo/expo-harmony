/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ColorMetrics } from '@kit.ArkUI';
import {
  ExpoEither,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

type GradientColor = ExpoEither<number, string> | null | undefined;
type GradientNumber = number | null | undefined;
type GradientRadius = ExpoEither<number, string>;
type CanvasRadius = number | string;
type GradientStop = [string, number];

// Invalid colors and incomplete points can arrive as null array entries from upstream JS.
const COLOR_TYPE = ExpoValueTypes.either(ExpoValueTypes.number(), ExpoValueTypes.string()).nullable().optional();
const COLORS_TYPE = ExpoValueTypes.array(COLOR_TYPE);
const NUMBERS_TYPE = ExpoValueTypes.array(ExpoValueTypes.number().nullable().optional()).nullable();
const RADIUS_TYPE = ExpoValueTypes.either(ExpoValueTypes.number(), ExpoValueTypes.string());
const BORDER_RADII_TYPE = ExpoValueTypes.array(RADIUS_TYPE).nullable();

interface Gradient {
  readonly stops: GradientStop[];
  readonly startPoint: number[];
  readonly endPoint: number[];
}

@Observed
class ExpoLinearGradientView extends ExpoView {
  colors: GradientColor[] = [];
  locations: GradientNumber[] | null = null;
  startPoint: number[] = [0.5, 0];
  endPoint: number[] = [0.5, 1];
  borderRadii: CanvasRadius[] = [0, 0, 0, 0];
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
      console.warn('ExpoLinearGradient ignored an invalid colors or locations update.');
      return;
    }

    // A resized or recreated canvas needs to repaint even after an invalid prop update.
    this.gradient = { stops, startPoint: this.startPoint, endPoint: this.endPoint };
    this.redraw?.();
  }
}

function colorToString(color: GradientColor): string | undefined {
  if (color === undefined || color === null) return undefined;
  if (color.isFirst) {
    const value: number | undefined = color.first;
    if (value === undefined || !Number.isFinite(value) || !Number.isInteger(value) || value < -2147483648 || value > 4294967295) {
      return undefined;
    }

    const argb: number = value >>> 0;

    return `#${argb.toString(16).padStart(8, '0')}`;
  }

  const value: string | undefined = color.second?.trim();
  if (value === undefined || value.length === 0) return undefined;

  try {
    // Canvas can silently ignore invalid color strings instead of throwing.
    ColorMetrics.resourceColor(value);
    return value;
  } catch {
    return undefined;
  }
}

function gradientStops(colors: GradientColor[], locations: GradientNumber[] | null): GradientStop[] | undefined {
  if (colors.length < 2) return undefined;
  if (locations !== null && locations.length !== colors.length) return undefined;

  const stops: GradientStop[] = [];
  let previous: number = -1;

  for (let index = 0; index < colors.length; index += 1) {
    const color: string | undefined = colorToString(colors[index]);
    if (color === undefined) return undefined;

    const offset: GradientNumber = locations === null ? index / (colors.length - 1) : locations[index];
    if (typeof offset !== 'number' || !Number.isFinite(offset) || offset < 0 || offset > 1 || offset < previous) {
      return undefined;
    }

    previous = offset;
    stops.push([color, offset]);
  }

  return stops;
}

function normalizePoint(point: GradientNumber[] | null, x: number, y: number): number[] | undefined {
  if (point === null) return [x, y];

  const pointX: GradientNumber = point[0];
  const pointY: GradientNumber = point[1];
  if (point.length !== 2 || typeof pointX !== 'number' || typeof pointY !== 'number' || !Number.isFinite(pointX) || !Number.isFinite(pointY)) {
    return undefined;
  }

  return [pointX, pointY];
}

function normalizeRadius(radius: GradientRadius): CanvasRadius | undefined {
  if (radius.isFirst) {
    const value: number | undefined = radius.first;
    return value !== undefined && Number.isFinite(value) && value >= 0 ? value : undefined;
  }

  const value: string | undefined = radius.second?.trim();
  if (value === undefined || !/^\+?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?%$/i.test(value)) return undefined;

  const percentage: number = Number(value.slice(0, -1));
  return Number.isFinite(percentage) ? `${percentage}%` : undefined;
}

function normalizeBorderRadii(radii: GradientRadius[] | null): CanvasRadius[] | undefined {
  if (radii === null) return [0, 0, 0, 0];
  if (radii.length !== 4) return undefined;

  const normalized: CanvasRadius[] = [];

  for (let index = 0; index < radii.length; index += 1) {
    const radius: CanvasRadius | undefined = normalizeRadius(radii[index]);
    if (radius === undefined) return undefined;

    normalized.push(radius);
  }

  return normalized;
}

@Component
struct ExpoLinearGradientViewContent {
  @ObjectLink view: ExpoLinearGradientView;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;
  private readonly redraw = (): void => {
    if (this.ready) this.drawGradient();
  };

  aboutToAppear(): void {
    this.view.attachRedraw(this.redraw);
  }

  aboutToDisappear(): void {
    this.ready = false;
    this.view.detachRedraw(this.redraw);
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
      .borderRadius({
        topLeft: this.view.borderRadii[0],
        topRight: this.view.borderRadii[1],
        bottomRight: this.view.borderRadii[2],
        bottomLeft: this.view.borderRadii[3],
      })
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
      .onReady((): void => {
        this.ready = true;
        this.drawGradient();
      })
      .onAreaChange(this.redraw);
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
      .prop(
        'colors',
        COLORS_TYPE,
        (view: ExpoLinearGradientView, colors: GradientColor[]): void => {
          view.colors = colors;
        },
        [],
      )
      .prop(
        'locations',
        NUMBERS_TYPE,
        (view: ExpoLinearGradientView, locations: GradientNumber[] | null): void => {
          view.locations = locations;
        },
        null,
      )
      .prop(
        'startPoint',
        NUMBERS_TYPE,
        (view: ExpoLinearGradientView, point: GradientNumber[] | null): void => {
          const normalized: number[] | undefined = normalizePoint(point, 0.5, 0);
          if (normalized !== undefined) view.startPoint = normalized;
        },
        null,
      )
      .prop(
        'endPoint',
        NUMBERS_TYPE,
        (view: ExpoLinearGradientView, point: GradientNumber[] | null): void => {
          const normalized: number[] | undefined = normalizePoint(point, 0.5, 1);
          if (normalized !== undefined) view.endPoint = normalized;
        },
        null,
      )
      .prop(
        'borderRadii',
        BORDER_RADII_TYPE,
        (view: ExpoLinearGradientView, radii: GradientRadius[] | null): void => {
          const normalized: CanvasRadius[] | undefined = normalizeBorderRadii(radii);
          if (normalized !== undefined) view.borderRadii = normalized;
        },
        null,
      )
      .onDidUpdateProps((view: ExpoLinearGradientView): void => view.updateGradient());

    return new ExpoModuleDefinition().name('ExpoLinearGradient').view(view);
  }
}
