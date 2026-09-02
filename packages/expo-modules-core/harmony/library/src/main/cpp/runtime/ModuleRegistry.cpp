#include "ModuleRegistry.h"

#include <algorithm>
#include <functional>
#include <unordered_map>
#include <unordered_set>

#include "errors/CodedError.h"
#include "fabric/ExpoViewComponentRegistry.h"
#include "modules/ArkTSModuleAdapter.h"
#include "modules/CoreModule.h"
#include "modules/internal/ExpoModule.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"

namespace expo::harmony {

namespace {

std::vector<std::string> viewComponentNames(
    const ModuleDefinition &module,
    const ViewDefinition &view) {
  std::vector<std::string> names{view.componentName};
  if (view.defaultView) {
    auto defaultName = "ViewManagerAdapter_" + module.name;
    if (defaultName != view.componentName) {
      names.push_back(std::move(defaultName));
    }
  }
  return names;
}

void validateClassInheritanceGraph(
    const std::unordered_map<
        std::string,
        std::unique_ptr<ModuleDefinition>> &definitions) {
  std::unordered_map<std::string, std::string> baseByClass;
  std::unordered_map<std::string, const ClassDefinition *> classes;
  for (const auto &[moduleName, module] : definitions) {
    for (const auto &klass : module->classes) {
      classes.emplace(moduleName + "\n" + klass.name, &klass);
    }
  }
  for (const auto &[moduleName, module] : definitions) {
    for (const auto &klass : module->classes) {
      if (klass.baseClassName.empty() || klass.baseClassName == "SharedObject" || klass.baseClassName == "SharedRef") {
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
            "Base class '" + baseModuleName + "." + baseClassName + "' required by '" + moduleName + "." + klass.name + "' is not registered.");
      }
      baseByClass.emplace(std::move(qualifiedClass), std::move(qualifiedBase));
    }
  }

  std::unordered_map<std::string, uint8_t> states;
  std::function<void(const std::string &)> visit = [&](const std::string &name) {
    auto &state = states[name];
    if (state == 2) {
      return;
    }
    if (state == 1) {
      auto separator = name.find('\n');
      throw CodedError(
          "ERR_CLASS_INHERITANCE_CYCLE",
          "Native class inheritance contains a cycle at '" + name.substr(0, separator) + "." + name.substr(separator + 1) + "'.");
    }
    state = 1;
    if (auto base = baseByClass.find(name); base != baseByClass.end()) {
      visit(base->second);
    }
    state = 2;
  };
  for (const auto &[name, klass] : classes) {
    (void)klass;
    visit(name);
  }
}

}  // namespace

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
  // ArkTS modules share one generic native adapter.
  for (auto &module : ArkTSModuleAdapter::createModules(context)) {
    registerModule(std::move(module));
  }
  validateClassInheritanceGraph(definitions_);
  initialized_ = true;
}

void ModuleRegistry::registerModule(std::shared_ptr<ExpoModule> module) {
  if (!module) {
    throw CodedError("ERR_INVALID_DEFINITION", "Expo module factory returned null.");
  }
  auto context = context_.lock();
  if (!context || !context->isAlive()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot register an Expo module after runtime destruction.");
  }
  auto definition = module->definition();
  validateModuleDefinition(definition);
  auto name = definition.name;
  auto retained = std::make_unique<ModuleDefinition>(std::move(definition));
  const auto *previous = find(name);
  auto position = names_.end();
  if (previous) {
    position = std::find(names_.begin(), names_.end(), name);
    if (position == names_.end()) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          "Expo module registry lost the ordering entry for '" + name + "'.");
    }
  }

  // Validate replacement view ownership before mutating registry state.
  std::unordered_map<std::string, bool> replacementViews;
  if (previous) {
    for (const auto &view : previous->views) {
      for (const auto &componentName : viewComponentNames(*previous, view)) {
        replacementViews.emplace(componentName, true);
      }
    }
  }
  std::unordered_map<std::string, bool> newViews;
  for (const auto &view : retained->views) {
    const auto &nativeComponentName = view.usesGenericFabricComponent
                                        ? protocol::kViewComponentName
                                        : view.componentName;
    if (!ExpoViewComponentRegistry::contains(nativeComponentName)) {
      throw CodedError(
          "ERR_VIEW_NOT_REGISTERED",
          "Fabric component '" + nativeComponentName + "' required by Expo module '" + retained->name + "' was not registered before React initialized its component registry.");
    }
    for (const auto &componentName : viewComponentNames(*retained, view)) {
      if (!newViews.emplace(componentName, true).second) {
        throw CodedError(
            "ERR_DUPLICATE_VIEW",
            "Fabric component '" + componentName + "' is defined twice by Expo module '" + retained->name + "'.");
      }
      if (views_.contains(componentName) && !replacementViews.contains(componentName)) {
        throw CodedError(
            "ERR_DUPLICATE_VIEW",
            "Fabric component '" + componentName + "' is registered by more than one Expo module.");
      }
    }
  }

  if (previous) {
    for (const auto &view : previous->views) {
      for (const auto &componentName : viewComponentNames(*previous, view)) {
        views_.erase(componentName);
      }
    }
  }
  for (const auto &view : retained->views) {
    for (const auto &componentName : viewComponentNames(*retained, view)) {
      views_[componentName] = &view;
    }
  }
  if (previous) {
    modules_[static_cast<size_t>(std::distance(names_.begin(), position))] = std::move(module);
  } else {
    modules_.push_back(std::move(module));
    names_.push_back(name);
  }
  // Preserve the original ordering slot when replacing a module.
  definitions_[name] = std::move(retained);
}

