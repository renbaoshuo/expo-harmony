'use strict';

const pkg = require('../package.json');

module.exports = (props = {}) => [pkg.name, props];
