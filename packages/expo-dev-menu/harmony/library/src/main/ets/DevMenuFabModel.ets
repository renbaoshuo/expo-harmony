/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { curves, UIContext } from '@kit.ArkUI';
import { DevMenuPreferences } from './DevMenuPreferences';
import {
  FAB_WIDTH, FAB_CONTENT_SIZE, FAB_LABEL_HEIGHT, FAB_MARGIN, FAB_HIT_AREA_ID,
  FabBounds, FabDrag, FabPoint, fabTarget, normalizeFabPosition, restoreFabPosition,
} from './DevMenuFabGeometry';

@Observed
export class DevMenuFabModel {
  rendered: boolean = false;
  interactive: boolean = false;
  x: number = 0;
  y: number = 0;
  alpha: number = 0;
  idleAlpha: number = 1;
  blue: number = 0xff007aff;
  blueBorder: number = 0x4d007aff;
  scale: number = 1;
  labelAlpha: number = 1;
  labelScale: number = 1;
  labelVisible: boolean = true;
  bounds: FabBounds = new FabBounds(0, 0);
  origin: FabPoint = new FabPoint();
  ui?: UIContext;
  onHidden?: () => void;
  private enabled: boolean = false;
  private menuOpen: boolean = false;
  private showing: boolean = false;
  private generation: number = 0;
  private idleTimer?: number;
  private labelTimer?: number;
  private pointerId?: number;
  private lastTouchUp: number = 0;
  private readonly drag: FabDrag = new FabDrag();
  private resting: FabPoint = new FabPoint();
  private normalized?: FabPoint;
  private readonly preferences: DevMenuPreferences;
  private readonly open: () => void;

  constructor(preferences: DevMenuPreferences, open: () => void) {
    this.preferences = preferences;
    this.open = open;
    this.normalized = preferences.getFabPosition();
  }

  updateBounds(bounds: FabBounds): void {
    if (
      this.bounds.width === bounds.width &&
      this.bounds.height === bounds.height &&
      this.bounds.minX === bounds.minX &&
      this.bounds.minY === bounds.minY &&
      this.bounds.maxX === bounds.maxX &&
      this.bounds.maxY === bounds.maxY
    )
      return;
    this.bounds = bounds;
    this.resting = restoreFabPosition(this.normalized, bounds);
    // Resize the safe area without resetting a pointer interaction in progress.
    if (this.pointerId !== undefined) {
      this.setVisible(this.enabled, this.menuOpen);
      return;
    }
    this.animate({ duration: 0 }, (): void => {
      this.x = this.menuOpen ? this.offscreenX() : this.resting.x;
      this.y = this.resting.y;
      this.scale = 1;
    });
    this.setVisible(this.enabled, this.menuOpen);
  }

  setVisible(enabled: boolean, menuOpen: boolean): void {
    const menuChanged = this.menuOpen !== menuOpen;
    this.enabled = enabled;
    this.menuOpen = menuOpen;

    const showing = enabled && this.bounds.displayable && this.ui !== undefined;
    this.interactive = showing && !menuOpen;
    if (showing !== this.showing) {
      this.showing = showing;

      const generation = ++this.generation;
      this.pointerId = undefined;
      if (showing) {
        this.rendered = true;
        this.labelAlpha = 1;
        this.labelScale = 1;
        this.labelVisible = true;
        this.x = menuOpen ? this.offscreenX() : this.resting.x;
        this.y = this.resting.y;
        this.animate({ curve: curves.interpolatingSpring(0, 1, 400, 40) }, (): void => {
          this.alpha = 1;
        });
        this.interact();
        this.labelTimer = setTimeout((): void => {
          this.labelTimer = undefined;
          this.animate(
            {
              curve: curves.interpolatingSpring(0, 1, 400, 40),
              onFinish: (): void => {
                if (generation === this.generation) this.labelVisible = false;
              },
            },
            (): void => {
              this.labelAlpha = 0;
              this.labelScale = 0;
            },
          );
        }, 10000);
      } else {
        this.clearTimers();
        this.animate(
          {
            curve: curves.interpolatingSpring(0, 1, 400, 40),
            onFinish: (): void => {
              if (generation === this.generation && !this.showing) {
                this.rendered = false;
                this.onHidden?.();
              }
            },
          },
          (): void => {
            this.alpha = 0;
            this.scale = 1;
          },
        );
      }
    } else if (showing && menuChanged) {
      this.pointerId = undefined;
      this.scale = 1;
      if (menuOpen) {
        this.animate({ duration: 500, curve: curves.cubicBezierCurve(0.4, 0, 0.2, 1) }, (): void => {
          this.x = this.offscreenX();
        });
      } else {
        this.springTo(this.resting, new FabPoint(), 0.6);
        this.interact();
      }
    }
  }

