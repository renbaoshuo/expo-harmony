export interface SplashScreenStateSnapshot {
  readonly nativeVisible: boolean;
  readonly prevented: boolean;
  readonly userControlled: boolean;
  readonly contentReady: boolean;
  readonly hidden: boolean;
  readonly destroyed: boolean;
}

export class SplashScreenStateMachine {
  private nativeVisibleValue: boolean = false;
  private preventedValue: boolean = false;
  private userControlledValue: boolean = false;
  private contentReadyValue: boolean = false;
  private hiddenValue: boolean = false;
  private destroyedValue: boolean = false;

  prepareForRuntime(visible: boolean): boolean {
    if (this.destroyedValue) return false;

    this.nativeVisibleValue = visible;
    this.preventedValue = false;
    this.userControlledValue = false;
    this.contentReadyValue = false;
    this.hiddenValue = false;

    return true;
  }

  markNativeVisible(): boolean {
    if (this.hiddenValue || this.destroyedValue) return false;
    this.nativeVisibleValue = true;
    return true;
  }

  prevent(userControlled: boolean): boolean {
    if (this.destroyedValue) return false;

    this.preventedValue = true;
    if (userControlled) this.userControlledValue = true;

    return true;
  }

  contentAppeared(): boolean {
    if (this.destroyedValue) return false;

    this.contentReadyValue = true;
    if (this.preventedValue) return false;

    return this.hide();
  }

  internalMaybeHide(): boolean {
    if (this.destroyedValue) return false;
    if (this.userControlledValue) return false;
    return this.hide();
  }

  hide(): boolean {
    if (this.hiddenValue || this.destroyedValue) return false;
    this.hiddenValue = true;
    return true;
  }

  markNativeRemoved(): void {
    this.nativeVisibleValue = false;
  }

  destroy(): boolean {
    if (this.destroyedValue) return false;
    this.destroyedValue = true;
    this.hiddenValue = true;
    return true;
  }

  snapshot(): SplashScreenStateSnapshot {
    return {
      nativeVisible: this.nativeVisibleValue,
      prevented: this.preventedValue,
      userControlled: this.userControlledValue,
      contentReady: this.contentReadyValue,
      hidden: this.hiddenValue,
      destroyed: this.destroyedValue,
    };
  }
}
