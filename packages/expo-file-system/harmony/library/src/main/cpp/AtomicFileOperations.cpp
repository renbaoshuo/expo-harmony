#include "ExclusiveFileCreate.h"

#include <cstring>
#include <limits.h>
#include <stdio.h>
#include "napi/native_api.h"

namespace {

bool ReadAbsolutePath(napi_env env, napi_value value, char (&path)[PATH_MAX]) {
  napi_valuetype type;
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
    napi_throw_type_error(env, "ERR_FILE_SYSTEM_INVALID_PATH", "An absolute file path is required");
    return false;
  }
  size_t size = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) return false;
  if (size >= PATH_MAX) {
    napi_throw_range_error(env, "ERR_FILE_SYSTEM_INVALID_PATH", "The file path exceeds the platform PATH_MAX limit");
    return false;
  }
  size_t copied = 0;
  if (napi_get_value_string_utf8(env, value, path, sizeof(path), &copied) != napi_ok) return false;
  if (copied == 0 || path[0] != '/' || std::strlen(path) != copied) {
    napi_throw_type_error(env, "ERR_FILE_SYSTEM_INVALID_PATH", "The file path must be absolute and contain no NUL bytes");
    return false;
  }
  return true;
}

napi_value ExclusiveCreate(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1) {
    napi_throw_type_error(env, "ERR_FILE_SYSTEM_INVALID_PATH", "An absolute file path is required");
    return nullptr;
  }
  char path[PATH_MAX];
  if (!ReadAbsolutePath(env, argv[0], path)) return nullptr;
  const int error = expo::filesystem::exclusiveCreateFile(path);
  if (error != 0) {
    napi_throw_error(env, error == EEXIST ? "ERR_FILE_SYSTEM_DESTINATION_EXISTS" : "ERR_FILE_SYSTEM_CANNOT_CREATE",
                     std::strerror(error));
    return nullptr;
  }
  napi_value result;
  if (napi_get_undefined(env, &result) != napi_ok) return nullptr;
  return result;
}

napi_value PublishNoReplace(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2];
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 2) {
    napi_throw_type_error(env, "ERR_FILE_SYSTEM_INVALID_PATH", "Absolute source and destination paths are required");
    return nullptr;
  }
  char source[PATH_MAX];
  char target[PATH_MAX];
  if (!ReadAbsolutePath(env, argv[0], source) || !ReadAbsolutePath(env, argv[1], target)) return nullptr;
  // Keep the check and rename in one filesystem operation. Unsupported filesystems
  // must fail rather than fall back to an existence check followed by rename.
  if (renameat2(AT_FDCWD, source, AT_FDCWD, target, RENAME_NOREPLACE) != 0) {
    const int error = errno;
    const char* code = error == EEXIST ? "ERR_FILE_SYSTEM_DESTINATION_EXISTS" :
      error == EXDEV ? "ERR_FILE_SYSTEM_CROSS_DEVICE" :
      (error == ENOSYS || error == EOPNOTSUPP ? "ERR_FILE_SYSTEM_PUBLISH_NOT_SUPPORTED" : "ERR_FILE_SYSTEM_CANNOT_PUBLISH");
    napi_throw_error(env, code, std::strerror(error));
    return nullptr;
  }
  napi_value result;
  if (napi_get_undefined(env, &result) != napi_ok) return nullptr;
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
    { "exclusiveCreate", nullptr, ExclusiveCreate, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "publishNoReplace", nullptr, PublishNoReplace, nullptr, nullptr, nullptr, napi_default, nullptr },
  };
  if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) return nullptr;
  return exports;
}

napi_module module = { 1, 0, nullptr, Init, "expo_file_system_atomic", nullptr, { 0 } };

} // namespace

extern "C" __attribute__((constructor)) void RegisterExpoFileSystemAtomic() {
  napi_module_register(&module);
}
