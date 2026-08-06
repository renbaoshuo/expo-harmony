'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { withHarmonyConfig } = require('..');

test('enabled false is a dependency-free no-op', () => {
  const config = { resolver: {} };
  assert.equal(withHarmonyConfig(config, { enabled: false }), config);
});
