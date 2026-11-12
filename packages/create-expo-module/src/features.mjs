/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export const ALL_FEATURES = ['Constant', 'Function', 'AsyncFunction', 'Event', 'View', 'ViewEvent', 'SharedObject'];

export function resolveFeatures(selected = [], fullExample = false) {
  if (fullExample || selected.includes('all')) return [...ALL_FEATURES];

  const invalid = selected.filter(feature => !ALL_FEATURES.includes(feature));
  if (invalid.length) {
    throw new TypeError(`Unsupported Harmony feature(s): ${invalid.join(', ')}. Available: ${ALL_FEATURES.join(', ')}. SwiftUI/Compose require Apple/Android.`);
  }

  const features = new Set(selected);
  if (features.has('ViewEvent')) features.add('View');

  return ALL_FEATURES.filter(feature => features.has(feature));
}

// Source detection is best effort: it selects examples, never translates business logic.
export function detectFeatures(content) {
  const result = new Set();
  const scopes = [];
  let pendingScope;
  const source = content.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g, ' ');
  const tokens = /[{}]|\b(Constant|AsyncFunction|Function|Class|View|Events)(?=\s*\()/g;

  for (const [token] of source.matchAll(tokens)) {
    if (token === '{') {
      scopes.push(pendingScope ?? scopes.at(-1));
      pendingScope = undefined;
    } else if (token === '}') {
      scopes.pop();
      pendingScope = undefined;
    } else if (token === 'Events') {
      if (scopes.at(-1) !== 'Class') result.add(scopes.at(-1) === 'View' ? 'ViewEvent' : 'Event');
    } else if (token === 'View' || token === 'Class') {
      result.add(token === 'Class' ? 'SharedObject' : token);
      pendingScope = token;
    } else if (!scopes.at(-1)) {
      result.add(token);
    }
  }

  return resolveFeatures([...result]);
}

export function renderFeatureBlocks(source, features) {
  return source.replace(/\{\{([#^])(\w+)\}\}([\s\S]*?)\{\{\/\2\}\}/g, (_match, mode, feature, body) => {
    if (!ALL_FEATURES.includes(feature)) throw new Error(`Unknown template feature: ${feature}`);
    return features.includes(feature) === (mode === '#') ? renderFeatureBlocks(body, features) : '';
  });
}
