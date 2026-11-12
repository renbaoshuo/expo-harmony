/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "ExpoModulesCorePackage.h"

#include <algorithm>
#include <cctype>
#include <exception>
#include <string>

#include <jsi/JSIDynamic.h>

#include <RNOH/ArkJS.h>
#include <RNOH/EventEmitRequestHandler.h>
#include <RNOH/MutationsToNapiConverter.h>
#include <RNOH/RNInstanceInternal.h>

#include <hilog/log.h>

#include "common/fabric/ExpoViewEventEmitter.h"
#include "common/fabric/ExpoViewShadowNode.h"
#include "common/fabric/ExpoViewComponentDescriptor.h"
#include "modules/ExpoModulesCoreTurboModule.h"
#include "runtime/Protocol.h"

namespace expo::harmony {

namespace {


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

// Unlike a TurboModule observer, a package handler exists before JS first uses
// Expo. Route teardown on JS so lazy module creation cannot race installation.
class ExpoLifecycleMessageHandler final : public rnoh::ArkTSMessageHandler {
public:
  void handleArkTSMessage(const Context &context) override {
    if (context.messageName != protocol::kLifecycleEvent || !context.messagePayload.isObject()) {
      return;
    }

    const auto eventName = context.messagePayload.getDefault("eventName", "");
    const auto payload = context.messagePayload.getDefault("payload", nullptr);
    if (!eventName.isString() || (eventName.asString() != protocol::kLifecycleDestroy && eventName.asString() != protocol::kLifecycleContentAppeared) || !payload.isObject()) {
      return;
    }

    const bool appeared = eventName.asString() == protocol::kLifecycleContentAppeared;
    const auto requestId = payload.getDefault("requestId", "");
    if (!requestId.isString() || (!appeared && requestId.asString().empty())) {
      return;
    }

    // The executor is only exposed by RNInstanceInternal.
    auto instance = std::dynamic_pointer_cast<rnoh::RNInstanceInternal>(context.rnInstance.lock());
    if (!instance) {
      return;
    }

    instance->getTaskExecutor()->runTask(
        rnoh::TaskThread::JS,
        [weakInstance = context.rnInstance, appeared, requestId = requestId.asString()] {
          auto instance = weakInstance.lock();
          if (!instance) {
            return;
          }

          auto core = instance->getTurboModule<ExpoModulesCoreTurboModule>("ExpoModulesCore");
          if (core) {
            if (appeared) {
              core->handleContentAppeared(instance->getId());
            } else {
              core->beginDestroy(requestId);
            }
          }
        });
  }
};

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
          protocol::kLogDomain,
          protocol::kLogTag,
          "Rejected Expo view event %{public}s for tag %{public}lld: %{private}s",
          context.eventName.c_str(),
          static_cast<long long>(context.tag),
          diagnostic.c_str());
    } catch (...) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          protocol::kLogDomain,
          protocol::kLogTag,
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
          protocol::kLogDomain,
          protocol::kLogTag,
          "Rejected Expo view state update: %{private}s",
          diagnostic.c_str());
    } catch (...) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          protocol::kLogDomain,
          protocol::kLogTag,
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
  namespace react = facebook::react;
  static const auto flavor = std::make_shared<const std::string>(protocol::kViewComponentName);
  return {react::ComponentDescriptorProvider{
      reinterpret_cast<react::ComponentHandle>(flavor->c_str()),
      react::ComponentName{flavor->c_str()},
      flavor,
      &react::concreteComponentDescriptorConstructor<expo::ExpoViewComponentDescriptor>}};
}

rnoh::ComponentNapiBinderByString
ExpoModulesCorePackage::createComponentNapiBinderByName() {
  return {{protocol::kViewComponentName, std::make_shared<ExpoViewComponentNapiBinder>()}};
}

rnoh::EventEmitRequestHandlers
ExpoModulesCorePackage::createEventEmitRequestHandlers() {
  return {std::make_shared<ExpoViewEventEmitRequestHandler>()};
}

std::vector<rnoh::ArkTSMessageHandler::Shared>
ExpoModulesCorePackage::createArkTSMessageHandlers() {
  return {std::make_shared<ExpoLifecycleMessageHandler>()};
}

}  // namespace expo::harmony
