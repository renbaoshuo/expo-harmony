/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

import { ExpoArtifacts, InlineModulesRoot, RnohArtifacts, ToolVersion } from '../config/constants';
import { HarmonyAutolinkingError } from '../errors';
import { HostMetadataFields } from '../metadata/host';
import type { InlineModuleFile, InlineModulesOptions, ModuleDescriptor, SearchRecord } from '../types';
import { compareText, isArkTsIdentifier, isPathInside, normalizeSlashes, readJsonAsync } from '../utilities/values';

const IgnoredDirectories = new Set(['.git', '.expo', '.hvigor', '.cxx', 'build', 'node_modules', 'oh_modules']);
const ImportExtensions = ['.ets', '.ts', '.js', '.json'];
const InlineModulesPackageName = '@expo-harmony/inline-modules';
const SourceSnapshots = new WeakMap<InlineModuleFile, Buffer>();

export function readInlineModuleContent(root: string, file: InlineModuleFile): Buffer {
  // A manifest contains relative paths and declarations, but no source bytes.
  let content = SourceSnapshots.get(file);
  if (!content) {
    content = fs.readFileSync(path.join(root, file.path));
    SourceSnapshots.set(file, content);
  }
  return content;
}

function projectRelativePath(root: string, file: string): string {
  const relative = normalizeSlashes(path.relative(root, file)) || '.';

  if (relative.includes('\\') || relative.includes('\0') || path.win32.isAbsolute(relative)) {
    throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline source paths must be portable project-relative paths: ${file}`, { stage: 'inline-modules' });
  }

  return relative;
}

function isGeneratedSource(file: string): boolean {
  const normalized = normalizeSlashes(file);
  return normalized.endsWith(`/${InlineModulesRoot}`) || normalized.includes(`/${InlineModulesRoot}/`)
    || [...Object.values(ExpoArtifacts), ...Object.values(RnohArtifacts)]
      .some(artifact => normalized.endsWith(`/${artifact}`));
}

function referenceName(node: ts.Node): string | undefined {
  if (ts.isIdentifier(node)) return node.text;
  if (ts.isQualifiedName(node)) {
    const left = referenceName(node.left);
    return left ? `${left}.${node.right.text}` : undefined;
  }
  if (ts.isPropertyAccessExpression(node)) {
    const left = referenceName(node.expression);
    return left ? `${left}.${node.name.text}` : undefined;
  }
  return undefined;
}

function moduleClasses(source: ts.SourceFile): InlineModuleFile['modules'] {
  const bases = new Set<string>();
  const definitions = new Set<string>();

  for (const statement of source.statements) {
    if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)
      || statement.moduleSpecifier.text !== '@expo-harmony/expo-modules-core') continue;

    const clause = statement.importClause;
    const bindings = clause?.namedBindings;
    if (!bindings) continue;

    if (ts.isNamespaceImport(bindings)) {
      if (!clause.isTypeOnly) bases.add(`${bindings.name.text}.ExpoModule`);
      definitions.add(`${bindings.name.text}.ExpoModuleDefinition`);
      continue;
    }

    for (const binding of bindings.elements) {
      const imported = (binding.propertyName ?? binding.name).text;
      if (imported === 'ExpoModule' && !clause.isTypeOnly && !binding.isTypeOnly) bases.add(binding.name.text);
      if (imported === 'ExpoModuleDefinition') definitions.add(binding.name.text);
    }
  }

  const classes: { name: string; default: boolean }[] = [];

  for (const statement of source.statements) {
    if (!ts.isClassDeclaration(statement)) continue;

    const modifiers = ts.getModifiers(statement) ?? [];
    if (modifiers.some(modifier => modifier.kind === ts.SyntaxKind.AbstractKeyword)) continue;

    const inherits = statement.heritageClauses?.some(clause => clause.token === ts.SyntaxKind.ExtendsKeyword
      && clause.types.some(type => bases.has(referenceName(type.expression))));
    const definition = statement.members.some(member => ts.isMethodDeclaration(member)
      && ts.isIdentifier(member.name) && member.name.text === 'definition'
      && !ts.getModifiers(member)?.some(modifier => modifier.kind === ts.SyntaxKind.StaticKeyword)
      && member.parameters.length === 0 && member.body
      && (inherits || (member.type && ts.isTypeReferenceNode(member.type)
        && definitions.has(referenceName(member.type.typeName)))));
    if (!definition) continue;

    if (!statement.name || !isArkTsIdentifier(statement.name.text)
      || !modifiers.some(modifier => modifier.kind === ts.SyntaxKind.ExportKeyword)) {
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline module classes must be named and exported: ${source.fileName}`, { stage: 'inline-modules' });
    }

    classes.push({
      name: statement.name.text,
      default: modifiers.some(modifier => modifier.kind === ts.SyntaxKind.DefaultKeyword),
    });
  }

  return classes.sort((left, right) => compareText(left.name, right.name));
}

