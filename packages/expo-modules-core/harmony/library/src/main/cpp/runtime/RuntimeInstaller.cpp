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

  std::shared_ptr<RuntimeContext> context() const {
    return context_;
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

void defineCoreAlias(
    jsi::Runtime &runtime,
    jsi::Object &expoObject,
    const char *name) {
  expo::common::defineProperty(
      runtime,
      &expoObject,
      name,
      {
          .configurable = false,
          .enumerable = true,
          .get = [property = std::string(name)](jsi::Runtime &rt, jsi::Object) {
            auto expo = rt.global().getPropertyAsObject(rt, "expo");
            auto modules = expo.getPropertyAsObject(rt, "modules");
            auto core = modules.getPropertyAsObject(rt, "ExpoModulesCore");
            return core.getProperty(rt, property.c_str());
          },
      });
}

}  // namespace

std::shared_ptr<RuntimeContext> RuntimeInstaller::installedContext(
    jsi::Runtime &runtime) {
  auto existing = runtime.global().getProperty(runtime, "expo");
  if (!existing.isObject()) {
    return nullptr;
  }

  auto expoObject = existing.getObject(runtime);
  auto marker = expoObject.getProperty(runtime, "__expo_harmony_runtime_context__");
  if (!marker.isBool() || !marker.getBool() || !expoObject.hasNativeState<RuntimeContextNativeState>(runtime)) {
    return nullptr;
  }

  auto nativeState = expoObject.getNativeState<RuntimeContextNativeState>(runtime);
  auto context = nativeState ? nativeState->context() : nullptr;

  return context && context->isAlive() && context->isAcceptingTasks()
           ? context
           : nullptr;
}

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
  const auto rollback = [&] {
    context->invalidate();
    global.setProperty(runtime, "expo", jsi::Value::undefined());
  };

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
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            "The native ExpoModulesCore definition was not registered.");
      }

      auto core = coreValue.getObject(runtime);
      defineReadOnly(
          runtime,
          expoObject,
          "expoModulesCoreVersion",
          core.getProperty(runtime, "expoModulesCoreVersion"));
      defineCoreAlias(runtime, expoObject, "cacheDir");
      defineCoreAlias(runtime, expoObject, "documentsDir");

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
    expo::common::defineProperty(runtime, &global, "expo", {.configurable = false, .enumerable = true, .writable = false, .value = jsi::Value(runtime, expoObject)});

    return true;
  } catch (const CodedError &error) {
    rollback();
    throw CodedError(error);
  } catch (const jsi::JSError &error) {
    rollback();
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    rollback();
    throw std::runtime_error(error.what());
  } catch (...) {
    rollback();
    throw CodedError(
        "ERR_RUNTIME_INSTALLATION",
        "Expo Modules could not install the native runtime because native code threw an unknown exception.");
  }
}

}  // namespace expo::harmony
