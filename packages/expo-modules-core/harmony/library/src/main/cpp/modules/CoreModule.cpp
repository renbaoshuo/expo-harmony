#include "CoreModule.h"

#include <algorithm>
#include <string>

#include "api/Version.h"
#include "errors/CodedError.h"
#include "fabric/ExpoViewComponentRegistry.h"
#include "modules/ExpoModulesCoreTurboModule.h"
#include "modules/Uuid.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"
#include "worklets/WorkletRuntimeInstaller.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

std::shared_ptr<RuntimeContext> requireContext(
    const std::weak_ptr<RuntimeContext> &weakContext) {
  auto context = weakContext.lock();
  if (!context || !context->isAlive()) {
    throw CodedError("ERR_RUNTIME_DESTROYED", "Expo AppContext has been destroyed.");
  }
  return context;
}

jsi::Value versionObject(Invocation &invocation) {
  auto &runtime = invocation.runtime();
  jsi::Object value(runtime);
  value.setProperty(
      runtime,
      "version",
      jsi::String::createFromUtf8(runtime, ExpoModulesCoreVersion));
  value.setProperty(runtime, "major", ExpoModulesCoreVersionMajor);
  value.setProperty(runtime, "minor", ExpoModulesCoreVersionMinor);
  value.setProperty(runtime, "patch", ExpoModulesCoreVersionPatch);
  return value;
}

std::string platformDirectory(
    const std::shared_ptr<RuntimeContext> &context,
    const char *methodName) {
  auto &runtime = context->runtime();
  auto value = context->turboModule()->callPlatformSync(
      runtime, methodName, nullptr, 0);
  if (!value.isString()) {
    throw CodedError(
        "ERR_PLATFORM_ADAPTER",
        std::string(methodName) + " returned a non-string directory URI.");
  }
  auto directory = value.getString(runtime).utf8(runtime);
  if (!directory.empty() && directory.back() != '/') {
    directory.push_back('/');
  }
  return directory;
}

std::string requireStringArgument(
    Invocation &invocation,
    size_t index) {
  const auto &value = invocation.argument(index);
  if (!value.isString()) {
    throw CodedError(
        "ERR_INVALID_ARGUMENT",
        invocation.path() + " argument " + std::to_string(index + 1) + " must be a string.");
  }
  return value.getString(invocation.runtime()).utf8(invocation.runtime());
}

jsi::Value stringValue(Invocation &invocation, const std::string &value) {
  return jsi::String::createFromUtf8(invocation.runtime(), value);
}

}  // namespace

CoreModule::CoreModule(std::shared_ptr<RuntimeContext> context)
    : context_(std::move(context)) {}

ModuleDefinition CoreModule::definition() {
  auto weakContext = context_;
  auto cachedCacheDirectory = std::make_shared<std::optional<std::string>>();
  auto cachedDocumentsDirectory = std::make_shared<std::optional<std::string>>();
  ModuleDefinitionBuilder builder("ExpoModulesCore");
  builder.property({.name = "expoModulesCoreVersion",
                    .getter = versionObject});
  builder.property({.name = "cacheDir",
                    .getter = [weakContext, cachedCacheDirectory](Invocation &invocation) {
                      if (!*cachedCacheDirectory) {
                        *cachedCacheDirectory = platformDirectory(
                            requireContext(weakContext), "getCacheDirectory");
                      }
                      return stringValue(invocation, **cachedCacheDirectory);
                    }});
  builder.property({.name = "documentsDir",
                    .getter = [weakContext, cachedDocumentsDirectory](Invocation &invocation) {
                      if (!*cachedDocumentsDirectory) {
                        *cachedDocumentsDirectory = platformDirectory(
                            requireContext(weakContext), "getDocumentsDirectory");
                      }
                      return stringValue(invocation, **cachedDocumentsDirectory);
                    }});
  builder.function({.name = "uuidv4",
                    .arity = 0,
                    .body = [](Invocation &invocation) {
                      return stringValue(invocation, uuidV4());
                    }});
  builder.function({.name = "uuidv5",
                    .arity = 2,
                    .body = [](Invocation &invocation) {
                      return stringValue(
                          invocation,
                          uuidV5(
                              requireStringArgument(invocation, 0),
                              requireStringArgument(invocation, 1)));
                    }});
  builder.function({.name = "getViewConfig",
                    .arity = 2,
                    .requiredArity = 1,
                    .body = [](Invocation &invocation) -> jsi::Value {
                      auto moduleName = requireStringArgument(invocation, 0);
                      std::optional<std::string> viewName;
                      if (invocation.argumentCount() > 1 && !invocation.argument(1).isUndefined() && !invocation.argument(1).isNull()) {
                        viewName = requireStringArgument(invocation, 1);
                      }
                      const auto *module = invocation.context().moduleRegistry().find(moduleName);
                      if (!module) {
                        return jsi::Value(nullptr);
                      }
                      auto view = std::find_if(
                          module->views.begin(),
                          module->views.end(),
                          [&viewName](const ViewDefinition &candidate) {
                            return viewName ? candidate.name == *viewName : candidate.defaultView;
                          });
                      if (view == module->views.end()) {
                        return jsi::Value(nullptr);
                      }
                      auto &runtime = invocation.runtime();
                      jsi::Object validAttributes(runtime);
                      for (const auto &prop : view->props) {
                        validAttributes.setProperty(runtime, prop.name.c_str(), true);
                      }
                      if (view->usesGenericFabricComponent) {
                        validAttributes.setProperty(runtime, protocol::kViewModuleNameProp, true);
                        validAttributes.setProperty(runtime, protocol::kViewNameProp, true);
                      }
                      jsi::Object directEventTypes(runtime);
                      for (const auto &event : view->events) {
                        auto normalized = event.starts_with("on")
                                            ? "top" + event.substr(2)
                                            : event;
                        jsi::Object registration(runtime);
                        registration.setProperty(
                            runtime,
                            "registrationName",
                            jsi::String::createFromUtf8(runtime, event));
                        directEventTypes.setProperty(
                            runtime, normalized.c_str(), std::move(registration));
                      }
                      jsi::Object result(runtime);
                      if (view->usesGenericFabricComponent) {
                        result.setProperty(
                            runtime,
                            "uiViewClassName",
                            jsi::String::createFromUtf8(
                                runtime, protocol::kViewComponentName));
                      }
                      result.setProperty(runtime, "validAttributes", std::move(validAttributes));
                      result.setProperty(runtime, "directEventTypes", std::move(directEventTypes));
                      return result;
                    }});
  builder.asyncFunction({.name = "reloadAppAsync",
                         .arity = 1,
                         .body = [weakContext](Invocation &invocation) {
                           auto context = requireContext(weakContext);
                           auto reason = requireStringArgument(invocation, 0);
                           auto &runtime = invocation.runtime();
                           jsi::Value argument = jsi::String::createFromUtf8(runtime, reason);
                           return context->turboModule()->callPlatformAsync(
                               runtime, "reloadAppAsync", &argument, 1);
                         }});
  builder.function({.name = "installOnUIRuntime",
                    .arity = 0,
                    .body = [](Invocation &invocation) {
                      WorkletRuntimeInstaller::install(
                          invocation.runtime(), invocation.sharedContext());
                      return jsi::Value::undefined();
                    }});
  return std::move(builder).build();
}

}  // namespace expo::harmony