function relativeImports(source: ts.SourceFile): string[] {
  const imports = new Set<string>();
  const add = (node: ts.Node | undefined) => {
    if (node && ts.isStringLiteralLike(node) && /^(?:\.{1,2})(?:\/|$)/u.test(node.text)) imports.add(node.text);
  };
  const visit = (node: ts.Node) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) add(node.moduleSpecifier);
    else if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) add(node.arguments[0]);
    else if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument)) add(node.argument.literal);

    ts.forEachChild(node, visit);
  };

  visit(source);

  return [...imports].sort(compareText);
}

async function resolveSourceImport(file: string, specifier: string): Promise<string> {
  const target = path.resolve(path.dirname(file), specifier);
  const candidates = [target, ...ImportExtensions.map(ext => target + ext),
    ...ImportExtensions.map(ext => path.join(target, 'index' + ext))];

  for (const candidate of candidates) {
    try {
      if ((await fs.promises.stat(candidate)).isFile()) return candidate;
    } catch (cause) {
      if (cause.code !== 'ENOENT' && cause.code !== 'ENOTDIR') {
        throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Unable to inspect inline source import ${JSON.stringify(specifier)} in ${file}.`, { cause, stage: 'inline-modules' });
      }
    }
  }

  throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Unable to resolve inline source import ${JSON.stringify(specifier)} in ${file}.`, { stage: 'inline-modules' });
}

export async function searchInlineModulesAsync(
  projectRoot: string,
  options: InlineModulesOptions | null
): Promise<SearchRecord | null> {
  if (!options) return null;

  if (!Array.isArray(options.watchedDirectories)
    || options.watchedDirectories.some(directory => typeof directory !== 'string' || !directory.trim())) {
    throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', 'inlineModules.watchedDirectories must be an array of non-empty directory paths.', { stage: 'inline-modules' });
  }

  if (options.watchedDirectories.length === 0) return null;

  const root = await fs.promises.realpath(projectRoot);
  const files = new Map<string, InlineModuleFile>();
  const visited = new Set<string>();
  const dirs: string[] = [];

  const check = async (file: string) => {
    const target = path.resolve(file);
    if (!isPathInside(root, target)) {
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline sources must stay inside the app project: ${file}`, { stage: 'inline-modules' });
    }
    const real = await fs.promises.realpath(target).catch((cause) => {
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline source path does not exist: ${file}`, { cause, stage: 'inline-modules' });
    });
    if (target !== real) {
      // Mirroring a symlink would change the base of its relative imports.
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline sources must not traverse symbolic links: ${file}`, { stage: 'inline-modules' });
    }

    return real;
  };

  const add = async (file: string) => {
    const real = await check(file);
    const relative = projectRelativePath(root, real);

    if (files.has(relative)) return;
    if (isGeneratedSource(real)) {
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline source imports a generated autolinking file: ${file}`, { stage: 'inline-modules' });
    }
    if (!ImportExtensions.includes(path.extname(real))) {
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Unsupported inline source import: ${file}`, { stage: 'inline-modules' });
    }

    const content = await fs.promises.readFile(real);
    const source = ts.createSourceFile(real, content.toString('utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
    const register = path.extname(real) === '.ets'
      && dirs.some(directory => isPathInside(path.resolve(root, directory), real));
    const snapshot = { path: relative, modules: register ? moduleClasses(source) : [] };
    SourceSnapshots.set(snapshot, content);
    files.set(relative, snapshot);

    if (path.extname(real) === '.json') return;

    for (const specifier of relativeImports(source)) {
      await add(await resolveSourceImport(real, specifier));
    }
  };

  const visit = async (directory: string) => {
    const real = await check(directory);
    if (visited.has(real)) return;

    visited.add(real);

    const entries = (await fs.promises.readdir(real, { withFileTypes: true }))
      .sort((left, right) => compareText(left.name, right.name));

    for (const entry of entries) {
      if (IgnoredDirectories.has(entry.name)) continue;

      const file = path.join(real, entry.name);
      if (isGeneratedSource(file)) continue;
      if (entry.isDirectory()) {
        await visit(file);
      } else if (entry.isSymbolicLink()) {
        throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline source trees must not contain symbolic links: ${file}`, { stage: 'inline-modules' });
      } else if (entry.isFile() && path.extname(entry.name) === '.ets') {
        await add(file);
      }
    }
  };

  // Resolve all watched roots first so import order cannot change registration.
  for (const directory of options.watchedDirectories) {
    const real = await check(path.resolve(root, directory));
    if (!(await fs.promises.stat(real)).isDirectory()) {
      throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', `Inline source path must be a directory: ${directory}`, { stage: 'inline-modules' });
    }
    dirs.push(projectRelativePath(root, real));
  }

  for (const directory of dirs) await visit(path.resolve(root, directory));

  if (files.size === 0) return null;

  const sources = [...files.values()].sort((left, right) => compareText(left.path, right.path));
  const classes = sources.flatMap(file => file.modules.map(module => module.name));
  if (new Set(classes).size !== classes.length) {
    throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', 'Inline module class names must be unique within the app target.', { stage: 'inline-modules' });
  }

  const pkg = await readJsonAsync(path.join(root, 'package.json'), 'INVALID_INLINE_MODULE', 'inline-modules');

  return {
    packageName: typeof pkg.name === 'string' && pkg.name ? pkg.name : InlineModulesPackageName,
    packageVersion: typeof pkg.version === 'string' && pkg.version ? pkg.version : ToolVersion,
    packageRoot: root,
    source: 'inlineModules',
    supportsHarmony: true,
    expoModuleConfig: null,
    rnohMetadata: null,
    inlineModules: { watchedDirectories: [...new Set(dirs)].sort(compareText), files: sources },
    revision: { depth: 0, originPath: root },
  };
}

