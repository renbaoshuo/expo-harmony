/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include <memory>
#include <napi/native_api.h>
#include <native_drawing/drawing_font_mgr.h>

namespace {
napi_value getSystemFontFamilies(napi_env env, napi_callback_info) {
  napi_value fonts;
  if (napi_create_array(env, &fonts) != napi_ok) return nullptr;

  std::unique_ptr<OH_Drawing_FontMgr, decltype(&OH_Drawing_FontMgrDestroy)> manager(
      OH_Drawing_FontMgrCreate(), OH_Drawing_FontMgrDestroy);
  if (!manager) return fonts;

  const int count = OH_Drawing_FontMgrGetFamilyCount(manager.get());
  uint32_t next = 0;
  for (int index = 0; index < count; ++index) {
    std::unique_ptr<char, decltype(&OH_Drawing_FontMgrDestroyFamilyName)> name(
        OH_Drawing_FontMgrGetFamilyName(manager.get(), index), OH_Drawing_FontMgrDestroyFamilyName);
    if (!name || *name.get() == '\0') continue;

    napi_value family;
    if (napi_create_string_utf8(env, name.get(), NAPI_AUTO_LENGTH, &family) != napi_ok ||
        napi_set_element(env, fonts, next++, family) != napi_ok) {
      return nullptr;
    }
  }

  return fonts;
}

napi_value initialize(napi_env env, napi_value exports) {
  const napi_property_descriptor method = {
      "getSystemFontFamilies", nullptr, getSystemFontFamilies, nullptr, nullptr, nullptr, napi_default, nullptr};
  return napi_define_properties(env, exports, 1, &method) == napi_ok ? exports : nullptr;
}

napi_module module = {1, 0, nullptr, initialize, "expo_constants_fonts", nullptr, {0}};
} // namespace

extern "C" __attribute__((constructor)) void registerExpoConstantsFonts() {
  napi_module_register(&module);
}
