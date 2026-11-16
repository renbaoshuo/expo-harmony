/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { UITurboModule, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { DevLauncherController } from './DevLauncherController';

export class EXDevLauncherConstants {
  readonly manifestString: string | null;
  readonly manifestURL: string | null;

  constructor(manifestString: string | null, manifestURL: string | null) {
    this.manifestString = manifestString;
    this.manifestURL = manifestURL;
  }
}

export class EXDevLauncherTurboModule extends UITurboModule {
  static readonly NAME = 'EXDevLauncher';
  private readonly constants: EXDevLauncherConstants;

  constructor(context: UITurboModuleContext) {
    super(context);

    const controller = DevLauncherController.get(context.uiAbilityContext.getApplicationContext());
    const selection = controller.getRuntimeSelection(context.rnInstance.getId());

    this.constants = new EXDevLauncherConstants(
      selection?.manifest === undefined ? null : JSON.stringify(selection.manifest),
      selection?.manifestURL ?? null,
    );
  }

  getConstants(): EXDevLauncherConstants {
    return this.constants;
  }
}
