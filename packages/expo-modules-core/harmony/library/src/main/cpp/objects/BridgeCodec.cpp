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
  if (object.hasNativeState<expo::SharedObject::NativeState>(runtime)) {
    return object.getNativeState<expo::SharedObject::NativeState>(runtime)->objectId;
  }
  auto objectIdValue = object.getProperty(runtime, "__expo_shared_object_id__");
  if (!objectIdValue.isNumber()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        className + " method called with an incompatible receiver.");
  }
  const auto objectId = static_cast<long>(objectIdValue.getNumber());
  if (objectId <= 0) {
    throw CodedError(
        "ERR_INVALID_SHARED_OBJECT_ID",
        className + " method called with an unbound shared object.");
  }
  return objectId;
}

}  // namespace expo::harmony
