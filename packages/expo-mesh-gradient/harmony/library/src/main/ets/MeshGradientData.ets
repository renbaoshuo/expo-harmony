/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Copyright 2024-present 650 Industries. All rights reserved. MIT licensed.
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { interpolateColor } from './MeshGradientColors';

export const DEFAULT_RESOLUTION: number = 8;
// Drawing's indexed triangles use uint16 indices, as does Android Canvas.
const MAX_VERTEX_COUNT: number = 1 << 16;

export interface MeshGradientData {
  positions: common2D.Point[];
  colors: number[];
  indices: number[];
}

enum SegmentPosition {
  FIRST,
  INTERIOR,
  LAST,
}

function segmentPosition(index: number, last: number): SegmentPosition {
  if (index === 0) return SegmentPosition.FIRST;
  return index === last - 1 ? SegmentPosition.LAST : SegmentPosition.INTERIOR;
}

function cubicPath(start: common2D.Point, end: common2D.Point, position: SegmentPosition, horizontal: boolean): drawing.Path {
  const dx = horizontal ? (end.x - start.x) * 0.5 : 0;
  const dy = horizontal ? 0 : (end.y - start.y) * 0.5;

  const path = new drawing.Path();
  path.moveTo(start.x, start.y);
  path.cubicTo(
    start.x + (position === SegmentPosition.FIRST ? 0 : dx),
    start.y + (position === SegmentPosition.FIRST ? 0 : dy),
    end.x - (position === SegmentPosition.LAST ? 0 : dx),
    end.y - (position === SegmentPosition.LAST ? 0 : dy),
    end.x,
    end.y,
  );
  path.lineTo(end.x, end.y);

  return path;
}

function sample(path: drawing.Path, distance: number, fallback: common2D.Point): common2D.Point {
  const point: common2D.Point = { x: fallback.x, y: fallback.y };
  const tangent: common2D.Point = { x: 0, y: 0 };

  // A collapsed edge has no tangent. Keep its coincident endpoint finite.
  if (!path.getPositionAndTangent(false, distance, point, tangent) && distance !== 0) {
    throw new Error('ExpoMeshGradient could not sample the mesh path.');
  }

  if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) {
    throw new Error('ExpoMeshGradient path coordinates must be finite.');
  }

  return point;
}

export function createMesh(
  columns: number,
  rows: number,
  points: number[][],
  colors: number[],
  stepsX: number,
  stepsY: number,
  smooth: boolean,
): MeshGradientData | undefined {
  if (
    !Number.isSafeInteger(columns) ||
    columns < 0 ||
    !Number.isSafeInteger(rows) ||
    rows < 0 ||
    !Number.isSafeInteger(stepsX) ||
    stepsX < 1 ||
    !Number.isSafeInteger(stepsY) ||
    stepsY < 1
  ) {
    throw new Error('ExpoMeshGradient requires non-negative integer dimensions and positive integer resolution.');
  }

  if (columns === 0 || rows === 0) return undefined;
  if (points.length !== columns * rows || colors.length !== columns * rows) {
    throw new Error('ExpoMeshGradient points and colors must each contain columns * rows elements.');
  }

  const width = (columns - 1) * stepsX + 1;
  const height = (rows - 1) * stepsY + 1;
  const count = width * height;

  if (!Number.isSafeInteger(count) || count > MAX_VERTEX_COUNT) {
    throw new Error(`ExpoMeshGradient supports at most ${MAX_VERTEX_COUNT} sampled vertices. Reduce resolution or dimensions.`);
  }

  for (let i = 0; i < points.length; i += 1) {
    const point = points[i];

    if (point.length !== 2 || !Number.isFinite(Math.fround(point[0])) || !Number.isFinite(Math.fround(point[1]))) {
      throw new Error('ExpoMeshGradient points must contain two finite float coordinates.');
    }
    if (!Number.isInteger(colors[i]) || colors[i] < -2147483648 || colors[i] > 4294967295) {
      throw new Error('ExpoMeshGradient colors must be processed 32-bit ARGB integers.');
    }
  }

  if (columns < 2 || rows < 2) return undefined;

  const mesh: MeshGradientData = { positions: [], colors: [], indices: [] };

  for (let y = 0; y < rows; y += 1) {
    for (let x = 0; x < columns; x += 1) {
      const source = y * columns + x;
      const target = y * stepsY * width + x * stepsX;
      const start: common2D.Point = { x: points[source][0], y: points[source][1] };

      mesh.positions[target] = start;
      mesh.colors[target] = colors[source] >>> 0;

      if (x === columns - 1 || stepsX === 1) continue;

      const end: common2D.Point = { x: points[source + 1][0], y: points[source + 1][1] };
      const path = cubicPath(start, end, segmentPosition(x, columns - 1), true);
      const length = path.getLength(false);

      for (let step = 1; step < stepsX; step += 1) {
        const fraction = step / stepsX;

        mesh.positions[target + step] = sample(path, fraction * length, start);
        mesh.colors[target + step] = interpolateColor(colors[source], colors[source + 1], fraction, smooth);
      }
    }
  }

  for (let y = 0; y < rows - 1; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (stepsY === 1) continue;

      const start = y * stepsY * width + x;
      const end = (y + 1) * stepsY * width + x;

      // Android uses the column boundary here, even for rectangular meshes.
      const path = cubicPath(mesh.positions[start], mesh.positions[end], segmentPosition(y, columns - 1), false);
      const length = path.getLength(false);

      for (let step = 1; step < stepsY; step += 1) {
        const fraction = step / stepsY;
        const target = start + step * width;

        mesh.positions[target] = sample(path, fraction * length, mesh.positions[start]);
        mesh.colors[target] = interpolateColor(mesh.colors[start], mesh.colors[end], fraction, smooth);
      }
    }
  }

  for (let y = 0; y < height - 1; y += 1) {
    for (let x = 0; x < width - 1; x += 1) {
      const a = y * width + x;
      const b = a + 1;
      const c = a + width;
      const d = c + 1;

      mesh.indices.push(a, c, d, a, b, d);
    }
  }

  return mesh;
}
