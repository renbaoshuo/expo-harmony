/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Ported from expo-dev-menu/android/.../fab/{FabState,FabUtils,ExpoVelocityTracker}.kt.
// Copyright 2015-present 650 Industries. All rights reserved. MIT licensed.
export const FAB_CONTENT_SIZE: number = 52;
export const FAB_LABEL_HEIGHT: number = 94;
export const FAB_MARGIN: number = 16;
export const FAB_WIDTH: number = FAB_CONTENT_SIZE + FAB_MARGIN * 2;
export const FAB_HEIGHT: number = FAB_WIDTH;
export const FAB_HIT_AREA_ID: string = 'expo-dev-menu-fab-hit-area';

export class FabPoint {
  x: number;
  y: number;
  constructor(x: number = 0, y: number = 0) {
    this.x = x;
    this.y = y;
  }
}

export class FabInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
  constructor(top: number = 0, right: number = 0, bottom: number = 0, left: number = 0) {
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.left = left;
  }
}

export class FabBounds {
  readonly minX: number;
  readonly minY: number;
  readonly maxX: number;
  readonly maxY: number;
  readonly displayable: boolean;
  readonly width: number;
  readonly height: number;

  constructor(width: number, height: number, insets: FabInsets = new FabInsets()) {
    this.width = width;
    this.height = height;
    this.minX = insets.left;
    this.minY = insets.top;
    this.maxX = Math.max(this.minX, width - FAB_WIDTH - insets.right);
    this.maxY = Math.max(this.minY, height - FAB_HEIGHT - insets.bottom);
    this.displayable = width - insets.left - insets.right >= FAB_WIDTH && height - insets.top - insets.bottom >= FAB_HEIGHT;
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(value, max));
}

export function restoreFabPosition(saved: FabPoint | undefined, bounds: FabBounds): FabPoint {
  if (saved === undefined || !Number.isFinite(saved.x) || !Number.isFinite(saved.y)) return new FabPoint(bounds.maxX, bounds.minY);

  return new FabPoint(
    bounds.minX + clamp(saved.x, 0, 1) * (bounds.maxX - bounds.minX),
    bounds.minY + clamp(saved.y, 0, 1) * (bounds.maxY - bounds.minY),
  );
}

export function normalizeFabPosition(point: FabPoint, bounds: FabBounds): FabPoint {
  return new FabPoint(
    bounds.maxX > bounds.minX ? clamp((point.x - bounds.minX) / (bounds.maxX - bounds.minX), 0, 1) : 0,
    bounds.maxY > bounds.minY ? clamp((point.y - bounds.minY) / (bounds.maxY - bounds.minY), 0, 1) : 0,
  );
}

export function fabTarget(point: FabPoint, velocity: FabPoint, bounds: FabBounds): FabPoint {
  // Keep Android's 100ms momentum projection and its exact edge-selection expression.
  const center = point.x - bounds.minX + FAB_WIDTH / 2 + velocity.x / 10;
  return new FabPoint(
    center < (bounds.maxX - bounds.minX) / 2 ? bounds.minX : bounds.maxX,
    clamp(point.y + velocity.y / 10, bounds.minY, bounds.maxY),
  );
}

class FabSample {
  readonly point: FabPoint;
  readonly time: number;
  constructor(point: FabPoint, time: number) {
    this.point = point;
    this.time = time;
  }
}

/** Touch coordinates and positions are vp; the caller converts Android's 40 physical-pixel tolerance. */
export class FabDrag {
  private previous: FabPoint = new FabPoint();
  private samples: FabSample[] = [];
  private distance: number = 0;
  position: FabPoint = new FabPoint();
  dragging: boolean = false;

  begin(pointer: FabPoint, position: FabPoint): void {
    this.previous = pointer;
    this.position = position;
    this.distance = 0;
    this.dragging = false;
    this.samples = [];
  }

  move(pointer: FabPoint, bounds: FabBounds, tolerance: number, time: number, height: number = FAB_HEIGHT): void {
    const dx = pointer.x - this.previous.x;
    const dy = pointer.y - this.previous.y;
    this.previous = pointer;
    this.distance += Math.hypot(dx, dy);
    this.position = new FabPoint(
      clamp(this.position.x + dx, bounds.minX - FAB_WIDTH / 2, bounds.maxX + FAB_WIDTH / 2),
      clamp(this.position.y + dy, bounds.minY - height / 2, bounds.maxY + height / 2),
    );
    this.dragging = this.distance > tolerance;
    this.samples.push(new FabSample(this.position, time));
    this.prune(time);
  }

  velocity(time: number): FabPoint {
    this.prune(time);
    if (this.samples.length < 2) return new FabPoint();
    const first = this.samples[0];
    const last = this.samples[this.samples.length - 1];
    const seconds = (last.time - first.time) / 1000;
    return seconds <= 0 ? new FabPoint() : new FabPoint((last.point.x - first.point.x) / seconds, (last.point.y - first.point.y) / seconds);
  }

  private prune(time: number): void {
    while (this.samples.length > 0 && this.samples[0].time < time - 100) this.samples.shift();
  }
}
