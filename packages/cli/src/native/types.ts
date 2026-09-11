export type HarmonyBuildMode = 'debug' | 'release';

interface NativeBuildPlan {
  abilityName: string;
  buildMode: HarmonyBuildMode;
  bundleName: string;
  expectedHap: string;
  exportPaths: {
    bundle: string;
    manifest: string;
    metadataRoot: string;
    rawfileRoot: string;
    sourceMap: string;
  };
  harmonyRoot: string;
  hvigorArgs: string[];
  moduleName: string;
  moduleRoot: string;
  nativeCache: { invalidationRoots: string[]; stateFile: string };
  nativeInputs: { lockfile: string; manifest: string };
  projectFiles: {
    hvigorConfig: string;
    moduleHvigor: string;
    moduleJson: string;
    projectBuildProfile: string;
    rootHvigor: string;
  };
  productName: string;
  targetName: string;
}

export interface BareHarmonyBuildPlan extends NativeBuildPlan {
  workflow: 'bare';
}

export interface CngHarmonyBuildPlan extends NativeBuildPlan {
  workflow: 'cng';
  projectFiles: NativeBuildPlan['projectFiles'] & {
    nativeInputsStamp: string;
    templateMarker: string;
  };
}

export type HarmonyBuildPlan = BareHarmonyBuildPlan | CngHarmonyBuildPlan;
