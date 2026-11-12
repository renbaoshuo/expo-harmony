/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include <array>
#include <cstring>
#include <limits.h>
#include <memory>
#include <string>
#include <unistd.h>

#include <napi/native_api.h>

extern "C" int bspatch_main(int argc, char *argv[]);
napi_value crash(napi_env env, napi_callback_info info);

struct Patch {
  std::array<std::string, 3> paths;
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  int result = 1;
};

static napi_value apply(napi_env env, napi_callback_info info) {
  size_t count = 4;
  napi_value args[4] = {};
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok) {
    return nullptr;
  }
  if (count != 3) {
    napi_throw_type_error(env, "ERR_UPDATES_PATCH", "Expected base, output, and patch paths.");
    return nullptr;
  }

  std::unique_ptr<Patch> patch;
  try {
    patch = std::make_unique<Patch>();
    for (size_t i = 0; i < count; i++) {
      size_t size = 0;
      if (napi_get_value_string_utf8(env, args[i], nullptr, 0, &size) != napi_ok || size == 0) {
        napi_throw_type_error(env, "ERR_UPDATES_PATCH", "Patch paths must be nonempty strings.");
        return nullptr;
      }

      patch->paths[i].resize(size);
      if (napi_get_value_string_utf8(env, args[i], patch->paths[i].data(), size + 1, &size) != napi_ok) {
        return nullptr;
      }
      if (patch->paths[i].find('\0') != std::string::npos) {
        napi_throw_type_error(env, "ERR_UPDATES_PATCH", "Patch paths cannot contain null bytes.");
        return nullptr;
      }
    }
  } catch (const std::exception &error) {
    napi_throw_error(env, "ERR_UPDATES_PATCH", error.what());
    return nullptr;
  }

  napi_value promise = nullptr, name = nullptr;
  if (napi_create_string_utf8(env, "ExpoUpdatesPatch", NAPI_AUTO_LENGTH, &name) != napi_ok || napi_create_promise(env, &patch->deferred, &promise) != napi_ok) {
    return nullptr;
  }
  const auto created = napi_create_async_work(env, nullptr, name, [](napi_env, void *data) {
      auto *patch = static_cast<Patch *>(data);
      std::array<char *, 4> args = {const_cast<char *>("bspatch"), patch->paths[0].data(), patch->paths[1].data(), patch->paths[2].data()};
      patch->result = bspatch_main(static_cast<int>(args.size()), args.data());
    }, [](napi_env env, napi_status status, void *data) {
      std::unique_ptr<Patch> patch(static_cast<Patch *>(data));
      napi_value result;
      napi_create_int32(env, status == napi_ok ? patch->result : 1, &result);
      napi_resolve_deferred(env, patch->deferred, result);
      napi_delete_async_work(env, patch->work);
    }, patch.get(), &patch->work);

  if (created != napi_ok || napi_queue_async_work(env, patch->work) != napi_ok) {
    if (patch->work) {
      napi_delete_async_work(env, patch->work);
    }
    napi_value result;
    napi_create_int32(env, 1, &result);
    napi_resolve_deferred(env, patch->deferred, result);
    return promise;
  }

  patch.release();

  return promise;
}

static napi_value linkAsset(napi_env env, napi_callback_info info) {
  size_t count = 2;
  napi_value args[2] = {};
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok) {
    return nullptr;
  }

  std::array<char, PATH_MAX> paths[2] = {};
  bool valid = count == 2;
  for (size_t i = 0; i < count && valid; i++) {
    size_t length = 0;
    valid = napi_get_value_string_utf8(env, args[i], nullptr, 0, &length) == napi_ok &&
        length > 0 && length < paths[i].size() &&
        napi_get_value_string_utf8(env, args[i], paths[i].data(), paths[i].size(), &length) == napi_ok &&
        std::memchr(paths[i].data(), '\0', length) == nullptr;
  }

  napi_value result = nullptr;
  napi_get_boolean(env, valid && link(paths[0].data(), paths[1].data()) == 0, &result);

  return result;
}

static napi_value initialize(napi_env env, napi_value exports) {
  napi_property_descriptor methods[] = {
      {"applyPatch", nullptr, apply, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"linkAsset", nullptr, linkAsset, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"crash", nullptr, crash, nullptr, nullptr, nullptr, napi_default, nullptr}};
  napi_define_properties(env, exports, 3, methods);
  return exports;
}

static napi_module module = {1, 0, nullptr, initialize, "expo_updates", nullptr, {0}};

extern "C" __attribute__((constructor)) void registerUpdates() {
  napi_module_register(&module);
}
