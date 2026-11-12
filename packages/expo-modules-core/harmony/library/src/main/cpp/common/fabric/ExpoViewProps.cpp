/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Copyright 2022-present 650 Industries. All rights reserved.

#include "ExpoViewProps.h"
#include <react/renderer/core/propsConversions.h>
#include <react/renderer/components/view/ViewProps.h>

namespace react = facebook::react;

namespace expo {

std::unordered_map<std::string, folly::dynamic> propsMapFromProps(const ExpoViewProps &sourceProps, const react::RawProps &rawProps) {
  auto props = sourceProps.propsMap;

  const auto &updates = static_cast<folly::dynamic>(rawProps);
  for (const auto &entry : updates.items()) {
    const auto &name = entry.first.getString();
    props[name] = static_cast<folly::dynamic>(entry.second);
  }

  return props;
}

// RNOH's C++ HostPlatformViewProps has the three-argument ABI.
ExpoViewProps::ExpoViewProps(const react::PropsParserContext &context,
                             const ExpoViewProps &sourceProps,
                             const react::RawProps &rawProps,
                             [[maybe_unused]] const std::function<bool(const std::string &)> &filterObjectKeys)
    : react::ViewProps(context, sourceProps, rawProps),
      propsMap(propsMapFromProps(sourceProps, rawProps)) {}

} // namespace expo
