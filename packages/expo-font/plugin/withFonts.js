/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const fs = require('node:fs');
const { createHash } = require('node:crypto');
const { createRequire } = require('node:module');
const path = require('node:path');

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyConfigPluginError,
  stableHarmonyJson,
  withRawfile,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');
const maxFontBytes = 32 * 1024 * 1024;
const fontExtensions = new Set(['.ttf', '.otf']);

class ExpoFontPluginError extends HarmonyConfigPluginError {
  constructor(message, options = {}) {
    super('ERR_HARMONY_CONFIG_INVALID', message, {
      ...options,
      operation: 'bundle-fonts',
    });
    this.name = 'ExpoFontPluginError';
  }
}

function fontFamilyFromFilename(file) {
  const name = path.basename(file, path.extname(file));
  return name.replace(/(?:_bold_italic|_bold|_italic)$/, '') || name;
}

function appendFontEntries(fonts, value, field) {
  if (value === undefined) return;
  if (!Array.isArray(value)) {
    throw new ExpoFontPluginError(`${field} must be an array.`);
  }
  fonts.push(...value);
}

function fontEntries(config, props) {
  const fonts = [];

  if (props !== undefined) {
    if (!props || typeof props !== 'object' || Array.isArray(props)) {
      throw new ExpoFontPluginError('@expo-harmony/expo-font options must be an object.');
    }

    appendFontEntries(fonts, props.fonts, '@expo-harmony/expo-font.fonts');
    appendFontEntries(
      fonts,
      props.harmony?.fonts,
      '@expo-harmony/expo-font.harmony.fonts'
    );
  }

  for (const plugin of config.plugins || []) {
    const name = Array.isArray(plugin) ? plugin[0] : plugin;
    if (name !== 'expo-font') continue;

    const options = Array.isArray(plugin) && plugin[1] && typeof plugin[1] === 'object'
      ? plugin[1]
      : {};

    appendFontEntries(fonts, options.fonts, 'expo-font.fonts');
    appendFontEntries(fonts, options.harmony?.fonts, 'expo-font.harmony.fonts');
  }

  const entries = [];
  for (const font of fonts) {
    if (typeof font === 'string') {
      entries.push({ source: font });
      continue;
    }

    if (!font || typeof font.fontFamily !== 'string' || !font.fontFamily.trim()
      || !Array.isArray(font.fontDefinitions)) {
      throw new ExpoFontPluginError(
        'Harmony font entries must be paths or expo-font family definitions.'
      );
    }

    for (const face of font.fontDefinitions) {
      if (!face || typeof face.path !== 'string') {
        throw new ExpoFontPluginError(
          `Font family '${font.fontFamily}' contains an invalid definition.`
        );
      }

      if (face.weight !== undefined
        && (!Number.isInteger(face.weight) || face.weight < 1 || face.weight > 1000)) {
        throw new ExpoFontPluginError(
          `Font family '${font.fontFamily}' contains an invalid weight.`
        );
      }

      if (face.style !== undefined && !['normal', 'italic'].includes(face.style)) {
        throw new ExpoFontPluginError(
          `Font family '${font.fontFamily}' contains an invalid style.`
        );
      }

      if (face.weight !== undefined || face.style !== undefined) {
        throw new ExpoFontPluginError(
          `Font family '${font.fontFamily}' uses weight/style variants, but the Harmony font registry currently supports one face per family. Use a distinct fontFamily for each Harmony face.`
        );
      }

      entries.push({ family: font.fontFamily, source: face.path });
    }
  }

  return entries;
}

function expandFontEntries(root, entries) {
  const fonts = [];
  const requireFromProject = createRequire(path.join(root, 'package.json'));

  for (const font of entries) {
    let source = path.resolve(root, font.source);
    let stat;

    try {
      try {
        stat = fs.statSync(source);
      } catch (cause) {
        if (cause.code !== 'ENOENT') throw cause;
        // Match Expo's package-style paths, resolved from the host application.
        source = requireFromProject.resolve(font.source);
        stat = fs.statSync(source);
      }
    } catch (cause) {
      throw new ExpoFontPluginError(`Harmony font input does not exist: ${source}`, {
        cause,
        file: source,
      });
    }

    if (stat.isDirectory()) {
      if (font.family !== undefined) {
        throw new ExpoFontPluginError(
          `Font family definitions must reference files: ${source}`,
          { file: source }
        );
      }

      const children = fs.readdirSync(source, { withFileTypes: true })
        .filter(child => child.isFile() && fontExtensions.has(path.extname(child.name).toLowerCase()));

      for (const child of children) {
        const file = path.join(source, child.name);
        fonts.push({
          family: fontFamilyFromFilename(file),
          source: fs.realpathSync(file),
        });
      }

      continue;
    }

    if (!stat.isFile()) {
      throw new ExpoFontPluginError(`Harmony font input is not a file: ${source}`, {
        file: source,
      });
    }

    fonts.push({
      ...font,
      family: font.family ?? fontFamilyFromFilename(source),
      source: fs.realpathSync(source),
    });
  }

  const unique = new Map();
  for (const font of fonts) {
    const key = `${font.family}\0${font.source}`;
    if (!unique.has(key)) unique.set(key, font);
  }

  return [...unique.values()].sort((left, right) => {
    return left.family.localeCompare(right.family, 'en')
      || left.source.localeCompare(right.source, 'en');
  });
}

function fontResources(entries) {
  const sources = new Map();

  for (const entry of entries) {
    const source = sources.get(entry.family);
    if (source !== undefined && source !== entry.source) {
      throw new ExpoFontPluginError(
        `Harmony font family '${entry.family}' resolves to more than one face. The Harmony registry supports one face per family; assign distinct family names instead.`,
        { file: entry.source }
      );
    }

    sources.set(entry.family, entry.source);
  }

  const files = {};
  const records = [];

  for (const entry of entries) {
    const ext = path.extname(entry.source).toLowerCase();
    if (!fontExtensions.has(ext)) {
      throw new ExpoFontPluginError(`Unsupported Harmony font file: ${entry.source}`, {
        file: entry.source,
      });
    }

    if (fs.statSync(entry.source).size > maxFontBytes) {
      throw new ExpoFontPluginError(`Harmony font file exceeds ${maxFontBytes} bytes: ${entry.source}`, {
        file: entry.source,
      });
    }

    const data = fs.readFileSync(entry.source);
    if (data.length === 0 || data.length > maxFontBytes) {
      throw new ExpoFontPluginError(`Harmony font files must contain between 1 and ${maxFontBytes} bytes: ${entry.source}`, {
        file: entry.source,
      });
    }

    const digest = createHash('sha256').update(data).digest('hex');
    const file = `fonts/font-${digest}${ext}`;

    files[file] ??= { content: data };
    records.push({
      family: entry.family,
      file,
      sha256: digest,
      size: data.length,
    });
  }

  files['expo-fonts.json'] = { content: stableHarmonyJson({ fonts: records }) };

  return files;
}

const withHarmonyFonts = (config, props) => {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  const entries = fontEntries(config, props);
  const root = config._internal?.projectRoot;
  if (entries.length > 0 && !root) {
    throw new ExpoFontPluginError('Expo Font requires an Expo project root to resolve Harmony fonts.');
  }

  const files = fontResources(entries.length > 0 ? expandFontEntries(root, entries) : []);
  return withRawfile(config, { owner: pkg.name, files });
};

module.exports = createRunOncePlugin(withHarmonyFonts, pkg.name, pkg.version);
