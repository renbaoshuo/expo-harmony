#pragma once

#include <jsi/jsi.h>
#include <string>

namespace expo::harmony {

long requireSharedObjectId(
    facebook::jsi::Runtime &runtime,
    const facebook::jsi::Value &value,
    const std::string &className);

}  // namespace expo::harmony
