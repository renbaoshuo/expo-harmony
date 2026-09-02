#include "ExpoModulesCorePackage.h"

#include <algorithm>
#include <cctype>
#include <exception>
#include <string>

#include <jsi/JSIDynamic.h>

#include <RNOH/ArkJS.h>
#include <RNOH/EventEmitRequestHandler.h>
#include <RNOH/MutationsToNapiConverter.h>

#include <hilog/log.h>

#include "common/fabric/ExpoViewEventEmitter.h"
#include "common/fabric/ExpoViewShadowNode.h"
#include "fabric/ExpoViewComponentRegistry.h"
#include "modules/ExpoModulesCoreTurboModule.h"

namespace expo::harmony {

namespace {

constexpr unsigned int kExpoModulesLogDomain = 0xD003900;
constexpr const char *kExpoModulesLogTag = "ExpoModulesCore";

std::string limitedDiagnostic(const char *message) {
  std::string result = message == nullptr ? "native error" : message;
  if (result.size() > 256) {
    result.resize(256);
  }
  std::replace_if(
      result.begin(),
      result.end(),
      [](unsigned char character) { return character < 0x20U; },
      ' ');
  return result;
}

std::string normalizeEventName(std::string name) {
  size_t prefixLength = 0;
  if (name.starts_with("on") && name.size() > 2) {
    prefixLength = 2;
  } else if (name.starts_with("top") && name.size() > 3) {
    prefixLength = 3;
  }
  if (prefixLength == 0) {
    return name;
  }
  name.erase(0, prefixLength);
  name[0] = static_cast<char>(
      std::tolower(static_cast<unsigned char>(name[0])));
  return name;
}

class ExpoViewEventEmitRequestHandler final
    : public rnoh::EventEmitRequestHandler {
public:
  void handleEvent(const Context &context) override {
    if (!context.shadowViewRegistry) {
      return;
    }
    auto eventEmitter = context.shadowViewRegistry
                            ->getEventEmitter<expo::ExpoViewEventEmitter>(context.tag);
    if (!eventEmitter) {
      return;
    }
    try {
      auto payload = ArkJS(context.env).getDynamic(context.payload);
      eventEmitter->dispatch(
          normalizeEventName(context.eventName),
          [payload = std::move(payload)](facebook::jsi::Runtime &runtime) {
            return facebook::jsi::valueFromDynamic(runtime, payload);
          });
    } catch (const std::exception &error) {
      const auto diagnostic = limitedDiagnostic(error.what());
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Rejected Expo view event %{public}s for tag %{public}lld: %{private}s",
          context.eventName.c_str(),
          static_cast<long long>(context.tag),
          diagnostic.c_str());
    } catch (...) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Rejected Expo view event %{public}s for tag %{public}lld: unknown native exception",
          context.eventName.c_str(),
          static_cast<long long>(context.tag));
    }
  }
};

class ExpoViewComponentNapiBinder final : public rnoh::ComponentNapiBinder {
public:
  void updateState(const StateUpdateContext &context) override {
    auto state = std::dynamic_pointer_cast<
        const expo::ExpoViewShadowNode::ConcreteState>(context.state);
    if (!state) {
      return;
    }
    try {
      auto dynamicState = ArkJS(context.env).getDynamic(context.newState);
      if (!dynamicState.isObject()) {
        return;
      }
      state->updateState(expo::ExpoViewState(state->getData(), std::move(dynamicState)));
    } catch (const std::exception &error) {
      const auto diagnostic = limitedDiagnostic(error.what());
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Rejected Expo view state update: %{private}s",
          diagnostic.c_str());
    } catch (...) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Rejected Expo view state update: unknown native exception");
    }
  }
};

}  // namespace

rnoh::TurboModuleFactoryDelegate::SharedTurboModule
ExpoModulesCoreTurboModuleFactoryDelegate::createTurboModule(
    Context context,
    const std::string &name) const {
  if (name == "ExpoModulesCore") {
    return std::make_shared<ExpoModulesCoreTurboModule>(std::move(context), name);
  }
  return nullptr;
}

std::unique_ptr<rnoh::TurboModuleFactoryDelegate>
ExpoModulesCorePackage::createTurboModuleFactoryDelegate() {
  return std::make_unique<ExpoModulesCoreTurboModuleFactoryDelegate>();
}

std::vector<facebook::react::ComponentDescriptorProvider>
ExpoModulesCorePackage::createComponentDescriptorProviders() {
  return ExpoViewComponentRegistry::descriptorProviders();
}

rnoh::ComponentNapiBinderByString
ExpoModulesCorePackage::createComponentNapiBinderByName() {
  rnoh::ComponentNapiBinderByString result;
  for (const auto &componentName :
       ExpoViewComponentRegistry::componentNames()) {
    result.emplace(
        componentName, std::make_shared<ExpoViewComponentNapiBinder>());
  }
  return result;
}

rnoh::ComponentInstance::Shared ExpoModulesCorePackage::createComponentInstance(
    const rnoh::ComponentInstance::Context &context) {
  if (!ExpoViewComponentRegistry::contains(context.componentName)) {
    return nullptr;
  }
  // Let RNOH create the fallback instance for ArkTS-wrapped builders.
  return nullptr;
}

rnoh::EventEmitRequestHandlers
ExpoModulesCorePackage::createEventEmitRequestHandlers() {
  return {std::make_shared<ExpoViewEventEmitRequestHandler>()};
}

}  // namespace expo::harmony
