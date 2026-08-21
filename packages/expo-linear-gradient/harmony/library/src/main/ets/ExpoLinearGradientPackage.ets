import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNComponentContext, RNPackageContext } from '@rnoh/react-native-openharmony';
import { ExpoViewAdapterRegistry } from '@expo-harmony/expo-modules-core';
import type { ExpoViewAdapter, ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

const COMPONENT_NAME: string = 'ViewManagerAdapter_ExpoLinearGradient';

type GradientStop = [string, number];
type GradientRadius = number | string;

@Observed
class ExpoLinearGradientViewState {
  colors: GradientStop[] = [
    ['#00000000', 0],
    ['#00000000', 1],
  ];
  startPoint: number[] = [0.5, 0];
  endPoint: number[] = [0.5, 1];
  borderRadii: GradientRadius[] = [0, 0, 0, 0];
  private redraw?: () => void;

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

function finiteNumber(value: ESObject, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeStop(value: ESObject, _index: number, previous: number): number {
  const stop = Number(value);
  if (!Number.isFinite(stop)) return previous;

  return Math.max(previous, Math.min(1, Math.max(0, stop)));
}

function normalizePoint(point: ESObject, x: number, y: number): number[] {
  if (point === undefined || point === null) return [x, y];
  if (!Array.isArray(point) || point.length !== 2) return [x, y];

  return [finiteNumber(point[0], x), finiteNumber(point[1], y)];
}

function normalizeRadius(value: ESObject, _index: number): GradientRadius {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) return value;

  if (typeof value === 'string' && value.endsWith('%')) {
    const percentage = Number(value.slice(0, -1));
    if (Number.isFinite(percentage) && percentage >= 0) return value;
  }

  return 0;
}

function normalizeBorderRadii(radii: ESObject): GradientRadius[] {
  if (radii === undefined || radii === null) return [0, 0, 0, 0];
  if (!Array.isArray(radii)) return [0, 0, 0, 0];
  if (radii.length !== 4 && radii.length !== 8) return [0, 0, 0, 0];

  const indices: number[] = radii.length === 8
    ? [0, 2, 4, 6]
    : [0, 1, 2, 3];

  const values: GradientRadius[] = [];
  for (let index = 0; index < indices.length; index += 1) {
    const source = indices[index];
    values.push(normalizeRadius(radii[source], source));
  }

  return values;
}

function colorToString(color: ESObject): string {
  if (typeof color === 'string') return color;
  if (typeof color !== 'number' || !Number.isFinite(color)) return '#00000000';

  const argb = color >>> 0;
  return `#${argb.toString(16).padStart(8, '0')}`;
}

function normalizeColors(colors: ESObject, locations: ESObject): GradientStop[] {
  if (!Array.isArray(colors) || colors.length === 0) {
    return [
      ['#00000000', 0],
      ['#00000000', 1],
    ];
  }

  const palette: ESObject[] = (colors as ESObject[]).slice();
  if (palette.length === 1) palette.push(palette[0]);
  const offsets: ESObject[] = Array.isArray(locations) ? (locations as ESObject[]) : [];
  const count = palette.length;

  const stops: GradientStop[] = [];
  let previous: number = 0;

  for (let index = 0; index < count; index += 1) {
    const color: ESObject = palette[index];
    const fallback = Math.max(previous, index / (count - 1));
    const offset = index < offsets.length ? normalizeStop(offsets[index], index, previous) : fallback;

    previous = offset;
    stops.push([colorToString(color), offset]);
  }

  return stops;
}

@Component
struct ExpoLinearGradientViewContent {
  @ObjectLink state: ExpoLinearGradientViewState;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasReady: boolean = false;

  aboutToAppear(): void {
    this.state.attachRedraw((): void => {
      if (this.canvasReady) this.drawGradient();
    });
  }

  aboutToDisappear(): void {
    this.state.detachRedraw();
  }

  private drawGradient(): void {
    const width = this.context.width;
    const height = this.context.height;

    if (width <= 0 || height <= 0) return;

    const startX = this.state.startPoint[0] * width;
    const startY = this.state.startPoint[1] * height;
    const endX = this.state.endPoint[0] * width;
    const endY = this.state.endPoint[1] * height;

    this.context.clearRect(0, 0, width, height);

    if (startX === endX && startY === endY) {
      const last: GradientStop = this.state.colors[this.state.colors.length - 1];
      this.context.fillStyle = last[0];
      this.context.fillRect(0, 0, width, height);
      return;
    }

    const gradient = this.context.createLinearGradient(startX, startY, endX, endY);
    this.state.colors.forEach((stop: GradientStop): void => {
      gradient.addColorStop(stop[1], stop[0]);
    });

    this.context.fillStyle = gradient;
    this.context.fillRect(0, 0, width, height);
  }

  build(): void {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .borderRadius({
        topLeft: this.state.borderRadii[0],
        topRight: this.state.borderRadii[1],
        bottomRight: this.state.borderRadii[2],
        bottomLeft: this.state.borderRadii[3],
      })
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
      .onReady((): void => {
        this.canvasReady = true;
        this.drawGradient();
      })
      .onAreaChange((): void => {
        if (this.canvasReady) this.drawGradient();
      });
  }
}

@Builder
function buildExpoLinearGradientView(context: ExpoViewContentContext): void {
  ExpoLinearGradientViewContent({ state: context.nativeView as ExpoLinearGradientViewState });
}

class ExpoLinearGradientViewAdapter implements ExpoViewAdapter {
  readonly componentName: string = COMPONENT_NAME;
  readonly content: WrappedBuilder<[ExpoViewContentContext]> = wrapBuilder(buildExpoLinearGradientView);

  create(_context: RNComponentContext, _tag: number, _componentName: string): ESObject {
    return new ExpoLinearGradientViewState();
  }

  updateProps(view: ESObject, props: Record<string, ESObject>): void {
    const state = view as ExpoLinearGradientViewState;
    const colors = normalizeColors(props.colors, props.locations);
    const startPoint = normalizePoint(props.startPoint, 0.5, 0);
    const endPoint = normalizePoint(props.endPoint, 0.5, 1);
    const borderRadii = normalizeBorderRadii(props.borderRadii);

    state.colors = colors;
    state.startPoint = startPoint;
    state.endPoint = endPoint;
    state.borderRadii = borderRadii;

    state.requestRedraw();
  }
}

let registered: boolean = false;

function registerExpoLinearGradientView(): void {
  if (registered) return;
  ExpoViewAdapterRegistry.register(new ExpoLinearGradientViewAdapter());
  registered = true;
}

export class ExpoLinearGradientPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
    registerExpoLinearGradientView();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-linear-gradient';
  }
}