const ModuleDefinition *ModuleRegistry::find(const std::string &name) const {
  auto iterator = definitions_.find(name);
  return iterator == definitions_.end() ? nullptr : iterator->second.get();
}

const ViewDefinition *ModuleRegistry::findView(
    const std::string &componentName) const {
  auto iterator = views_.find(componentName);
  return iterator == views_.end() ? nullptr : iterator->second;
}

bool ModuleRegistry::isSharedRefClass(
    const std::string &moduleName,
    const std::string &className) const {
  auto currentModule = moduleName;
  auto currentClass = className;
  std::unordered_set<std::string> visited;
  while (visited.emplace(currentModule + "\n" + currentClass).second) {
    const auto *module = find(currentModule);
    if (!module) {
      return false;
    }
    const auto definition = std::find_if(
        module->classes.begin(),
        module->classes.end(),
        [&](const ClassDefinition &candidate) {
          return candidate.name == currentClass;
        });
    if (definition == module->classes.end()) {
      return false;
    }
    if (definition->baseClassName == "SharedRef") {
      return true;
    }
    if (definition->baseClassName.empty() || definition->baseClassName == "SharedObject") {
      return false;
    }
    const auto separator = definition->baseClassName.find('.');
    if (separator == std::string::npos) {
      currentClass = definition->baseClassName;
    } else {
      currentModule = definition->baseClassName.substr(0, separator);
      currentClass = definition->baseClassName.substr(separator + 1);
    }
  }
  return false;
}

SharedObjectClassLineage ModuleRegistry::sharedObjectClassLineage(
    const std::string &moduleName,
    const std::string &className) const {
  SharedObjectClassLineage result;
  auto currentModule = moduleName;
  auto currentClass = className;
  std::unordered_set<std::string> visited;
  while (visited.emplace(currentModule + "\n" + currentClass).second) {
    result.push_back({currentModule, currentClass});
    const auto *module = find(currentModule);
    if (!module) {
      break;
    }
    const auto definition = std::find_if(
        module->classes.begin(),
        module->classes.end(),
        [&](const ClassDefinition &candidate) {
          return candidate.name == currentClass;
        });
    if (definition == module->classes.end() || definition->baseClassName.empty() || definition->baseClassName == "SharedObject" || definition->baseClassName == "SharedRef") {
      break;
    }
    const auto separator = definition->baseClassName.find('.');
    if (separator == std::string::npos) {
      currentClass = definition->baseClassName;
    } else {
      currentModule = definition->baseClassName.substr(0, separator);
      currentClass = definition->baseClassName.substr(separator + 1);
    }
  }
  return result;
}

const std::vector<std::string> &ModuleRegistry::names() const noexcept {
  return names_;
}

void ModuleRegistry::destroy() noexcept {
  if (destroyed_) {
    return;
  }
  destroyed_ = true;
  // Keep definitions alive until RuntimeContext releases exported HostFunctions.
}

}  // namespace expo::harmony
