/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

// libcurl shares its TLS random generator across transfers on different threads.
#define MBEDTLS_THREADING_C
#define MBEDTLS_THREADING_PTHREAD
