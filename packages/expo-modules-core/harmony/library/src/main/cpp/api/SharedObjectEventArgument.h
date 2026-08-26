#pragma once

#include <functional>
#include <memory>

#include <jsi/jsi.h>

namespace expo::harmony {

class RuntimeContext;

using SharedObjectEventArgument = std::function<facebook::jsi::Value(
    const std::shared_ptr<RuntimeContext> &)>;

}  // namespace expo::harmony
