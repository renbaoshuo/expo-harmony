#include "CoreModule.h"

#include <algorithm>

#include "api/Promise.h"
#include "api/TypeConverter.h"
#include "api/Version.h"
#include "errors/CodedError.h"
#include "modules/ExpoModulesCoreTurboModule.h"
#include "modules/Uuid.h"
#include "runtime/ModuleRegistry.h"
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
                      return convertToJS(
                          invocation.sharedContext(),
                          **cachedCacheDirectory);
                    }});
  builder.property({.name = "documentsDir",
                    .getter = [weakContext, cachedDocumentsDirectory](Invocation &invocation) {
                      if (!*cachedDocumentsDirectory) {
                        *cachedDocumentsDirectory = platformDirectory(
                            requireContext(weakContext), "getDocumentsDirectory");
                      }
                      return convertToJS(
                          invocation.sharedContext(),
                          **cachedDocumentsDirectory);
                    }});
  builder.function(typedFunction<std::string>("uuidv4", [] { return uuidV4(); }));
  builder.function(typedFunction<std::string, std::string, std::string>(
      "uuidv5",
      [](std::string name, std::string nameSpace) {
        return uuidV5(name, nameSpace);
      }));
  builder.function({.name = "getViewConfig",
                    .arity = 2,
                    .requiredArity = 1,
                    .body = [](Invocation &invocation) -> jsi::Value {
                      ArgumentReader arguments(invocation);
                      auto moduleName = arguments.get<std::string>(0);
                      std::optional<std::string> viewName;
                      if (invocation.argumentCount() > 1 && !invocation.argument(1).isUndefined() && !invocation.argument(1).isNull()) {
                        viewName = arguments.get<std::string>(1);
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
                      result.setProperty(runtime, "validAttributes", std::move(validAttributes));
                      result.setProperty(runtime, "directEventTypes", std::move(directEventTypes));
                      return result;
                    }});
  builder.asyncFunction({.name = "reloadAppAsync",
                         .arity = 1,
                         .body = [weakContext](Invocation &invocation) {
                           auto context = requireContext(weakContext);
                           auto reason = convertFromJS<std::string>(
                               context,
                               invocation.argument(0),
                               invocation.path() + " argument 0");
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

NativeModulesProxyModule::NativeModulesProxyModule(
    std::shared_ptr<RuntimeContext> context)
    : context_(std::move(context)) {}

ModuleDefinition NativeModulesProxyModule::definition() {
  auto weakContext = context_;
  ModuleDefinitionBuilder builder("NativeModulesProxy");
  builder.constant("modulesConstants", [weakContext](Invocation &invocation) {
    auto context = requireContext(weakContext);
    auto &runtime = invocation.runtime();
    jsi::Object result(runtime);
    for (const auto &moduleName : context->moduleRegistry().names()) {
      if (moduleName == "NativeModulesProxy" || moduleName == "ExpoModulesCore") {
        continue;
      }
      const auto *module = context->moduleRegistry().find(moduleName);
      jsi::Object constants(runtime);
      for (const auto &[name, factory] : module->constants) {
        Invocation constantInvocation(
            context,
            moduleName + "." + name,
            runtime,
            jsi::Value::undefined(),
            nullptr,
            0);
        try {
          constants.setProperty(runtime, name.c_str(), factory(constantInvocation));
        } catch (const CodedError &error) {
          throw error.wrapping(
              "ERR_MODULE_CONSTANT",
              "Failed to read module constant '" + moduleName + "." + name + "'.",
              {.moduleName = moduleName, .functionName = name});
        } catch (const std::exception &error) {
          throw CodedError(
              "ERR_MODULE_CONSTANT",
              "Failed to read module constant '" + moduleName + "." + name + "': " + error.what(),
              {.moduleName = moduleName, .functionName = name});
        }
      }
      result.setProperty(runtime, moduleName.c_str(), std::move(constants));
    }
    return result;
  });
  builder.constant("exportedMethods", [weakContext](Invocation &invocation) {
    auto context = requireContext(weakContext);
    auto &runtime = invocation.runtime();
    jsi::Object result(runtime);
    for (const auto &moduleName : context->moduleRegistry().names()) {
      if (moduleName == "NativeModulesProxy" || moduleName == "ExpoModulesCore") {
        continue;
      }
      const auto *module = context->moduleRegistry().find(moduleName);
      jsi::Array methods(runtime, module->functions.size());
      for (size_t index = 0; index < module->functions.size(); ++index) {
        const auto &function = module->functions[index];
        jsi::Object info(runtime);
        info.setProperty(
            runtime,
            "name",
            jsi::String::createFromUtf8(runtime, function.name));
        info.setProperty(runtime, "key", static_cast<double>(index));
        info.setProperty(runtime, "argumentsCount", static_cast<double>(function.arity));
        methods.setValueAtIndex(runtime, index, std::move(info));
      }
      result.setProperty(runtime, moduleName.c_str(), std::move(methods));
    }
    return result;
  });
  builder.asyncFunction({.name = "callMethod",
                         .arity = 3,
                         .body = [weakContext](Invocation &invocation) {
                           auto context = requireContext(weakContext);
                           ArgumentReader arguments(invocation);
                           auto moduleName = arguments.get<std::string>(0);
                           auto methodName = arguments.get<std::string>(1);
                           auto &runtime = invocation.runtime();
                           auto values = arguments.get<std::vector<jsi::Value>>(2);
                           auto moduleValue = context->getModule(moduleName);
                           if (moduleValue.isUndefined()) {
                             auto modules = runtime.global()
                                                .getPropertyAsObject(runtime, "expo")
                                                .getPropertyAsObject(runtime, "modules");
                             moduleValue = modules.getProperty(runtime, moduleName.c_str());
                           }
                           if (!moduleValue.isObject()) {
                             throw CodedError(
                                 "ERR_MODULE_NOT_FOUND", "Cannot find native module '" + moduleName + "'.");
                           }
                           auto moduleObject = moduleValue.getObject(runtime);
                           auto functionValue = moduleObject.getProperty(runtime, methodName.c_str());
                           if (!functionValue.isObject() || !functionValue.getObject(runtime).isFunction(runtime)) {
                             throw CodedError(
                                 "ERR_FUNCTION_NOT_FOUND",
                                 "Cannot find native function '" + moduleName + "." + methodName + "'.");
                           }
                           auto function = functionValue.getObject(runtime).getFunction(runtime);
                           return function.callWithThis(
                               runtime,
                               moduleObject,
                               static_cast<const jsi::Value *>(values.data()),
                               values.size());
                         }});
  return std::move(builder).build();
}

}  // namespace expo::harmony
