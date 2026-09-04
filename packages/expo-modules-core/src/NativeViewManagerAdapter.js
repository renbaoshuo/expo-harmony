'use strict';

const React = require('react');
const ReactNative = require('react-native');
const NativeComponentRegistry = require('react-native/Libraries/NativeComponent/NativeComponentRegistry');

const EXPO_VIEW_COMPONENT_NAME = 'ViewManagerAdapter_ExpoModulesCore';
const nativeComponentsCache = new Map();
const propsRevisions = new WeakMap();
let nextPropsRevision = 1;

function getExpoGlobal() {
  return globalThis.expo;
}

function expoLogicalComponentName(moduleName, viewName) {
  return viewName
    ? `ViewManagerAdapter_${moduleName}_${viewName}`
    : `ViewManagerAdapter_${moduleName}`;
}

function expoViewPropsRevision(props) {
  const existing = propsRevisions.get(props);
  if (existing !== undefined) return existing;
  if (!Number.isSafeInteger(nextPropsRevision)) {
    throw new Error('Expo View props revision identity space was exhausted.');
  }
  const revision = nextPropsRevision;
  nextPropsRevision += 1;
  propsRevisions.set(props, revision);
  return revision;
}

function ensureNativeModulesAreInstalled() {
  if (getExpoGlobal()) return;

  const coreModule = ReactNative.TurboModuleRegistry.get('ExpoModulesCore');
  if (!coreModule || typeof coreModule.installModules !== 'function') {
    throw new Error('Unable to install Expo modules: ExpoModulesCore.installModules() is unavailable.');
  }

  try {
    coreModule.installModules();
  } catch (error) {
    throw new Error(`Unable to install Expo modules: ${error}`);
  }

  if (!getExpoGlobal()) {
    throw new Error('Unable to install Expo modules: the native installer did not create globalThis.expo.');
  }
}

function requireExpoViewComponent(moduleName, viewName) {
  const logicalName = expoLogicalComponentName(moduleName, viewName);
  const appIdentifier = getExpoGlobal()?.__expo_app_identifier__ ?? '';
  const registryName = appIdentifier ? `${logicalName}_${appIdentifier}` : logicalName;
  const cached = nativeComponentsCache.get(registryName);
  if (cached) return cached;

  const nativeComponent = NativeComponentRegistry.get(registryName, () => {
    const viewConfig = getExpoGlobal()?.getViewConfig?.(moduleName, viewName);
    if (!viewConfig) {
      throw new Error(`Unable to get the view config for ${viewName ?? 'default view'} from module ${moduleName}.`);
    }

    return {
      ...viewConfig,
      uiViewClassName: EXPO_VIEW_COMPONENT_NAME,
      validAttributes: {
        ...viewConfig?.validAttributes,
        expoModuleName: true,
        expoViewRevision: true,
        expoViewName: true,
      },
    };
  });
  nativeComponentsCache.set(registryName, nativeComponent);
  return nativeComponent;
}

function requireNativeViewManager(moduleName, viewName) {
  ensureNativeModulesAreInstalled();
  const ReactNativeComponent = requireExpoViewComponent(moduleName, viewName);

  class NativeComponent extends React.PureComponent {
    static displayName = viewName ?? moduleName;

    nativeRef = React.createRef();
    nativeTag = null;
    nativeComponentName = expoLogicalComponentName(moduleName, viewName);

    get nativePropsRevision() {
      return expoViewPropsRevision(this.props);
    }

    componentDidMount() {
      this.nativeTag = ReactNative.findNodeHandle(this.nativeRef.current);
    }

    render() {
      return React.createElement(ReactNativeComponent, {
        ...this.props,
        expoModuleName: moduleName,
        expoViewRevision: this.nativePropsRevision,
        expoViewName: viewName ?? '',
        ref: this.nativeRef,
      });
    }
  }

  try {
    const nativeModule = getExpoGlobal()?.modules?.[moduleName];
    const prototypeName = viewName ? `${moduleName}_${viewName}` : moduleName;
    const nativeViewPrototype = nativeModule?.ViewPrototypes?.[prototypeName];
    if (nativeViewPrototype) {
      Object.assign(NativeComponent.prototype, nativeViewPrototype);
    }
  } catch {
    // Match Expo's behavior for tests and runtimes with incomplete module mocks.
  }

  return NativeComponent;
}

exports.requireNativeViewManager = requireNativeViewManager;
