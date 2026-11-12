/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export class SplashScreenStateMachine {
  private visible: boolean = false;
  private prevented: boolean = false;
  private controlled: boolean = false;
  private hidden: boolean = false;
  private destroyed: boolean = false;

  prepareForRuntime(visible: boolean): void {
    if (this.destroyed) return;

    this.visible = visible;
    this.prevented = false;
    this.controlled = false;
    this.hidden = false;
  }

  markNativeVisible(): void {
    if (this.hidden || this.destroyed) return;
    this.visible = true;
  }

  prevent(controlled: boolean): boolean {
    if (this.destroyed) return false;

    this.prevented = true;
    if (controlled) this.controlled = true;

    return true;
  }

  contentAppeared(): boolean {
    if (this.destroyed || this.prevented) return false;
    return this.hide();
  }

  internalMaybeHide(): boolean {
    if (this.destroyed || this.controlled) return false;
    return this.hide();
  }

  hide(): boolean {
    if (this.hidden || this.destroyed) return false;
    this.hidden = true;
    return true;
  }

  markNativeRemoved(): void {
    this.visible = false;
  }

  destroy(): boolean {
    if (this.destroyed) return false;

    this.destroyed = true;
    this.hidden = true;
    return true;
  }

  isVisible(): boolean {
    return this.visible;
  }

  isHiding(): boolean {
    return this.hidden && this.visible && !this.destroyed;
  }

  isDestroyed(): boolean {
    return this.destroyed;
  }
}
