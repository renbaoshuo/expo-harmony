#include "BridgeCodec.h"

#include <common/SharedObject.h>

#include "errors/CodedError.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

long requireSharedObjectId(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    const std::string &className) {
  if (!value.isObject()) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", className + " method called with a non-object receiver.");
  }
  auto object = value.getObject(runtime);
  if (!object.hasNativeState<expo::SharedObject::NativeState>(runtime)) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", className + " method called with an incompatible receiver.");
  }
  return object.getNativeState<expo::SharedObject::NativeState>(runtime)->objectId;
}

}  // namespace expo::harmony
