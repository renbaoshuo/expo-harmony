/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Copyright 2022-present 650 Industries. All rights reserved.

#include "ExpoViewShadowNode.h"

#include <cmath>

namespace react = facebook::react;

namespace expo {

extern const char ExpoViewComponentName[] = "ExpoFabricView";

ExpoViewShadowNode::ExpoViewShadowNode(
    const react::ShadowNodeFragment &fragment,
    const react::ShadowNodeFamily::Shared &family,
    react::ShadowNodeTraits traits)
    : ConcreteViewShadowNode(fragment, family, traits) {
  initialize();
}

ExpoViewShadowNode::ExpoViewShadowNode(
    const react::ShadowNode &sourceShadowNode,
    const react::ShadowNodeFragment &fragment)
    : ConcreteViewShadowNode(sourceShadowNode, fragment) {
  initialize();
}

void ExpoViewShadowNode::applySizeState(const ExpoViewState &state) const {
  ensureUnsealed();

  // A state-only clone shares its props and inherits the previous Yoga node's
  // style. Start each dimension from props so clearing state restores its unit.
  const auto &propsStyle = static_cast<const ExpoViewProps &>(*props_).yogaStyle;
  auto style = yogaNode_.style();

  const auto applyDimension = [&](facebook::yoga::Dimension dimension, react::Float styleSize, react::Float nativeSize) {
    auto value = propsStyle.dimension(dimension);
    if (std::isfinite(styleSize)) {
      value = facebook::yoga::StyleSizeLength::points(styleSize);
    } else if ((value.isAuto() || value.isUndefined()) && std::isfinite(nativeSize)) {
      value = facebook::yoga::StyleSizeLength::points(nativeSize);
    }
    style.setDimension(dimension, value);
  };
  applyDimension(facebook::yoga::Dimension::Width, state._styleWidth, state._width);
  applyDimension(facebook::yoga::Dimension::Height, state._styleHeight, state._height);

  if (style != yogaNode_.style()) {
    yogaNode_.setStyle(style);
    yogaNode_.setDirty(true);
  }
}

void ExpoViewShadowNode::initialize() noexcept {
  const auto &props = static_cast<const ExpoViewProps &>(*props_);
  const auto root = props.propsMap.find("layoutRoot");
  if (root != props.propsMap.end() && root->second.isBool() && root->second.getBool()) {
    traits_.set(react::ShadowNodeTraits::Trait::RootNodeKind);
  } else {
    traits_.unset(react::ShadowNodeTraits::Trait::RootNodeKind);
  }

  if (props.collapsableChildren) {
    traits_.set(react::ShadowNodeTraits::Trait::ChildrenFormStackingContext);
  } else {
    traits_.unset(react::ShadowNodeTraits::Trait::ChildrenFormStackingContext);
  }

  if (YGNodeStyleGetDisplay(&yogaNode_) == YGDisplayContents) {
    const auto flag = props.propsMap.find("disableForceFlatten");
    const bool disableForceFlatten = flag != props.propsMap.end() && flag->second.isBool() && flag->second.getBool();

    if (disableForceFlatten) {
      traits_.unset(react::ShadowNodeTraits::Trait::ForceFlattenView);
    }
  }
}

} // namespace expo
