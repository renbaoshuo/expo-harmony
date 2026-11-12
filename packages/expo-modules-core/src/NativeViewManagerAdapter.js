/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

/* global __DEV__: readonly */

const React = require('react');
const ReactNative = require('react-native');
const { createViewConfig } = require('@react-native-oh/react-native-harmony/Libraries/NativeComponent/ViewConfig');
const deepDiffer = require('@react-native-oh/react-native-harmony/Libraries/Utilities/differ/deepDiffer').default;

const EXPO_VIEW_COMPONENT_NAME = 'ViewManagerAdapter_ExpoModulesCore';
const nativeComponentsCache = new Map();
let nextPropsRevision = 1;

function getExpoGlobal() {
  return globalThis.expo;
}

function processPropValue(value) {
  const SharedObject = getExpoGlobal()?.SharedObject;
  if (typeof SharedObject !== 'function' || !(value instanceof SharedObject)) return value;

  const id = value.__expo_shared_object_id__;
  return typeof id === 'number' ? id : value;
}

function addAttributeProcessing(attributes) {
  return Object.fromEntries(Object.keys(attributes).map(name => [name, { process: processPropValue }]));
}

function expoLogicalComponentName(moduleName, viewName) {
  return viewName
    ? `ViewManagerAdapter_${moduleName}_${viewName}`
    : `ViewManagerAdapter_${moduleName}`;
}

function nextExpoViewPropsRevision() {
  if (!Number.isSafeInteger(nextPropsRevision)) {
    throw new Error('Expo View props revision identity space was exhausted.');
  }

  return nextPropsRevision++;
}

function requireExpoViewComponent(moduleName, viewName) {
  const name = expoLogicalComponentName(moduleName, viewName);
  const appId = getExpoGlobal()?.__expo_app_identifier__ ?? '';
  const key = appId ? `${name}_${appId}` : name;
  const cached = nativeComponentsCache.get(key);
  if (cached) return cached;

  const component = ReactNative.registerViewConfig(key, () => {
    const config = getExpoGlobal()?.getViewConfig?.(moduleName, viewName);
    if (!config) {
      console.warn(`Unable to get the view config for ${viewName ?? 'default view'} from module ${moduleName}.`);
    }

    // Expo views share one Fabric host, so native reflection cannot supply each view's props.
    return createViewConfig({
      ...config,
      uiViewClassName: EXPO_VIEW_COMPONENT_NAME,
      validAttributes: {
        ...addAttributeProcessing(config?.validAttributes ?? {}),
        expoModuleName: true,
        expoViewRevision: true,
        expoViewName: true,
      },
    });
  });

  nativeComponentsCache.set(key, component);

  return component;
}

function requireNativeViewManager(moduleName, viewName) {
  const ReactNativeComponent = requireExpoViewComponent(moduleName, viewName);
  const config = getExpoGlobal()?.getViewConfig?.(moduleName, viewName);
  const propNames = Object.keys(config?.validAttributes ?? {});
  let warnedAboutHostedContent = false;

  class NativeComponent extends React.PureComponent {
    static displayName = viewName ?? moduleName;

    nativeRef = React.createRef();
    nativeTag = null;
    committedProps = null;
    renderedProps = new WeakMap();
    nativeComponentName = expoLogicalComponentName(moduleName, viewName);

    get nativePropsRevision() {
      return this.committedProps?.revision ?? 0;
    }

    getNativeRef() {
      return this.nativeRef.current;
    }

    componentDidMount() {
      this.committedProps = this.renderedProps.get(this.props);
      this.nativeTag = ReactNative.findNodeHandle(this.nativeRef.current);
    }

    componentDidUpdate() {
      this.committedProps = this.renderedProps.get(this.props);
    }

    componentWillUnmount() {
      this.nativeTag = null;
    }

    render() {
      // eslint-disable-next-line react/prop-types -- Expo view props are declared by the native module.
      if (__DEV__ && this.props.expoInternalSizeFromChildren && !warnedAboutHostedContent) {
        warnedAboutHostedContent = true;
        console.warn(`Expo view ${this.nativeComponentName} does not support sizing to hosted content on HarmonyOS.`);
      }
      const values = Object.fromEntries(propNames.map(name => [name, processPropValue(this.props[name])]));
      const committed = this.committedProps;
      const revision = committed && !deepDiffer(committed.values, values, 64)
        ? committed.revision
        : nextExpoViewPropsRevision();
      this.renderedProps.set(this.props, { values, revision });
      return React.createElement(ReactNativeComponent, {
        ...this.props,
        expoModuleName: moduleName,
        expoViewRevision: revision,
        expoViewName: viewName ?? '',
        ref: this.nativeRef,
      });
    }
  }

  const nativeModule = getExpoGlobal()?.modules?.[moduleName];
  const prototypeName = viewName ? `${moduleName}_${viewName}` : moduleName;
  const nativeViewPrototype = nativeModule?.ViewPrototypes?.[prototypeName];
  if (nativeViewPrototype) {
    Object.assign(NativeComponent.prototype, nativeViewPrototype);
  }

  return NativeComponent;
}

exports.requireNativeViewManager = requireNativeViewManager;
