/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Copyright 2022-present 650 Industries. All rights reserved.

#include "ExpoViewComponentDescriptor.h"
#include <react/renderer/core/ShadowNode.h>

namespace expo {

ExpoViewComponentDescriptor::ExpoViewComponentDescriptor(facebook::react::ComponentDescriptorParameters const &parameters)
  : facebook::react::ConcreteComponentDescriptor<ExpoViewShadowNode>(parameters) {
}

facebook::react::ComponentHandle ExpoViewComponentDescriptor::getComponentHandle() const {
  return reinterpret_cast<facebook::react::ComponentHandle>(getComponentName());
}

facebook::react::ComponentName ExpoViewComponentDescriptor::getComponentName() const {
  return std::static_pointer_cast<std::string const>(this->flavor_)->c_str();
}

void ExpoViewComponentDescriptor::adopt(facebook::react::ShadowNode &shadowNode) const {
  react_native_assert(dynamic_cast<ExpoViewShadowNode *>(&shadowNode));

  const auto node = dynamic_cast<ExpoViewShadowNode *>(&shadowNode);
  node->applySizeState(node->getStateData());
  ConcreteComponentDescriptor::adopt(shadowNode);
}

} // namespace expo
