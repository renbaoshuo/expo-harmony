#include "ModuleRegistry.h"

#include "api/ExpoModule.h"
#include "api/ExpoModulesProvider.h"
#include "errors/CodedError.h"
#include "modules/CoreModule.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"

#include <functional>
#include <unordered_map>

namespace expo::harmony {

namespace {

void validateClassInheritanceGraph(
    const std::unordered_map<
        std::string,
        std::unique_ptr<ModuleDefinition>>& definitions) {
  std::unordered_map<std::string, std::string> baseByClass;
  std::unordered_map<std::string, const ClassDefinition*> classes;
  for (const auto& [moduleName, module] : definitions) {
    for (const auto& klass : module->classes) {
      classes.emplace(moduleName + "\n" + klass.name, &klass);
    }
  }
  for (const auto& [moduleName, module] : definitions) {
    for (const auto& klass : module->classes) {
      if (klass.baseClassName.empty() ||
          klass.baseClassName == "SharedObject" ||
          klass.baseClassName == "SharedRef") {
        continue;
      }
      auto baseModuleName = moduleName;
      auto baseClassName = klass.baseClassName;
      auto separator = baseClassName.find('.');
      if (separator != std::string::npos) {
        baseModuleName = baseClassName.substr(0, separator);
        baseClassName = baseClassName.substr(separator + 1);
      }
      auto qualifiedClass = moduleName + "\n" + klass.name;
      auto qualifiedBase = baseModuleName + "\n" + baseClassName;
      if (!classes.contains(qualifiedBase)) {
        throw CodedError(
            "ERR_CLASS_NOT_FOUND",
            "Base class '" + baseModuleName + "." + baseClassName +
                "' required by '" + moduleName + "." + klass.name +
                "' is not registered.");
      }
      baseByClass.emplace(std::move(qualifiedClass), std::move(qualifiedBase));
    }
  }

  std::unordered_map<std::string, uint8_t> states;
  std::function<void(const std::string&)> visit = [&](const std::string& name) {
    auto& state = states[name];
    if (state == 2) return;
    if (state == 1) {
      auto separator = name.find('\n');
      throw CodedError(
          "ERR_CLASS_INHERITANCE_CYCLE",
          "Native class inheritance contains a cycle at '" +
              name.substr(0, separator) + "." + name.substr(separator + 1) + "'.");
    }
    state = 1;
    if (auto base = baseByClass.find(name); base != baseByClass.end()) {
      visit(base->second);
    }
    state = 2;
  };
  for (const auto& [name, klass] : classes) {
    (void)klass;
    visit(name);
  }
}

} // namespace

ModuleRegistry::ModuleRegistry(std::shared_ptr<RuntimeContext> context)
    : context_(std::move(context)) {}

ModuleRegistry::~ModuleRegistry() {
  destroy();
}

void ModuleRegistry::initialize() {
  if (initialized_) {
    return;
  }
  auto context = context_.lock();
  if (!context) {
    throw CodedError("ERR_RUNTIME_DESTROYED", "Cannot initialize modules after runtime destruction.");
  }
  registerModule(std::make_shared<CoreModule>(context));
  registerModule(std::make_shared<NativeModulesProxyModule>(context));
  for (const auto& registration :
       ExpoModulesProviderRegistry::shared().createProviders()) {
    try {
      for (auto& module : registration.provider->modules(context)) {
        registerModule(std::move(module));
      }
    } catch (const CodedError& error) {
      throw error.wrapping(
          "ERR_PROVIDER_INITIALIZATION",
          "Expo module provider '" + registration.identifier +
              "' could not initialize.");
    } catch (const std::exception& error) {
      throw CodedError(
          "ERR_PROVIDER_INITIALIZATION",
          "Expo module provider '" + registration.identifier +
              "' could not initialize: " + error.what());
    } catch (...) {
      throw CodedError(
          "ERR_PROVIDER_INITIALIZATION",
          "Expo module provider '" + registration.identifier +
              "' could not initialize because native code threw an unknown exception.");
    }
  }
  validateClassInheritanceGraph(definitions_);
  initialized_ = true;
}

void ModuleRegistry::notifyCreated() {
  if (created_ || destroyed_) return;
  if (!initialized_) {
    throw CodedError(
        "ERR_RUNTIME_NOT_INSTALLED",
        "Cannot create Expo modules before the registry is initialized.");
  }
  auto context = context_.lock();
  if (!context || !context->isAlive()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot create Expo modules after runtime destruction.");
  }
  created_ = true;
  for (const auto& name : names_) {
    const auto* definition = find(name);
    createdNames_.push_back(name);
    if (definition && definition->onCreate) {
      definition->onCreate(*context);
    }
  }
  for (const auto& name : names_) {
    const auto* definition = find(name);
    if (definition && definition->onRegisterActivityContracts) {
      definition->onRegisterActivityContracts(*context);
    }
  }
}

void ModuleRegistry::registerModule(std::shared_ptr<ExpoModule> module) {
  if (!module) {
    throw CodedError("ERR_INVALID_PROVIDER", "Expo module provider returned null.");
  }
  auto definition = module->definition();
  validateModuleDefinition(definition);
  if (definitions_.contains(definition.name)) {
    throw CodedError(
        "ERR_DUPLICATE_MODULE",
        "A module named '" + definition.name + "' was registered twice.");
  }
  auto name = definition.name;
  modules_.push_back(std::move(module));
  names_.push_back(name);
  auto retained = std::make_unique<ModuleDefinition>(std::move(definition));
  if (auto context = context_.lock()) {
    for (const auto& klass : retained->classes) {
      if (klass.nativeType != std::type_index(typeid(void))) {
        context->registerNativeClass(
            klass.nativeType, retained->name, klass.name);
      }
    }
  }
  for (const auto& view : retained->views) {
    if (views_.contains(view.componentName)) {
      throw CodedError(
          "ERR_DUPLICATE_VIEW",
          "Fabric component '" + view.componentName +
              "' is registered by more than one Expo module.");
    }
    views_[view.componentName] = &view;
  }
  definitions_[std::move(name)] = std::move(retained);
}

const ModuleDefinition* ModuleRegistry::find(const std::string& name) const {
  auto iterator = definitions_.find(name);
  return iterator == definitions_.end() ? nullptr : iterator->second.get();
}

const ViewDefinition* ModuleRegistry::findView(
    const std::string& componentName) const {
  auto iterator = views_.find(componentName);
  return iterator == views_.end() ? nullptr : iterator->second;
}

const std::vector<std::string>& ModuleRegistry::names() const noexcept {
  return names_;
}

void ModuleRegistry::dispatchLifecycle(
    const std::string& eventName,
    const folly::dynamic& payload) {
  auto context = context_.lock();
  if (!context || destroyed_) return;
  if (eventName == protocol::kLifecycleDestroy) {
    destroy();
    return;
  }
  for (const auto& name : names_) {
    const auto* definition = find(name);
    if (!definition) continue;
    if (eventName == protocol::kLifecycleForeground && definition->onForeground) {
      definition->onForeground(*context);
    } else if (eventName == protocol::kLifecycleBackground && definition->onBackground) {
      definition->onBackground(*context);
    } else if (eventName == protocol::kLifecycleUserLeaves && definition->onUserLeaves) {
      definition->onUserLeaves(*context);
    } else if (eventName == protocol::kLifecycleActivityDestroy &&
               definition->onActivityDestroy) {
      definition->onActivityDestroy(*context);
    } else if (eventName == protocol::kLifecycleNewIntent && definition->onNewIntent) {
      definition->onNewIntent(*context, payload);
    } else if (eventName == protocol::kLifecycleActivityResult && definition->onActivityResult &&
               payload.isObject()) {
      definition->onActivityResult(
          *context,
          payload.getDefault("requestCode", 0).asInt(),
          payload.getDefault("resultCode", 0).asInt(),
          payload.getDefault("data", nullptr));
    }
  }
}

void ModuleRegistry::destroy() noexcept {
  if (destroyed_) {
    return;
  }
  destroyed_ = true;
  auto context = context_.lock();
  if (context) {
    for (auto iterator = createdNames_.rbegin();
         iterator != createdNames_.rend();
         ++iterator) {
      const auto* definition = find(*iterator);
      if (definition && definition->onDestroy) {
        try {
          definition->onDestroy(*context);
        } catch (...) {
        }
      }
    }
  }
  // Exported HostFunctions keep non-owning pointers into the immutable
  // definitions. Keep both definitions and their owning ExpoModule instances
  // alive until RuntimeContext itself is released. RuntimeContext is marked
  // dead before its retained JSI objects are cleared, so post-destroy calls
  // fail deterministically without dereferencing freed native bodies.
}

} // namespace expo::harmony
