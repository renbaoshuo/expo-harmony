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

type GradientColor = ExpoEither<number, string>;
type GradientRadius = ExpoEither<number, string>;
type CanvasRadius = number | string;
type GradientStop = [string, number];

const COLOR_TYPE = ExpoValueTypes.either(ExpoValueTypes.number(), ExpoValueTypes.string());
const COLORS_TYPE = ExpoValueTypes.array(COLOR_TYPE);
const LOCATIONS_TYPE = ExpoValueTypes.array(ExpoValueTypes.number()).nullable();
const POINT_TYPE = ExpoValueTypes.array(ExpoValueTypes.number()).nullable();
const RADIUS_TYPE = ExpoValueTypes.either(ExpoValueTypes.number(), ExpoValueTypes.string());
const BORDER_RADII_TYPE = ExpoValueTypes.array(RADIUS_TYPE).nullable();

@Observed
class ExpoLinearGradientView extends ExpoView {
  colors: GradientColor[] = [];
  locations: number[] | null = null;
  startPoint: number[] = [0.5, 0];
  endPoint: number[] = [0.5, 1];
  borderRadii: CanvasRadius[] = [0, 0, 0, 0];
  private redraw?: () => void;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  attachRedraw(callback: () => void): void {
    this.redraw = callback;
  }

  detachRedraw(): void {
    this.redraw = undefined;
  }

  requestRedraw(): void {
    this.redraw?.();
  }
}

function colorToString(color: GradientColor): string | undefined {
  if (color.isFirst) {
    const value: number | undefined = color.first;
    if (value === undefined || !Number.isFinite(value) || !Number.isInteger(value) || value < -2147483648 || value > 4294967295) {
      return undefined;
    }

    const argb: number = value >>> 0;

    return `#${argb.toString(16).padStart(8, '0')}`;
  }

  const value: string | undefined = color.second;
  return value !== undefined && value.length > 0 ? value : undefined;
}

function gradientStops(colors: GradientColor[], locations: number[] | null): GradientStop[] | undefined {
  if (colors.length < 2) return undefined;
  if (locations !== null && locations.length !== colors.length) return undefined;

  const stops: GradientStop[] = [];
  let previous: number = -1;
  for (let index = 0; index < colors.length; index += 1) {
    const color: string | undefined = colorToString(colors[index]);
    if (color === undefined) return undefined;

    const offset: number = locations === null ? index / (colors.length - 1) : locations[index];
    if (!Number.isFinite(offset) || offset < 0 || offset > 1 || offset < previous) {
      return undefined;
    }

    previous = offset;
    stops.push([color, offset]);
  }

  return stops;
}

function normalizePoint(point: number[] | null, x: number, y: number): number[] | undefined {
  if (point === null) return [x, y];
  if (point.length !== 2 || !Number.isFinite(point[0]) || !Number.isFinite(point[1])) {
    return undefined;
  }

  return [point[0], point[1]];
}

function normalizeRadius(radius: GradientRadius): CanvasRadius | undefined {
  if (radius.isFirst) {
    const value: number | undefined = radius.first;
    return value !== undefined && Number.isFinite(value) && value >= 0 ? value : undefined;
  }

  const value: string | undefined = radius.second;
  if (value === undefined || !value.endsWith('%')) return undefined;

  const percentage: number = Number(value.slice(0, -1));
  return Number.isFinite(percentage) && percentage >= 0 ? value : undefined;
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

  aboutToAppear(): void {
    this.view.attachRedraw((): void => {
      if (this.ready) this.drawGradient();
    });
  }

  aboutToDisappear(): void {
    this.view.detachRedraw();
  }

  private drawGradient(): void {
    const width: number = this.context.width;
    const height: number = this.context.height;
    if (width <= 0 || height <= 0) return;

    const stops: GradientStop[] | undefined = gradientStops(this.view.colors, this.view.locations);
    if (stops === undefined) {
      console.warn('ExpoLinearGradient ignored an invalid colors or locations update.');
      return;
    }

    const startX: number = this.view.startPoint[0] * width;
    const startY: number = this.view.startPoint[1] * height;
    const endX: number = this.view.endPoint[0] * width;
    const endY: number = this.view.endPoint[1] * height;

    try {
      const gradient = this.context.createLinearGradient(startX, startY, endX, endY);
      stops.forEach((stop: GradientStop): void => gradient.addColorStop(stop[1], stop[0]));

      this.context.clearRect(0, 0, width, height);
      this.context.fillStyle = gradient;
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
      .onAreaChange((): void => {
        if (this.ready) this.drawGradient();
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
        LOCATIONS_TYPE,
        (view: ExpoLinearGradientView, locations: number[] | null): void => {
          view.locations = locations;
        },
        null,
      )
      .prop(
        'startPoint',
        POINT_TYPE,
        (view: ExpoLinearGradientView, point: number[] | null): void => {
          const normalized: number[] | undefined = normalizePoint(point, 0.5, 0);
          if (normalized !== undefined) view.startPoint = normalized;
        },
        null,
      )
      .prop(
        'endPoint',
        POINT_TYPE,
        (view: ExpoLinearGradientView, point: number[] | null): void => {
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
      .prop('dither', ExpoValueTypes.boolean().nullable(), (_view: ExpoLinearGradientView, _dither: boolean | null): void => {}, true)
      .onDidUpdateProps((view: ExpoLinearGradientView): void => view.requestRedraw());

    return new ExpoModuleDefinition().name('ExpoLinearGradient').view(view);
  }
}
