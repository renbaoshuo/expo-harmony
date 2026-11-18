/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { drawing } from '@kit.ArkGraphics2D';
import { DrawContext, FrameNode, NodeController, RenderNode, Size, UIContext } from '@kit.ArkUI';
import {
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoRecordShape,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { createMesh, DEFAULT_RESOLUTION, MeshGradientData } from './MeshGradientData';

const DRAWING_CAPABILITY = 'SystemCapability.Graphics.Drawing';
// Keep invalid values in the same prop update so validation can clear the old mesh.
const MESH_NUMBER = ExpoValueTypes.custom<number>(
  'MeshNumber',
  (value: ESObject): number => typeof value === 'number' ? value : NaN,
  (value: number): ESObject => value,
);

interface MeshResolution {
  x?: number;
  y?: number;
}

const MESH_RESOLUTION_RECORD = ExpoValueTypes.shapedRecord<MeshResolution>(
  'MeshResolution',
  new ExpoRecordShape().field('x', MESH_NUMBER.optional()).field('y', MESH_NUMBER.optional()),
  (fields: Record<string, ESObject>): MeshResolution => fields as MeshResolution,
  (value: MeshResolution): Record<string, ESObject> => value as Record<string, ESObject>,
);

const MESH_RESOLUTION = ExpoValueTypes.custom<MeshResolution>(
  'MeshResolution',
  (value: ESObject, path: string): MeshResolution => {
    try {
      return MESH_RESOLUTION_RECORD.decode(value, path);
    } catch {
      return { x: NaN };
    }
  },
  (value: MeshResolution, path: string): ESObject | void => MESH_RESOLUTION_RECORD.encode(value, path),
);

@Observed
class ExpoMeshGradientView extends ExpoView {
  columns: number = 0;
  rows: number = 0;
  points: number[][] = [];
  colors: number[] = [];
  resolution: MeshResolution = {};
  smoothsColors: boolean = true;
  mesh?: MeshGradientData;
  redraw?: (mesh: MeshGradientData | undefined) => void;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  update(): void {
    this.mesh = undefined;

    try {
      if (canIUse(DRAWING_CAPABILITY)) {
        this.mesh = createMesh(
          this.columns,
          this.rows,
          this.points,
          this.colors,
          this.resolution.x ?? DEFAULT_RESOLUTION,
          this.resolution.y ?? DEFAULT_RESOLUTION,
          this.smoothsColors,
        );
      }
    } catch (error) {
      console.warn(`ExpoMeshGradient cleared an invalid mesh: ${String(error)}`);
    }

    this.redraw?.(this.mesh);
  }
}

class MeshRenderNode extends RenderNode {
  mesh?: MeshGradientData;

  override draw(context: DrawContext): void {
    const mesh = this.mesh;
    if (mesh === undefined) return;

    const size = context.sizeInPixel;
    if (size.width <= 0 || size.height <= 0) return;

    const canvas = context.canvas;
    canvas.save();

    try {
      canvas.scale(size.width, size.height);
      // DST selects the vertex colors. The default brush composites them with SRC_OVER.
      canvas.drawVertices(
        drawing.VertexMode.TRIANGLES_VERTEXMODE,
        mesh.positions.length,
        mesh.positions,
        null,
        mesh.colors,
        mesh.indices.length,
        mesh.indices,
        drawing.BlendMode.DST,
      );
    } catch (error) {
      console.warn(`ExpoMeshGradient could not draw the mesh: ${String(error)}`);
    } finally {
      canvas.restore();
    }
  }
}

class MeshNodeController extends NodeController {
  private frame?: FrameNode;
  private node?: MeshRenderNode;
  private mesh?: MeshGradientData;

  override makeNode(context: UIContext): FrameNode {
    if (this.frame === undefined) {
      this.frame = new FrameNode(context);
      const root = this.frame.getRenderNode();

      if (root !== null) {
        const node = new MeshRenderNode();
        node.mesh = this.mesh;
        node.clipToFrame = true;

        try {
          root.appendChild(node);
          this.node = node;
        } catch (error) {
          node.dispose();
          console.warn(`ExpoMeshGradient could not attach its render node: ${String(error)}`);
        }
      }
    }

    return this.frame;
  }

  override aboutToResize(size: Size): void {
    const root = this.frame?.getRenderNode();
    if (root !== undefined && root !== null) root.size = size;

    if (this.node !== undefined) {
      this.node.size = size;
      this.node.invalidate();
    }
  }

  update(mesh: MeshGradientData | undefined): void {
    this.mesh = mesh;

    if (this.node !== undefined) {
      this.node.mesh = mesh;
      this.node.invalidate();
    }
  }

  dispose(): void {
    const frame = this.frame;
    const node = this.node;

    this.node = undefined;
    this.frame = undefined;
    this.mesh = undefined;

    try {
      if (node !== undefined) frame?.getRenderNode()?.removeChild(node);
    } catch (error) {
      console.warn(`ExpoMeshGradient could not detach its render node: ${String(error)}`);
    } finally {
      try {
        node?.dispose();
      } finally {
        frame?.dispose();
      }
    }
  }
}

@Component
struct ExpoMeshGradientContent {
  @ObjectLink view: ExpoMeshGradientView;
  private controller: MeshNodeController = new MeshNodeController();
  private readonly redraw = (mesh: MeshGradientData | undefined): void => this.controller.update(mesh);

  aboutToAppear(): void {
    this.view.redraw = this.redraw;
    this.redraw(this.view.mesh);
  }

  aboutToDisappear(): void {
    if (this.view.redraw === this.redraw) this.view.redraw = undefined;
    this.controller.dispose();
  }

  build(): void {
    NodeContainer(this.controller)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None);
  }
}

