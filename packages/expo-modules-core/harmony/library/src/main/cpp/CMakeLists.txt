cmake_minimum_required(VERSION 3.19)
project(expo_modules_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(EXPO_REACT_NATIVE_MINOR_VERSION 84)
set(EXPO_HERMES_V1 ON)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh-package.json5" EXPO_MODULE_PACKAGE_JSON)
string(JSON EXPO_MODULE_HAR_VERSION GET "${EXPO_MODULE_PACKAGE_JSON}" version)
string(REGEX REPLACE "-harmony\\..*$" "" EXPO_MODULES_CORE_VERSION_VALUE "${EXPO_MODULE_HAR_VERSION}")
if(NOT EXPO_MODULES_CORE_VERSION_VALUE MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  message(FATAL_ERROR "Invalid Expo Modules Core HAR version: ${EXPO_MODULE_HAR_VERSION}")
endif()

if(DEFINED OH_MODULES_DIR)
  set(EXPO_OH_MODULES_DIR "${OH_MODULES_DIR}")
else()
  set(EXPO_OH_MODULES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules")
endif()

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

if(NOT TARGET rnoh_worklets)
  add_subdirectory(
    "${EXPO_OH_MODULES_DIR}/@react-native-ohos/react-native-worklets/src/main/cpp"
    "${CMAKE_CURRENT_BINARY_DIR}/worklets")
endif()

target_compile_definitions(rnoh_worklets PRIVATE
  HERMES_V1_ENABLED=$<BOOL:${EXPO_HERMES_V1}>)

get_target_property(EXPO_WORKLETS_SOURCE_DIR rnoh_worklets SOURCE_DIR)
get_target_property(EXPO_WORKLETS_SOURCES rnoh_worklets SOURCES)
foreach(EXPO_WORKLETS_SOURCE IN LISTS EXPO_WORKLETS_SOURCES)
  if(EXPO_WORKLETS_SOURCE MATCHES "/WorkletRuntime/WorkletRuntime\\.cpp$")
    set_source_files_properties(
      "${EXPO_WORKLETS_SOURCE}"
      DIRECTORY "${EXPO_WORKLETS_SOURCE_DIR}"
      PROPERTIES COMPILE_DEFINITIONS REACT_NATIVE_MINOR_VERSION=${EXPO_REACT_NATIVE_MINOR_VERSION})
  endif()
endforeach()
set_property(TARGET rnoh_worklets PROPERTY INTERFACE_SOURCES "")

file(GLOB_RECURSE EXPO_COMMON_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/common/*.cpp")
file(GLOB_RECURSE EXPO_HARMONY_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/api/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/errors/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/fabric/*.cpp"
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
  EXPO_MODULES_CORE_VERSION="${EXPO_MODULES_CORE_VERSION_VALUE}")

target_compile_definitions(expo_harmony__expo_modules_core PRIVATE
  EXPO_HARMONY=1
  REACT_NATIVE_MINOR_VERSION=${EXPO_REACT_NATIVE_MINOR_VERSION}
  WORKLETS_ENABLED=1)

target_include_directories(expo_harmony__expo_modules_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/common"
  "${CMAKE_CURRENT_SOURCE_DIR}/common/JSI"
  "${CMAKE_CURRENT_SOURCE_DIR}/common/fabric")

target_link_libraries(expo_harmony__expo_modules_core PUBLIC
  rnoh
  rnoh_worklets
  libace_napi.z.so
  libhilog_ndk.z.so)
