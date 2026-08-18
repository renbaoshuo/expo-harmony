#include "ExpoConstantsProvider.h"

#if __has_include(<ExpoHarmonyGeneratedConstants.h>)
#include <ExpoHarmonyGeneratedConstants.h>
#else
#include "ExpoHarmonyConstants.h"
#endif

#include <cctype>
#include <cmath>
#include <deviceinfo.h>
#include <optional>
#include <set>
#include <string>

#include <jsi/JSIDynamic.h>

#include <folly/json.h>
#include <native_drawing/drawing_font_mgr.h>
#include <sys/utsname.h>

#include "modules/Uuid.h"

namespace jsi = facebook::jsi;

namespace expo::harmony::constants {
namespace {

constexpr const char *kServiceName = "ExpoConstantsService";
constexpr const char *kStatusBarMethod = "getStatusBarHeight";

std::string numericVersion(const char *value) {
  if (!value) {
    return {};
  }
  const char *begin = value;
  while (*begin && !std::isdigit(static_cast<unsigned char>(*begin))) {
    ++begin;
  }
  const char *end = begin;
  while (*end && (std::isdigit(static_cast<unsigned char>(*end)) || *end == '.')) {
    ++end;
  }
  while (end > begin && end[-1] == '.') {
    --end;
  }
  return std::string(begin, end);
}

std::string systemVersion() {
  for (const char *candidate : {
           OH_GetOSFullName(),
           OH_GetDistributionOSVersion(),
           OH_GetDisplayVersion(),
       }) {
    auto version = numericVersion(candidate);
    if (!version.empty()) {
      return version;
    }
  }
  struct utsname value{};
  return uname(&value) == 0 ? numericVersion(value.release) : std::string();
}

std::string deviceName() {
  const char *marketName = OH_GetMarketName();
  if (marketName && *marketName) {
    return marketName;
  }
  const char *model = OH_GetProductModel();
  if (model && *model) {
    return model;
  }
  const char *type = OH_GetDeviceType();
  return type && *type ? std::string("HarmonyOS ") + type : "HarmonyOS device";
}

std::optional<folly::dynamic> parseManifest() {
  const std::string raw = EXPO_HARMONY_APP_CONFIG_JSON;
  if (raw.empty()) {
    return std::nullopt;
  }
  try {
    auto parsed = folly::parseJson(raw);
    if (!parsed.isObject()) {
      throw CodedError("ERR_CONSTANTS_INVALID_APP_CONFIG", "The embedded Expo app config must be a JSON object.");
    }
    return std::move(parsed);
  } catch (const CodedError &) {
    throw;
  } catch (const std::exception &error) {
    throw CodedError(
        "ERR_CONSTANTS_INVALID_APP_CONFIG",
        "The embedded Expo app config is invalid JSON: " + std::string(error.what()));
  } catch (...) {
    throw CodedError(
        "ERR_CONSTANTS_INVALID_APP_CONFIG",
        "The embedded Expo app config could not be parsed.");
  }
}

jsi::Value dynamicValue(Invocation &invocation, const folly::dynamic &value) {
  return jsi::valueFromDynamic(invocation.runtime(), value);
}

double readStatusBarHeight(const std::shared_ptr<RuntimeContext> &context) noexcept {
  try {
    auto value = context->invokePlatformServiceSync(
        kServiceName, kStatusBarMethod, folly::dynamic::array());
    if (value.isNumber() && std::isfinite(value.getNumber()) && value.getNumber() >= 0) {
      return value.getNumber();
    }
  } catch (...) {
  }
  return 0;
}

const folly::dynamic &systemFonts() {
  static const auto fonts = [] {
    std::set<std::string> names{"monospace", "sans-serif", "serif"};
    auto *manager = OH_Drawing_FontMgrCreate();
    if (manager) {
      const auto count = OH_Drawing_FontMgrGetFamilyCount(manager);
      for (int index = 0; index < count; ++index) {
        char *value = OH_Drawing_FontMgrGetFamilyName(manager, index);
        if (value && *value) {
          names.insert(value);
        }
        if (value) {
          OH_Drawing_FontMgrDestroyFamilyName(value);
        }
      }
      OH_Drawing_FontMgrDestroy(manager);
    }
    auto result = folly::dynamic::array();
    for (const auto &name : names) {
      result.push_back(name);
    }
    return result;
  }();
  return fonts;
}

class ExpoConstantsModule final : public ExpoModule {
public:
  explicit ExpoConstantsModule(std::shared_ptr<RuntimeContext> context)
      : context_(context),
        sessionId_(expo::harmony::uuidV4()) {}

  ModuleDefinition definition() override {
    ModuleBuilder module("ExponentConstants");
    module.constant("appOwnership", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("debugMode", [](Invocation &) {
      return jsi::Value(EXPO_HARMONY_DEBUG_MODE);
    });
    module.constant("deviceName", [](Invocation &invocation) {
      return jsi::String::createFromUtf8(invocation.runtime(), deviceName());
    });
    module.constant("deviceYearClass", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("executionEnvironment", [](Invocation &invocation) {
      return jsi::String::createFromAscii(invocation.runtime(), "bare");
    });
    module.constant("experienceUrl", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("expoRuntimeVersion", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("expoVersion", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("isHeadless", [](Invocation &) {
      return jsi::Value(false);
    });
    module.constant("linkingUri", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("manifest", [](Invocation &invocation) -> jsi::Value {
      auto manifest = parseManifest();
      if (!manifest) {
        return jsi::Value(nullptr);
      }
      return jsi::String::createFromUtf8(
          invocation.runtime(), folly::toJson(*manifest));
    });
    module.constant("manifest2", [](Invocation &) {
      return jsi::Value(nullptr);
    });
    module.constant("sessionId", [this](Invocation &invocation) {
      return jsi::String::createFromUtf8(invocation.runtime(), sessionId_);
    });
    module.constant("statusBarHeight", [context = context_](Invocation &) {
      auto runtimeContext = context.lock();
      return jsi::Value(
          runtimeContext && runtimeContext->isAlive()
              ? readStatusBarHeight(runtimeContext)
              : 0);
    });
    module.constant("systemFonts", [](Invocation &invocation) {
      return dynamicValue(invocation, systemFonts());
    });
    module.constant("systemVersion", [](Invocation &invocation) {
      return jsi::String::createFromUtf8(invocation.runtime(), systemVersion());
    });
    module.constant("platform", [](Invocation &invocation) {
      auto harmony = folly::dynamic::object("bundleName", EXPO_HARMONY_BUNDLE_NAME)("versionName", EXPO_HARMONY_VERSION_NAME)("versionCode", EXPO_HARMONY_VERSION_CODE)("deviceType", OH_GetDeviceType() ? OH_GetDeviceType() : "default")("apiVersion", OH_GetSdkApiVersion())("osFullName", OH_GetOSFullName() ? OH_GetOSFullName() : "");
      return dynamicValue(invocation, folly::dynamic::object("harmony", std::move(harmony)));
    });
    module.function(FunctionDefinition{
        .name = "getWebViewUserAgentAsync",
        .arity = 0,
        .async = true,
        .body = [](Invocation &invocation) {
          return invocation.context().invokePlatformService(
              kServiceName, "getWebViewUserAgent", folly::dynamic::array());
        }});
    return std::move(module).build();
  }

private:
  std::weak_ptr<RuntimeContext> context_;
  std::string sessionId_;
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoConstantsProvider::modules(
    const std::shared_ptr<RuntimeContext> &context) {
  return {std::make_shared<ExpoConstantsModule>(context)};
}

}  // namespace expo::harmony::constants
