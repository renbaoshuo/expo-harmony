#pragma once

#include <memory>
#include <vector>

#include <jsi/jsi.h>

#include <folly/dynamic.h>

#include "modules/internal/ExpoModule.h"

namespace expo::harmony {

class RuntimeContext;

/** Common adapter for every ArkTS-authored Expo Module. */
class ArkTSModuleAdapter final : public ExpoModule {
public:
  static std::vector<std::shared_ptr<ExpoModule>> createModules(
      const std::shared_ptr<RuntimeContext> &context);
  static facebook::jsi::Value decodeValue(
      const std::shared_ptr<RuntimeContext> &context,
      const folly::dynamic &value);
  static std::vector<facebook::jsi::Value> decodeValues(
      const std::shared_ptr<RuntimeContext> &context,
      const folly::dynamic &values);
  static std::vector<facebook::jsi::Value> decodeTypedValues(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &values);
  static void discardValues(
      const std::shared_ptr<RuntimeContext> &context,
      const folly::dynamic &values) noexcept;

  explicit ArkTSModuleAdapter(folly::dynamic descriptor);
  ModuleDefinition definition() override;

private:
  folly::dynamic descriptor_;
};

}  // namespace expo::harmony