@Builder
function buildMeshGradient(context: ExpoViewContentContext): void {
  ExpoMeshGradientContent({ view: context.nativeView as ExpoMeshGradientView });
}

export class ExpoMeshGradientModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const view = new ExpoViewDefinition<ExpoMeshGradientView>(
      'MeshGradientView',
      (context: ExpoViewContext): ExpoMeshGradientView => new ExpoMeshGradientView(context),
      wrapBuilder(buildMeshGradient),
    )
      .groupView()
      .prop(
        'columns',
        MESH_NUMBER,
        (view: ExpoMeshGradientView, value: number): void => {
          view.columns = value;
        },
        0,
      )
      .prop(
        'rows',
        MESH_NUMBER,
        (view: ExpoMeshGradientView, value: number): void => {
          view.rows = value;
        },
        0,
      )
      .prop(
        'points',
        ExpoValueTypes.array(ExpoValueTypes.array(MESH_NUMBER).defaulted([])),
        (view: ExpoMeshGradientView, value: number[][]): void => {
          view.points = value;
        },
        [],
      )
      .prop(
        'colors',
        ExpoValueTypes.array(MESH_NUMBER),
        (view: ExpoMeshGradientView, value: number[]): void => {
          view.colors = value;
        },
        [],
      )
      .prop(
        'resolution',
        MESH_RESOLUTION,
        (view: ExpoMeshGradientView, value: MeshResolution): void => {
          view.resolution = value;
        },
        {},
      )
      .prop(
        'smoothsColors',
        ExpoValueTypes.boolean(),
        (view: ExpoMeshGradientView, value: boolean): void => {
          view.smoothsColors = value;
        },
        true,
      )
      .onDidUpdateProps((view: ExpoMeshGradientView): void => view.update())
      .onDestroy((view: ExpoMeshGradientView): void => {
        view.mesh = undefined;
        const redraw = view.redraw;
        view.redraw = undefined;
        redraw?.(undefined);
      });

    return new ExpoModuleDefinition().name('ExpoMeshGradient').view(view);
  }
}
