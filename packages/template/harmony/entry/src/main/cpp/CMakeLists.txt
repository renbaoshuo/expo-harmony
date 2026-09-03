cmake_minimum_required(VERSION 3.13)
project(expo_harmony_app LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(OH_MODULES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../oh_modules")
set(RNOH_CPP_DIR "${OH_MODULES_DIR}/@rnoh/react-native-openharmony/src/main/cpp")
set(RNOH_CODEGEN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/rnoh_codegen")
set(RNOH_GENERATED_DIR "${RNOH_CODEGEN_ROOT}/generated")
set(LOG_VERBOSITY_LEVEL 1)
set(CMAKE_ASM_FLAGS "-Wno-error=unused-command-line-argument -Qunused-arguments")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack")

# Hvigor rewrites this ignored stamp only when the bytes of a linked HAR change.
# The digest is part of every native compile command, so deterministic archives
# with normalized old mtimes cannot make Ninja reuse stale objects.
set(EXPO_HARMONY_NATIVE_INPUTS_STAMP
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.hvigor/expo-harmony/native-inputs.cmake")
if(NOT EXISTS "${EXPO_HARMONY_NATIVE_INPUTS_STAMP}")
  message(FATAL_ERROR "Harmony native input fingerprint is missing; build through the root Hvigor project.")
endif()
include("${EXPO_HARMONY_NATIVE_INPUTS_STAMP}")

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND DEFINED OHOS_SDK_NATIVE)
  set(CMAKE_CXX_FLAGS
    "${CMAKE_CXX_FLAGS} -include ${OHOS_SDK_NATIVE}/sysroot/usr/include/assert.h")
endif()

add_subdirectory("${RNOH_CPP_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/rnoh")
include("${CMAKE_CURRENT_SOURCE_DIR}/autolinking.cmake")

file(GLOB GENERATED_CPP_FILES "${RNOH_GENERATED_DIR}/*.cpp")
add_library(rnoh_app SHARED
  ${GENERATED_CPP_FILES}
  "./PackageProvider.cpp"
  "${RNOH_CPP_DIR}/RNOHAppNapiBridge.cpp")

target_link_libraries(rnoh_app PUBLIC rnoh)
target_include_directories(rnoh_app PRIVATE "${RNOH_CODEGEN_ROOT}")
target_include_directories(rnoh_app PRIVATE
  "${OH_MODULES_DIR}/@expo-harmony/expo-modules-core/src/main/cpp/package")
autolink_libraries(rnoh_app)
