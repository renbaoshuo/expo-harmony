import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class IntentLauncherAbility extends UIAbility {
  private want: Want = {};

  onCreate(want: Want): void {
    this.want = want;
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    const storage = new LocalStorage();
    storage.setOrCreate('want', this.want);
    stage.loadContent('pages/IntentLauncher', storage);
  }
}
