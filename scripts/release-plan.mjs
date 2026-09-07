import semver from 'semver';

export function bump(version) {
  const match = /^(\d+\.\d+\.\d+)-harmony\.(\d+)$/.exec(version);
  if (!match) throw new Error(`Cannot automatically bump ${version}; select a custom version.`);
  return `${match[1]}-harmony.${Number(match[2]) + 1}`;
}

const runtimeSections = ['dependencies', 'optionalDependencies', 'peerDependencies'];
const nativeSections = ['dependencies', 'devDependencies', 'dynamicDependencies', 'overrides'];

function references(pkg) {
  return [
    ...runtimeSections.flatMap(key => Object.entries(pkg.manifest[key] || {})),
    ...pkg.native.flatMap(({ data }) => nativeSections.flatMap(key => Object.entries(data[key] || {}))),
  ].filter(([name, value]) => name !== pkg.manifest.name && !/^(?:file:|link:|\.)/.test(value));
}

export function planRelease(packages, selected) {
  const versions = new Map(selected);
  const registry = new Map(packages.map(pkg => [pkg.manifest.name, pkg]));
  for (const [name, version] of versions) {
    const pkg = registry.get(name);
    if (!pkg || pkg.manifest.private) throw new Error(`Not a publishable package: ${name}`);
    if (!semver.valid(version) || !semver.gt(version, pkg.manifest.version)) throw new Error(`Version must increase: ${name}@${version}`);
  }
  let changed;
  do {
    changed = false;
    for (const pkg of packages) {
      if (pkg.manifest.private || versions.has(pkg.manifest.name)) continue;
      if (references(pkg).some(([name]) => versions.has(name))) {
        versions.set(pkg.manifest.name, bump(pkg.manifest.version));
        changed = true;
      }
    }
  } while (changed);
  return versions;
}

export function updateManifests(pkg, versions) {
  const manifest = structuredClone(pkg.manifest);
  const native = structuredClone(pkg.native);
  const version = versions.get(manifest.name);
  if (version) manifest.version = version;
  for (const key of [...runtimeSections, 'devDependencies']) {
    for (const [name, value] of Object.entries(manifest[key] || {})) {
      if (versions.has(name) && !value.startsWith('workspace:') && semver.validRange(value)) {
        manifest[key][name] = versions.get(name);
      }
    }
  }
  for (const entry of native) {
    // App templates have their own version; only module projects track npm.
    if (version && pkg.native.some(item => item.data.name === manifest.name)) entry.data.version = version;
    for (const key of nativeSections) {
      for (const [name, value] of Object.entries(entry.data[key] || {})) {
        if (versions.has(name) && semver.validRange(value)) entry.data[key][name] = versions.get(name);
      }
    }
  }
  return { manifest, native };
}
