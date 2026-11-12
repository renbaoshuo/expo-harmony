/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const {
  createRunOncePlugin,
  HarmonyConfigPluginError,
  HarmonyManifest,
  HarmonyResources,
  registerHarmonyConfigPlugin,
  withColors,
  withMedia,
  withModuleJson,
  withStrings,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const MEDIA = 'expo_splash_screen';
const BACKGROUND = 'expo_splash_screen_background';
const RESIZE_MODE = 'expo_splash_screen_resize_mode';
const IMAGE_WIDTH = 'expo_splash_screen_image_width';
const LEGACY_IMAGE_FLAGS = ['expo_splash_screen_has_dark_image', 'expo_splash_screen_has_image'];
const RESIZE_MODES = new Set(['contain', 'cover', 'native']);
const COLOR = /^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$/;
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.svg', '.webp', '.gif']);
const TRANSPARENT_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=', 'base64');
const OWNERSHIP = Object.freeze({
  ability: {
    startWindowBackground: `$color:${BACKGROUND}`,
    startWindowIcon: `$media:${MEDIA}`,
  },
  resources: {
    colors: {
      entry: [BACKGROUND],
      entryDark: [BACKGROUND],
    },
    media: {
      entry: [MEDIA],
      entryDark: [MEDIA],
    },
    strings: {
      entry: [...LEGACY_IMAGE_FLAGS, IMAGE_WIDTH, RESIZE_MODE],
    },
  },
});

function replaceMedia(files, base, file) {
  for (const name of Object.keys(files)) {
    if (path.parse(name).name === base) delete files[name];
  }

  if (file) files[file.name] = { ...file, replaceBase: true };
}

function normalizeColor(value, field, fallback) {
  const color = value ?? fallback;
  if (typeof color !== 'string' || !COLOR.test(color)) {
    throw new TypeError(`${field} must be #RRGGBB or #RRGGBBAA.`);
  }

  return HarmonyResources.toArgb(color);
}

function normalizeImageWidth(value) {
  const width = value ?? 100;
  if (typeof width !== 'number' || !Number.isFinite(width) || width <= 0) {
    throw new TypeError('imageWidth must be a positive finite number.');
  }

  return width;
}

function normalizeImage(value, field) {
  if (value == null) return null;
  if (typeof value !== 'string' || value.length === 0) {
    throw new TypeError(`${field} must be a non-empty file path.`);
  }

  const ext = path.extname(value).toLowerCase();
  if (!IMAGE_EXTENSIONS.has(ext)) {
    throw new TypeError(`${field} must use png, jpg, jpeg, svg, webp, or gif.`);
  }

  return { value, extension: ext };
}

function normalizeObject(value, field) {
  if (value == null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${field} splash options must be an object.`);
  }

  return value;
}

function normalizeProps(props) {
  if (typeof props !== 'object' || Array.isArray(props)) {
    throw new TypeError('expo-splash-screen plugin options must be an object or null.');
  }

  const options = props;
  const harmony = normalizeObject(options.harmony, 'harmony');
  const dark = {
    ...normalizeObject(options.dark, 'dark'),
    ...normalizeObject(harmony.dark, 'harmony.dark'),
  };
  const resize = harmony.resizeMode ?? options.resizeMode ?? 'contain';

  if (!RESIZE_MODES.has(resize)) {
    throw new TypeError(`Unsupported Harmony splash resizeMode: ${String(resize)}.`);
  }

  return {
    backgroundColor: normalizeColor(
      harmony.backgroundColor ?? options.backgroundColor,
      'backgroundColor',
      '#FFFFFF'
    ),
    darkBackgroundColor: normalizeColor(
      dark.backgroundColor,
      'dark.backgroundColor',
      harmony.backgroundColor ?? options.backgroundColor ?? '#FFFFFF'
    ),
    image: normalizeImage(harmony.image ?? options.image, 'image'),
    darkImage: normalizeImage(dark.image, 'dark.image'),
    imageWidth: normalizeImageWidth(harmony.imageWidth ?? options.imageWidth),
    resizeMode: resize,
  };
}

function resolveInterfaceStyle(config) {
  const style = config?.harmony?.userInterfaceStyle ?? config?.userInterfaceStyle ?? 'light';
  if (!['light', 'dark', 'automatic'].includes(style)) {
    throw new TypeError(`Unsupported Harmony userInterfaceStyle: ${String(style)}.`);
  }

  return style;
}

function resolveQualifiedResources(options, style) {
  if (style === 'dark') {
    const image = options.darkImage ?? options.image;

    return {
      entryBackgroundColor: options.darkBackgroundColor,
      entryDarkBackgroundColor: options.darkBackgroundColor,
      entryImage: image,
      entryDarkImage: image,
    };
  }

  if (style === 'light') {
    return {
      entryBackgroundColor: options.backgroundColor,
      entryDarkBackgroundColor: options.backgroundColor,
      entryImage: options.image,
      entryDarkImage: options.image,
    };
  }

  return {
    entryBackgroundColor: options.backgroundColor,
    entryDarkBackgroundColor: options.darkBackgroundColor,
    entryImage: options.image,
    entryDarkImage: options.darkImage,
  };
}

function resolveImage(root, image, field) {
  if (!image) return null;

  const source = path.resolve(root, image.value);
  let stat;

  try {
    stat = fs.statSync(source, { throwIfNoEntry: false });
  } catch (cause) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Unable to inspect Harmony splash ${field}: ${source}`,
      { operation: 'resolve-splash-image', file: source, cause }
    );
  }

  if (!stat?.isFile()) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_CONFIG_INVALID',
      `${field} does not resolve to a file: ${source}`,
      { operation: 'resolve-splash-image', file: source }
    );
  }

  return { name: `${MEDIA}${image.extension}`, source };
}