export async function resolveInlineModuleDescriptorAsync(input: Pick<SearchRecord, 'packageRoot' | 'inlineModules'>): Promise<ModuleDescriptor> {
  const record = await searchInlineModulesAsync(input.packageRoot, {
    watchedDirectories: input.inlineModules?.watchedDirectories,
  });
  if (!record) {
    throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', 'Inline module sources no longer exist.', { stage: 'inline-modules' });
  }

  const host = Object.fromEntries(HostMetadataFields.map(field => [field, []])) as unknown as ModuleDescriptor['expo'];

  return {
    packageName: record.packageName,
    packageVersion: record.packageVersion,
    packageRoot: record.packageRoot,
    packageLinkPath: record.packageRoot,
    source: 'inlineModules',
    expo: host,
    harmony: {
      ...host,
      modules: record.inlineModules.files.flatMap(file => file.modules.map(module => module.name)).sort(compareText),
      services: [],
    },
    rnoh: { harPaths: [] },
    artifact: { kind: 'bundled', harPaths: [] },
    inlineModules: record.inlineModules,
  };
}

export function inlineModuleArtifacts(module: Pick<ModuleDescriptor, 'inlineModules'>): string[] {
  return module.inlineModules?.files.map(file => path.posix.join(InlineModulesRoot, file.path)) ?? [];
}
