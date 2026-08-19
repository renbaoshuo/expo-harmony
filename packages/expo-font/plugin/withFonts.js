'use strict';

const fs = require('node:fs');
const { createHash } = require('node:crypto');
const path = require('node:path');

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyConfigPluginError,
  recordManagedFile,
  registerHarmonyConfigPlugin,
  stableHarmonyJson,
  withHarmonyDangerousMod,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

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
  const name = path.basename(file);
  const match = /^(.+?)(?:_bold|_italic|_bold_italic)?\.(?:ttf|otf)$/.exec(name);
  return match?.[1] || path.basename(name, path.extname(name));
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

  appendFontEntries(fonts, config.harmony?.fonts, 'expo.harmony.fonts');

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
          `Font family '${font.fontFamily}' uses weight/style variants, but RNOH 0.84.1 only provides one registered face per family. Use a distinct fontFamily for each Harmony face.`
        );
      }

      entries.push({ family: font.fontFamily, source: face.path });
    }
  }

  return entries;
}

async function expandFontEntriesAsync(root, entries) {
  const fonts = [];

  for (const font of entries) {
    const source = path.resolve(root, font.source);
    let stat;

    try {
      stat = await fs.promises.stat(source);
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

      const children = (await fs.promises.readdir(source, { withFileTypes: true }))
        .filter(child => child.isFile() && ['.ttf', '.otf'].includes(path.extname(child.name)))
        .sort((left, right) => left.name.localeCompare(right.name, 'en'));

      for (const child of children) {
        const file = path.join(source, child.name);
        fonts.push({ family: fontFamilyFromFilename(file), source: file });
      }

      continue;
    }

    if (!stat.isFile()) {
      throw new ExpoFontPluginError(`Harmony font input is not a file: ${source}`, {
        file: source,
      });
    }

    fonts.push({ ...font, family: font.family ?? fontFamilyFromFilename(source), source });
  }

  return fonts;
}

async function writeFontResourcesAsync(project, config, props) {
  const root = path.join(project, 'harmony/entry/src/main/resources/rawfile');
  const directory = path.join(root, 'fonts');
  const manifest = path.join(root, 'expo-fonts.json');
  const entries = await expandFontEntriesAsync(project, fontEntries(config, props));
  const sources = new Map();

  for (const entry of entries) {
    const source = sources.get(entry.family);
    if (source !== undefined && source !== entry.source) {
      throw new ExpoFontPluginError(
        `Harmony font family '${entry.family}' resolves to more than one face. RNOH 0.84.1 would silently keep only the last registration; assign distinct family names instead.`,
        { file: entry.source }
      );
    }

    sources.set(entry.family, entry.source);
  }

  const records = [];
  for (const [index, entry] of entries.entries()) {
    const ext = path.extname(entry.source).toLowerCase();
    if (!['.ttf', '.otf'].includes(ext)) {
      throw new ExpoFontPluginError(`Unsupported Harmony font file: ${entry.source}`, {
        file: entry.source,
      });
    }

    const data = await fs.promises.readFile(entry.source);
    if (data.length === 0) {
      throw new ExpoFontPluginError(`Harmony font file is empty: ${entry.source}`, {
        file: entry.source,
      });
    }

    const hash = createHash('sha256').update(data).digest('hex').slice(0, 16);
    const stem = entry.family.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-|-$/g, '')
      || 'font';
    const name = `${stem}-${index}-${hash}${ext}`;

    await fs.promises.mkdir(directory, { recursive: true });
    await fs.promises.writeFile(path.join(directory, name), data);

    records.push({ family: entry.family, file: `fonts/${name}` });
  }

  let stale = [];

  try {
    const value = JSON.parse(await fs.promises.readFile(manifest, 'utf8'));
    stale = Array.isArray(value.fonts) ? value.fonts.map(font => font?.file).filter(Boolean) : [];
  } catch (cause) {
    if (cause.code !== 'ENOENT' && !(cause instanceof SyntaxError)) {
      throw new ExpoFontPluginError(`Unable to read the Harmony font manifest: ${manifest}`, {
        cause,
        file: manifest,
      });
    }
  }

  await fs.promises.mkdir(root, { recursive: true });
  await fs.promises.writeFile(manifest, stableHarmonyJson({ fonts: records }));

  const current = new Set(records.map(record => record.file));
  for (const relative of stale) {
    if (!/^fonts\/[A-Za-z0-9._-]+\.(?:ttf|otf)$/i.test(relative) || current.has(relative)) {
      continue;
    }

    const file = path.join(root, relative);

    try {
      await fs.promises.unlink(file);
    } catch (cause) {
      if (cause.code !== 'ENOENT') {
        throw new ExpoFontPluginError(`Unable to remove stale Harmony font: ${file}`, {
          cause,
          file,
        });
      }
    }
  }

  return [manifest, ...records.map(record => path.join(root, record.file))];
}

const withHarmonyFonts = (config, props) => {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  const registered = registerHarmonyConfigPlugin(config, pkg.name);

  return withHarmonyDangerousMod(registered, async (mod) => {
    const files = await writeFontResourcesAsync(mod.modRequest.projectRoot, registered, props);

    for (const file of files) recordManagedFile(mod, file, pkg.name);

    return mod;
  });
};

module.exports = createRunOncePlugin(withHarmonyFonts, pkg.name, pkg.version);
module.exports.fontEntries = fontEntries;
module.exports.withHarmonyFonts = withHarmonyFonts;
module.exports.writeFontResourcesAsync = writeFontResourcesAsync;