function updateEntryAbility(json) {
  const selected = HarmonyManifest.getMainAbilityOrThrow(json);

  return {
    ...json,
    module: {
      ...json.module,
      abilities: json.module.abilities.map(ability => ability === selected
        ? { ...ability, ...OWNERSHIP.ability }
        : ability),
    },
  };
}

const withHarmonySplashScreen = (config, props) => {
  if (props == null) return config;

  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  const normalized = normalizeProps(props);
  config = registerHarmonyConfigPlugin(config, pkg.name, OWNERSHIP);

  config = withModuleJson(config, (mod) => {
    mod.modResults = updateEntryAbility(mod.modResults);

    return mod;
  });

  config = withColors(config, (mod) => {
    const qualified = resolveQualifiedResources(normalized, resolveInterfaceStyle(mod.modRawConfig));

    mod.modResults.entry ??= {};
    mod.modResults.entryDark ??= {};

    HarmonyResources.setColor(mod.modResults.entry, { name: BACKGROUND, value: qualified.entryBackgroundColor });
    HarmonyResources.setColor(mod.modResults.entryDark, {
      name: BACKGROUND,
      value: qualified.entryDarkBackgroundColor,
    });

    return mod;
  });

  config = withStrings(config, (mod) => {
    const entry = mod.modResults.entry ??= {};

    for (const name of LEGACY_IMAGE_FLAGS) HarmonyResources.removeString(entry, name);
    HarmonyResources.setString(entry, { name: IMAGE_WIDTH, value: String(normalized.imageWidth) });
    HarmonyResources.setString(entry, { name: RESIZE_MODE, value: normalized.resizeMode });

    return mod;
  });

  config = withMedia(config, (mod) => {
    const qualified = resolveQualifiedResources(normalized, resolveInterfaceStyle(mod.modRawConfig));
    const root = mod.modRequest.projectRoot;

    const image = resolveImage(root, qualified.entryImage, 'image');
    const dark = resolveImage(root, qualified.entryDarkImage, 'darkImage');

    mod.modResults.entry ??= {};
    mod.modResults.entryDark ??= {};

    replaceMedia(mod.modResults.entry, MEDIA, image ?? { name: `${MEDIA}.png`, content: TRANSPARENT_PNG });
    replaceMedia(mod.modResults.entryDark, MEDIA, dark);

    return mod;
  });

  return config;
};

module.exports = createRunOncePlugin(withHarmonySplashScreen, pkg.name, pkg.version);
