'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyConfigPluginError,
  registerHarmonyConfigPlugin,
  withColors,
  withMedia,
  withModuleJson,
  withStrings,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const SPLASH_MEDIA = 'expo_splash_screen';
const LEGACY_DARK_MEDIA = 'expo_splash_screen_dark';
const SPLASH_BACKGROUND = 'expo_splash_screen_background';
const LEGACY_DARK_BACKGROUND = 'expo_splash_screen_background_dark';
const RESIZE_MODES = new Set(['contain', 'cover', 'native']);
const COLOR = /^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$/;
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.svg', '.webp', '.gif']);
const TRANSPARENT_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+3MxZ5wAAAABJRU5ErkJggg==', 'base64');
const OWNERSHIP = Object.freeze({
  ability: {
    startWindowBackground: '$color:expo_splash_screen_background',
    startWindowIcon: '$media:expo_splash_screen',
  },
  resources: {
    colors: {
      entry: [SPLASH_BACKGROUND, LEGACY_DARK_BACKGROUND],
      entryDark: [SPLASH_BACKGROUND, LEGACY_DARK_BACKGROUND],
    },
    media: {
      entry: [SPLASH_MEDIA, LEGACY_DARK_MEDIA],
      entryDark: [SPLASH_MEDIA, LEGACY_DARK_MEDIA],
    },
    strings: {
      entry: [
        'expo_splash_screen_has_dark_image',
        'expo_splash_screen_has_image',
        'expo_splash_screen_image_width',
        'expo_splash_screen_resize_mode',
      ],
    },
  },
});

function setResource(items, name, value) {
  const next = (Array.isArray(items) ? items : []).filter(item => item?.name !== name);

  next.push({ name, value });
  next.sort((left, right) => left.name.localeCompare(right.name, 'en'));

  return next;
}

function removeResource(items, name) {
  return (Array.isArray(items) ? items : []).filter(item => item?.name !== name);
}

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

  const upper = color.toUpperCase();
  if (upper.length === 9) {
    // Expo config follows CSS/React Native #RRGGBBAA, while Harmony resource
    // colors use #AARRGGBB. Six-digit opaque colors have the same ordering.
    return `#${upper.slice(7, 9)}${upper.slice(1, 7)}`;
  }

  return upper;
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

function normalizeProps(config, props) {
  if (props != null && (typeof props !== 'object' || Array.isArray(props))) {
    throw new TypeError('expo-splash-screen plugin options must be an object or null.');
  }

  const expo = props == null ? normalizeObject(config?.splash, 'legacy') : {};
  const legacy = normalizeObject(config?.harmony?.splash, 'harmony legacy');
  const options = { ...expo, ...legacy, ...(props ?? {}) };
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

  return { name: `${SPLASH_MEDIA}${image.extension}`, source };
}

function updateEntryAbility(json) {
  const module = json.module;
  if (!module || typeof module !== 'object' || !Array.isArray(module.abilities)) {
    return json;
  }

  const main = module.mainElement;
  const abilities = module.abilities.map((ability, index) => {
    if (!ability || typeof ability !== 'object') return ability;

    const selected = typeof main === 'string' ? ability.name === main : index === 0;
    if (!selected) return ability;

    return {
      ...ability,
      startWindowBackground: '$color:expo_splash_screen_background',
      startWindowIcon: '$media:expo_splash_screen',
    };
  });

  return { ...json, module: { ...module, abilities } };
}

const withHarmonySplashScreen = (config, props) => {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name, OWNERSHIP);

  let cache;

  const resolveOptions = () => {
    if (cache) return cache;

    const normalized = normalizeProps(config, props);

    cache = {
      normalized,
      qualified: resolveQualifiedResources(normalized, resolveInterfaceStyle(config)),
    };

    return cache;
  };

  config = withModuleJson(config, (mod) => {
    mod.modResults = updateEntryAbility(mod.modResults);
    return mod;
  });

  config = withColors(config, (mod) => {
    const { qualified } = resolveOptions();

    mod.modResults.entry ??= {};
    mod.modResults.entryDark ??= {};

    mod.modResults.entry.color = setResource(
      removeResource(mod.modResults.entry.color, LEGACY_DARK_BACKGROUND),
      SPLASH_BACKGROUND,
      qualified.entryBackgroundColor
    );
    mod.modResults.entryDark.color = setResource(
      removeResource(mod.modResults.entryDark.color, LEGACY_DARK_BACKGROUND),
      SPLASH_BACKGROUND,
      qualified.entryDarkBackgroundColor
    );

    return mod;
  });

  config = withStrings(config, (mod) => {
    const { normalized } = resolveOptions();

    mod.modResults.entry ??= {};

    let strings = mod.modResults.entry.string;
    strings = setResource(strings, 'expo_splash_screen_resize_mode', normalized.resizeMode);
    strings = setResource(strings, 'expo_splash_screen_image_width', String(normalized.imageWidth));
    strings = removeResource(strings, 'expo_splash_screen_has_image');
    strings = removeResource(strings, 'expo_splash_screen_has_dark_image');

    mod.modResults.entry.string = strings;

    return mod;
  });

  config = withMedia(config, (mod) => {
    const { qualified } = resolveOptions();

    mod.modResults.entry ??= {};
    mod.modResults.entryDark ??= {};

    const root = mod.modRequest.projectRoot;
    const image = resolveImage(root, qualified.entryImage, 'image');
    const dark = resolveImage(root, qualified.entryDarkImage, 'darkImage');

    replaceMedia(mod.modResults.entry, SPLASH_MEDIA, image ?? { name: `${SPLASH_MEDIA}.png`, content: TRANSPARENT_PNG });
    replaceMedia(mod.modResults.entryDark, SPLASH_MEDIA, dark);

    replaceMedia(mod.modResults.entry, LEGACY_DARK_MEDIA, null);
    replaceMedia(mod.modResults.entryDark, LEGACY_DARK_MEDIA, null);

    return mod;
  });

  return config;
};

module.exports = createRunOncePlugin(withHarmonySplashScreen, pkg.name, pkg.version);
module.exports.withHarmonySplashScreen = withHarmonySplashScreen;
