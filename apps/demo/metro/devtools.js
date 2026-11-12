/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { gzipSync } = require('node:zlib');

module.exports = function devtools(request, response, next) {
  const path = new URL(request.url, 'http://localhost').pathname;
  if (!path.startsWith('/__devtools__/')) return next();

  const route = path.slice('/__devtools__/'.length);
  const text = Buffer.from('Expo Harmony 网络');
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Content-Type', 'text/plain; charset=utf-8');

  if (route === 'gzip') {
    const compressed = gzipSync(text);
    response.setHeader('Content-Encoding', 'gzip');
    response.setHeader('Content-Length', compressed.length);
    response.end(request.method === 'HEAD' ? undefined : compressed);
    return;
  }

  if (route === 'echo') {
    let length = 0;
    const chunks = [];
    request.on('data', (chunk) => {
      length += chunk.length;
      if (length > 2 * 1024 * 1024) {
        response.writeHead(413).end();
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => {
      const body = Buffer.concat(chunks);
      response.setHeader('Content-Type', request.headers['content-type'] ?? 'application/octet-stream');
      response.setHeader('Content-Length', body.length);
      response.end(body);
    });
    return;
  }

  if (route === 'stream' || route === 'slow') {
    response.write(text.subarray(0, 5));
    const timer = setTimeout(() => response.end(text.subarray(5)), route === 'slow' ? 5000 : 50);
    response.on('close', () => clearTimeout(timer));
    return;
  }

  let body;
  switch (route) {
    case 'text':
      body = text;
      break;
    case 'empty':
      body = Buffer.alloc(0);
      break;
    case 'binary':
      response.setHeader('Content-Type', 'application/octet-stream');
      body = Buffer.from(Array.from({ length: 256 }, (_, index) => index));
      break;
    case 'limit':
      body = Buffer.alloc(1048576, 'x');
      break;
    case 'large':
      body = Buffer.alloc(1048577, 'x');
      break;
    default:
      response.writeHead(404).end();
      return;
  }

  response.setHeader('Content-Length', body.length);
  response.end(body);
};
