#pragma once

#include <string>

#include <jsi/jsi.h>

namespace expo::harmony {

long requireSharedObjectId(
    facebook::jsi::Runtime &runtime,
    const facebook::jsi::Value &value,
    const std::string &className);

}  // namespace expo::harmony
