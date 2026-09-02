// Copyright 2022-present 650 Industries. All rights reserved.

#pragma once

#ifdef __cplusplus

#include <cmath>
#include <limits>

#include <folly/dynamic.h>
#ifdef ANDROID
#include <react/renderer/mapbuffer/MapBuffer.h>
#include <react/renderer/mapbuffer/MapBufferBuilder.h>
#endif

namespace expo {

class ExpoViewState final {
public:
  ExpoViewState() {}

  ExpoViewState(float width, float height) {
    if (width >= 0) {
      _width = width;
    } else {
      _width = std::numeric_limits<float>::quiet_NaN();
    }
    if (height >= 0) {
      _height = height;
    } else {
      _height = std::numeric_limits<float>::quiet_NaN();
    }
  };

  static ExpoViewState withStyleDimensions(float styleWidth, float styleHeight) {
    ExpoViewState state;
    if (styleWidth >= 0) {
      state._styleWidth = styleWidth;
    } else {
      state._styleWidth = std::numeric_limits<float>::quiet_NaN();
    }
    if (styleHeight >= 0) {
      state._styleHeight = styleHeight;
    } else {
      state._styleHeight = std::numeric_limits<float>::quiet_NaN();
    }
    return state;
  }

  ExpoViewState(ExpoViewState const &previousState, folly::dynamic data)
  : _width(decodeDimension(data, "width")),
    _height(decodeDimension(data, "height")),
    _styleWidth(decodeDimension(data, "styleWidth")),
    _styleHeight(decodeDimension(data, "styleHeight")) {
  }

  static inline bool isNonnullProperty(const folly::dynamic &value, const std::string &name) {
    return value.isObject() && value.count(name) && !value[name].isNull();
  }

  static inline float decodeDimension(
      const folly::dynamic &value,
      const std::string &name) noexcept {
    if (!isNonnullProperty(value, name) || !value[name].isNumber()) {
      return std::numeric_limits<float>::quiet_NaN();
    }

    const auto dimension = value[name].asDouble();
    if (!std::isfinite(dimension) || dimension < 0 ||
        dimension > std::numeric_limits<float>::max()) {
      return std::numeric_limits<float>::quiet_NaN();
    }

    return static_cast<float>(dimension);
  }

#ifdef ANDROID
  folly::dynamic getDynamic() const {
    return {};
  };

  facebook::react::MapBuffer getMapBuffer() const {
    return facebook::react::MapBufferBuilder::EMPTY();
  };

#endif

  float _width = std::numeric_limits<float>::quiet_NaN();
  float _height = std::numeric_limits<float>::quiet_NaN();
  float _styleWidth = std::numeric_limits<float>::quiet_NaN();
  float _styleHeight = std::numeric_limits<float>::quiet_NaN();

};

} // namespace expo

#endif // __cplusplus
