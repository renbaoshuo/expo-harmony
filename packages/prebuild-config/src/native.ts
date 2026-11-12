/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import ts from 'typescript';

function getProperty(object: ts.ObjectLiteralExpression, name: string): ts.Expression | undefined {
  // A spread or computed name can override a property without naming it in the source.
  if (object.properties.some(property => (
    ts.isSpreadAssignment(property) || (property.name && ts.isComputedPropertyName(property.name))
  ))) {
    return undefined;
  }

  const properties = object.properties.filter(property => (
    property.name && (ts.isIdentifier(property.name) || ts.isStringLiteral(property.name))
    && property.name.text === name
  ));
  const [property] = properties;
  return properties.length === 1 && ts.isPropertyAssignment(property) ? property.initializer : undefined;
}

function isRnohAutolinkingDisabled(source: string): boolean {
  if (typeof source !== 'string' || !source.trim()) {
    throw new TypeError('module hvigorfile.ts must start from the canonical Harmony template source.');
  }

  const file = ts.createSourceFile('hvigorfile.ts', source, ts.ScriptTarget.Latest);
  const bindings = new Set<string>();
  for (const statement of file.statements) {
    if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)
      || statement.moduleSpecifier.text !== '@rnoh/hvigor-plugin' || statement.importClause?.isTypeOnly) continue;

    const imports = statement.importClause?.namedBindings;
    if (!imports || !ts.isNamedImports(imports)) continue;
    for (const binding of imports.elements) {
      if (!binding.isTypeOnly && (binding.propertyName ?? binding.name).text === 'createRNOHModulePlugin') {
        bindings.add(binding.name.text);
      }
    }
  }

  const exported = file.statements.find(ts.isExportAssignment)?.expression;
  if (!exported || !ts.isObjectLiteralExpression(exported)) return false;

  const plugins = getProperty(exported, 'plugins');
  if (!plugins || !ts.isArrayLiteralExpression(plugins) || !plugins.elements.length) return false;

  return plugins.elements.every((plugin) => {
    if (!ts.isCallExpression(plugin) || !ts.isIdentifier(plugin.expression) || !bindings.has(plugin.expression.text)) {
      return false;
    }
    const [options] = plugin.arguments;
    return Boolean(options && ts.isObjectLiteralExpression(options)
      && getProperty(options, 'autolinking')?.kind === ts.SyntaxKind.NullKeyword);
  });
}

export {
  isRnohAutolinkingDisabled,
};
