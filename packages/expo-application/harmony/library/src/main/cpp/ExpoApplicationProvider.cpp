#include "ExpoApplicationProvider.h"

#include <optional>
#include <string>

namespace expo::harmony::application {
namespace {

constexpr auto kServiceName = "ExpoApplicationService";

std::shared_ptr<RuntimeContext> requireContext(const std::weak_ptr<RuntimeContext> &weakContext) {
  auto context = weakContext.lock();
  if (!context || !context->isAlive()) {
    throw CodedError("ERR_RUNTIME_DESTROYED", "Cannot read application information after runtime destruction.");
  }
  return context;
}

std::optional<std::string> readOptionalString(
    const std::weak_ptr<RuntimeContext> &weakContext,
    const char *method,
    const char *field,
    const char *errorCode) {
  auto context = requireContext(weakContext);

  auto value = context->invokePlatformServiceSync(kServiceName, method, folly::dynamic::array());
  if (value.isNull() || value.isUndefined()) {
    return std::nullopt;
  }
  if (!value.isString()) {
    throw CodedError(errorCode, std::string("Harmony returned an invalid '") + field + "' value.");
  }

  auto result = value.getString(context->runtime()).utf8(context->runtime());
  return result.empty() ? std::nullopt : std::optional<std::string>(std::move(result));
}

FunctionDefinition timeFunction(std::string name, std::string method) {
  return FunctionDefinition{
      .name = std::move(name),
      .arity = 0,
      .requiredArity = 0,
      .async = true,
      .body = [method = std::move(method)](Invocation &invocation) {
        return invocation.context().invokePlatformService(
            kServiceName, method, folly::dynamic::array());
      }};
}

class ExpoApplicationModule final : public ExpoModule {
public:
  explicit ExpoApplicationModule(
      const std::shared_ptr<RuntimeContext> &context)
      : context_(context) {}

  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoApplication");
    module.constant<std::optional<std::string>>(
        "applicationName", [context = context_]() {
          return readOptionalString(
              context,
              "getApplicationName",
              "applicationName",
              "ERR_APPLICATION_NAME");
        });
    module.constant<std::optional<std::string>>(
        "applicationId", [context = context_]() {
          return readOptionalString(
              context,
              "getApplicationId",
              "applicationId",
              "ERR_APPLICATION_ID");
        });
    module.constant<std::optional<std::string>>(
        "nativeApplicationVersion", [context = context_]() {
          return readOptionalString(
              context,
              "getNativeApplicationVersion",
              "nativeApplicationVersion",
              "ERR_APPLICATION_VERSION");
        });
    module.constant<std::optional<std::string>>(
        "nativeBuildVersion", [context = context_]() {
          return readOptionalString(
              context,
              "getNativeBuildVersion",
              "nativeBuildVersion",
              "ERR_APPLICATION_BUILD_VERSION");
        });
    module.function(timeFunction(
        "getInstallationTimeAsync", "getInstallationTime"));
    module.function(timeFunction(
        "getLastUpdateTimeAsync", "getLastUpdateTime"));
    return std::move(module).build();
  }

private:
  std::weak_ptr<RuntimeContext> context_;
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoApplicationProvider::modules(
    const std::shared_ptr<RuntimeContext> &context) {
  return {std::make_shared<ExpoApplicationModule>(context)};
}
}  // namespace expo::harmony::application
