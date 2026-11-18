# @expo-harmony-copyright
#
# Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
# Released under MIT license. https://github.com/renbaoshuo/expo-harmony
# @end-expo-harmony-copyright

cmake_minimum_required(VERSION 3.24)
project(expo_fetch_legacy LANGUAGES C CXX)

include(FetchContent)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Honor the local options even when a dependency declares an older CMake policy version.
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
set(CMAKE_POLICY_DEFAULT_CMP0126 NEW)
set(ENABLE_PROGRAMS OFF)
set(ENABLE_TESTING OFF)
set(MBEDTLS_FATAL_WARNINGS OFF)
set(MBEDTLS_USER_CONFIG_FILE "${CMAKE_CURRENT_SOURCE_DIR}/MbedTlsConfig.h")
FetchContent_Declare(mbedtls
  URL https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.8/mbedtls-3.6.8.tar.bz2
  URL_HASH SHA256=bc54b818e87f49c0b3281dd85d24adaede0e63b4e822e3fbd49c005a38b9595b)
FetchContent_MakeAvailable(mbedtls)

set(BUILD_SHARED_LIBS OFF)
set(BUILD_CURL_EXE OFF)
set(BUILD_TESTING OFF)
set(CURL_DISABLE_INSTALL ON)
set(HTTP_ONLY ON)
set(CURL_USE_OPENSSL OFF)
set(CURL_USE_MBEDTLS ON)
set(CURL_USE_PKGCONFIG OFF)
set(CURL_USE_LIBPSL OFF)
set(CURL_DISABLE_NTLM ON)
set(USE_LIBIDN2 OFF)
set(USE_NGHTTP2 OFF)
set(CURL_ZLIB ON)
set(CURL_BROTLI OFF)
set(CURL_ZSTD OFF)
# Use the system directory selected by the transport, independent of the build host.
set(CURL_CA_BUNDLE "none" CACHE STRING "curl default CA file" FORCE)
set(CURL_CA_PATH "none" CACHE STRING "curl default CA path" FORCE)
set(MBEDTLS_INCLUDE_DIR "${mbedtls_SOURCE_DIR}/include")
set(MBEDTLS_LIBRARY MbedTLS::mbedtls)
set(MBEDX509_LIBRARY MbedTLS::mbedx509)
set(MBEDCRYPTO_LIBRARY MbedTLS::mbedcrypto)
# The TLS libraries are built with curl. Its configure-time link probe cannot see them yet.
set(HAVE_MBEDTLS_DES_CRYPT_ECB 0)
FetchContent_Declare(curl
  URL https://curl.se/download/curl-8.23.0.tar.xz
  URL_HASH SHA256=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5)
FetchContent_MakeAvailable(curl)

add_library(expo_fetch_legacy SHARED LegacyFetchBinding.cpp HttpTransfer.cpp)
target_compile_features(expo_fetch_legacy PRIVATE cxx_std_20)
target_compile_options(expo_fetch_legacy PRIVATE -Wall -Wextra)
set_target_properties(expo_fetch_legacy PROPERTIES
  CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_link_options(expo_fetch_legacy PRIVATE -Wl,--exclude-libs,ALL)
target_link_libraries(expo_fetch_legacy PRIVATE CURL::libcurl libace_napi.z.so)
