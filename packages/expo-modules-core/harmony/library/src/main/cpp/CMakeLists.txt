# @expo-harmony-copyright
#
# Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
# Released under MIT license. https://github.com/renbaoshuo/expo-harmony
# @end-expo-harmony-copyright

cmake_minimum_required(VERSION 3.19)
project(expo_modules_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/PackageVersion.cmake")
read_expo_package_version("${CMAKE_CURRENT_SOURCE_DIR}/../../../oh-package.json5" EXPO_MODULE_HAR_VERSION)
string(REGEX REPLACE "-harmony\\..*$" "" EXPO_MODULES_CORE_VERSION_VALUE "${EXPO_MODULE_HAR_VERSION}")
if(NOT EXPO_MODULES_CORE_VERSION_VALUE MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  message(FATAL_ERROR "Invalid Expo Modules Core HAR version: ${EXPO_MODULE_HAR_VERSION}")
endif()

if(DEFINED OH_MODULES_DIR)
  set(EXPO_OH_MODULES_DIR "${OH_MODULES_DIR}")
else()
  set(EXPO_OH_MODULES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules")
endif()

set(EXPO_RNOH_PACKAGE_JSON_PATH
  "${EXPO_OH_MODULES_DIR}/@rnoh/react-native-openharmony/oh-package.json5")
if(NOT EXISTS "${EXPO_RNOH_PACKAGE_JSON_PATH}")
  message(FATAL_ERROR "Unable to locate the RNOH package manifest")
endif()
read_expo_package_version("${EXPO_RNOH_PACKAGE_JSON_PATH}" EXPO_RNOH_VERSION)
if(NOT EXPO_RNOH_VERSION MATCHES "^0\\.([0-9]+)\\.")
  message(FATAL_ERROR "Unable to derive the React Native minor from RNOH ${EXPO_RNOH_VERSION}")
endif()
set(EXPO_REACT_NATIVE_MINOR_VERSION "${CMAKE_MATCH_1}")
if(NOT TARGET rnoh)
  set(ENABLE_COMPILE_OPTIMIZATIONS OFF CACHE BOOL "" FORCE)

  if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND DEFINED OHOS_SDK_NATIVE)
    set(CMAKE_CXX_FLAGS
      "${CMAKE_CXX_FLAGS} -include ${OHOS_SDK_NATIVE}/sysroot/usr/include/assert.h")
  endif()

  add_subdirectory(
    "${EXPO_OH_MODULES_DIR}/@rnoh/react-native-openharmony/src/main/cpp"
    "${CMAKE_CURRENT_BINARY_DIR}/rnoh")
endif()

if(TARGET rnoh_core)
  get_target_property(RNOH_CORE_SOURCE_DIR rnoh_core SOURCE_DIR)
  set(RNOH_EXCEPTION_STACK_SOURCE "${RNOH_CORE_SOURCE_DIR}/ExceptionStackHandler.cpp")
  if(EXISTS "${RNOH_EXCEPTION_STACK_SOURCE}")
    # RNOH checks API 15 at runtime, but strong references stop its library from loading on API 14.
    set_property(SOURCE "${RNOH_EXCEPTION_STACK_SOURCE}"
      TARGET_DIRECTORY rnoh_core APPEND PROPERTY COMPILE_OPTIONS
      -include "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RnohHiAppEventCompat.h")
  endif()
endif()

set(EXPO_WORKLETS_ENABLED OFF)
if(TARGET rnoh_worklets)
  set(EXPO_WORKLETS_ENABLED ON)
endif()

file(GLOB_RECURSE EXPO_COMMON_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/common/*.cpp")
file(GLOB_RECURSE EXPO_HARMONY_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/api/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/errors/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/fabric/*.cpp"
  # Includes the single common ArkTSModuleAdapter; modules never add C++ here.
  "${CMAKE_CURRENT_SOURCE_DIR}/modules/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/objects/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/package/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/runtime/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/types/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/worklets/*.cpp")

add_library(expo_harmony__expo_modules_core SHARED
  ${EXPO_COMMON_SOURCES}
  ${EXPO_HARMONY_SOURCES})

target_compile_definitions(expo_harmony__expo_modules_core PUBLIC
  EXPO_MODULES_CORE_VERSION="${EXPO_MODULES_CORE_VERSION_VALUE}"
  WORKLETS_ENABLED=$<BOOL:${EXPO_WORKLETS_ENABLED}>)

target_compile_definitions(expo_harmony__expo_modules_core PRIVATE
  EXPO_HARMONY=1
  REACT_NATIVE_MINOR_VERSION=${EXPO_REACT_NATIVE_MINOR_VERSION})

target_include_directories(expo_harmony__expo_modules_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/common"
  "${CMAKE_CURRENT_SOURCE_DIR}/common/JSI"
  "${CMAKE_CURRENT_SOURCE_DIR}/common/fabric")

target_link_libraries(expo_harmony__expo_modules_core PUBLIC
  rnoh
  libace_napi.z.so
  libhilog_ndk.z.so)

if(EXPO_WORKLETS_ENABLED)
  target_link_libraries(expo_harmony__expo_modules_core PRIVATE
    rnoh_worklets)
endif()
