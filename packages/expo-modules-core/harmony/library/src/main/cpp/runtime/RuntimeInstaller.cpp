#include "RuntimeInstaller.h"

#include <common/EventEmitter.h>
#include <common/JSI/JSIUtils.h>
#include <common/NativeModule.h>
#include <common/SharedObject.h>
#include <common/SharedRef.h>

#include "errors/CodedError.h"
#include "modules/ModulesHostObject.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/RuntimeContext.h"
#include "worklets/WorkletRuntimeInstaller.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

class RuntimeContextNativeState final : public jsi::NativeState {
public:
  explicit RuntimeContextNativeState(std::shared_ptr<RuntimeContext> context)
      : context_(std::move(context)) {}

  ~RuntimeContextNativeState() override {
    context_->invalidate();
  }

private:
  std::shared_ptr<RuntimeContext> context_;
};

void defineReadOnly(
    jsi::Runtime &runtime,
    jsi::Object &object,
    const char *name,
    jsi::Value value,
    bool enumerable = true) {
  expo::common::defineProperty(runtime, &object, name, {.configurable = false, .enumerable = enumerable, .writable = false, .value = std::move(value)});
}

}  // namespace

bool RuntimeInstaller::install(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    bool workletRuntime) {
  auto existing = runtime.global().getProperty(runtime, "expo");
  if (existing.isObject()) {
    auto existingObject = existing.getObject(runtime);
    auto marker = existingObject.getProperty(runtime, "__expo_harmony_runtime_context__");
    if (marker.isBool() && marker.getBool()) {
      return false;
    }
  }

  jsi::Object expoObject(runtime);
  expo::common::defineProperty(
      runtime,
      &expoObject,
      "__expo_harmony_runtime_context__",
      {
          .configurable = true,
          .enumerable = false,
          .writable = true,
          .value = false,
      });

  auto global = runtime.global();
  expo::common::defineProperty(runtime, &global, "expo", {.configurable = true, .enumerable = true, .writable = true, .value = jsi::Value(runtime, expoObject)});
  try {
    expo::EventEmitter::installClass(runtime);
    expo::NativeModule::installClass(runtime);
    expo::SharedObject::installBaseClass(
        runtime,
        [weakContext = std::weak_ptr<RuntimeContext>(context)](long objectId) {
          if (auto locked = weakContext.lock()) {
            locked->scheduleSharedObjectRelease(objectId);
          }
        });
    expo::SharedRef::installBaseClass(runtime);

    expoObject = runtime.global().getPropertyAsObject(runtime, "expo");
    expoObject.setNativeState(
        runtime, std::make_shared<RuntimeContextNativeState>(context));
    if (!workletRuntime) {
      context->initializeModuleRegistry();
      auto modulesHost = std::make_shared<ModulesHostObject>(context);
      expoObject.setProperty(
          runtime,
          "modules",
          jsi::Object::createFromHostObject(runtime, std::move(modulesHost)));

      auto coreValue = expoObject.getPropertyAsObject(runtime, "modules")
                           .getProperty(runtime, "ExpoModulesCore");
      if (!coreValue.isObject()) {
        throw makeJSError(
            runtime,
            "ERR_INVALID_PROVIDER",
            "The native ExpoModulesCore definition was not registered.");
      }
      auto core = coreValue.getObject(runtime);
      for (const char *constant : {
               "expoModulesCoreVersion", "cacheDir", "documentsDir"}) {
        defineReadOnly(
            runtime,
            expoObject,
            constant,
            core.getProperty(runtime, constant));
      }

      for (const char *function : {
               "uuidv4", "uuidv5", "getViewConfig", "reloadAppAsync", "installOnUIRuntime"}) {
        expoObject.setProperty(runtime, function, core.getProperty(runtime, function));
      }
    }

    defineReadOnly(
        runtime,
        expoObject,
        "__expo_harmony_runtime_context__",
        true,
        false);
    if (!workletRuntime) {
      context->moduleRegistry().notifyCreated();
    }
    expo::common::defineProperty(runtime, &global, "expo", {.configurable = false, .enumerable = true, .writable = false, .value = jsi::Value(runtime, expoObject)});
    return true;
  } catch (...) {
    context->invalidate();
    global.setProperty(runtime, "expo", jsi::Value::undefined());
    throw;
  }
}

}  // namespace expo::harmony