  touch(event: TouchEvent): void {
    if (!this.interactive) return;
    event.stopPropagation();
    if (event.type === TouchType.Down && this.pointerId === undefined) {
      const point = event.changedTouches[0];
      if (point === undefined) return;
      this.pointerId = point.id;
      // Interrupt a running snap at its rendered position, not at the old animation target.
      const rendered = this.ui?.getFrameNodeById(FAB_HIT_AREA_ID)?.getPositionToWindowWithTransform();
      if (rendered !== undefined) {
        this.animate({ duration: 0 }, (): void => {
          this.x = rendered.x - this.origin.x - FAB_MARGIN;
          this.y = rendered.y - this.origin.y - FAB_MARGIN;
        });
      }
      this.drag.begin(new FabPoint(point.windowX, point.windowY), new FabPoint(this.x, this.y));
      this.interact();
      this.press(true);

      return;
    }

    const point = event.changedTouches.find((touch: TouchObject): boolean => touch.id === this.pointerId);
    if (event.type === TouchType.Cancel) {
      this.finishTouch(true);
      return;
    }
    if (point === undefined || this.pointerId === undefined) return;
    if (event.type === TouchType.Move) {
      const height = (this.labelVisible ? FAB_LABEL_HEIGHT : FAB_CONTENT_SIZE) + FAB_MARGIN * 2;
      this.drag.move(new FabPoint(point.windowX, point.windowY), this.bounds, this.ui?.px2vp(40) ?? 40, Date.now(), height);
      if (this.drag.dragging) {
        this.press(false);
        this.animate({ curve: curves.interpolatingSpring(0, 1, 1500, 2 * Math.sqrt(1500)) }, (): void => {
          this.x = this.drag.position.x;
          this.y = this.drag.position.y;
        });
      }
    } else if (event.type === TouchType.Up) this.finishTouch(false);
  }

  click(event: ClickEvent): void {
    // Touch is handled above, including the 40px click/drag tolerance. Keep keyboard,
    // accessibility and mouse activation without opening twice for synthetic clicks.
    if (event.source !== SourceType.TouchScreen && Date.now() - this.lastTouchUp > 100 && this.interactive) {
      this.interact();
      this.open();
    }
  }

  private finishTouch(cancelled: boolean): void {
    if (this.pointerId === undefined) return;
    this.pointerId = undefined;
    this.lastTouchUp = Date.now();
    this.press(false);
    this.interact();
    if (this.drag.dragging || cancelled) {
      const velocity = cancelled ? new FabPoint() : this.drag.velocity(Date.now());
      this.resting = fabTarget(new FabPoint(this.x, this.y), velocity, this.bounds);
      this.normalized = normalizeFabPosition(this.resting, this.bounds);
      this.springTo(this.resting, velocity, 0.65);
      this.preferences.saveFabPosition(this.normalized).catch((error: Error): void => console.warn(`Expo Dev Menu: ${error.message}`));
    } else this.open();
  }

  private press(pressed: boolean): void {
    this.animate({ curve: curves.interpolatingSpring(0, 1, 1500, 2 * Math.sqrt(1500)) }, (): void => {
      this.scale = pressed ? 0.9 : 1;
    });
  }

  private springTo(point: FabPoint, velocity: FabPoint, ratio: number): void {
    const dx = point.x - this.x;
    const dy = point.y - this.y;
    const damping = 2 * ratio * Math.sqrt(200); // Compose Spring.StiffnessLow = 200
    this.animate({ curve: curves.interpolatingSpring(Math.abs(dx) > 0.001 ? velocity.x / dx : 0, 1, 200, damping) }, (): void => {
      this.x = point.x;
    });
    this.animate({ curve: curves.interpolatingSpring(Math.abs(dy) > 0.001 ? velocity.y / dy : 0, 1, 200, damping) }, (): void => {
      this.y = point.y;
    });
  }

  private offscreenX(): number {
    return this.resting.x < (this.bounds.minX + this.bounds.maxX) / 2 ? -FAB_WIDTH : this.bounds.width;
  }

  private interact(): void {
    if (this.idleTimer !== undefined) clearTimeout(this.idleTimer);
    this.animate({ curve: curves.interpolatingSpring(0, 1, 1500, 2 * Math.sqrt(1500)) }, (): void => {
      this.idleAlpha = 1;
      this.blue = 0xff007aff;
      this.blueBorder = 0x4d007aff;
    });
    this.idleTimer = setTimeout((): void => {
      this.idleTimer = undefined;
      // Android ColorMatrix.setSaturation(0): 0*.213 + 122*.715 + 255*.072 = 105.59.
      // Only blue is chromatic; white/black icon, label and shadows are unchanged.
      // Animate the colors directly: the simulator's parent saturate() leaves a blue tint.
      this.animate({ curve: curves.interpolatingSpring(0, 1, 1500, 2 * Math.sqrt(1500)) }, (): void => {
        this.idleAlpha = 0.5;
        this.blue = 0xff6a6a6a;
        this.blueBorder = 0x4d6a6a6a;
      });
    }, 5000);
  }

  private animate(options: AnimateParam, update: () => void): void {
    if (this.ui === undefined) {
      update();
      options.onFinish?.();
    } else this.ui.animateTo(options, update);
  }

  private clearTimers(): void {
    if (this.idleTimer !== undefined) clearTimeout(this.idleTimer);
    if (this.labelTimer !== undefined) clearTimeout(this.labelTimer);
    this.idleTimer = undefined;
    this.labelTimer = undefined;
  }

  detach(): void {
    ++this.generation;
    this.clearTimers();
    this.pointerId = undefined;
    this.interactive = false;
    this.rendered = false;
    this.showing = false;
    this.enabled = false;
    this.bounds = new FabBounds(0, 0);
    this.origin = new FabPoint();
    this.alpha = 0;
    this.scale = 1;
    this.ui = undefined;
    this.onHidden = undefined;
  }
}
