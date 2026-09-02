#pragma once

#include "modules/internal/ModuleDefinition.h"

namespace expo::harmony {

/** Core-internal owner for one immutable native module definition. */
class ExpoModule {
public:
  virtual ~ExpoModule() = default;
  virtual ModuleDefinition definition() = 0;
};

}  // namespace expo::harmony
