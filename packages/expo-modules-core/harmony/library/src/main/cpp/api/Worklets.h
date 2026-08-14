#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <worklets/SharedItems/Serializable.h>
#include <worklets/WorkletRuntime/WorkletRuntime.h>

#include "errors/CodedError.h"

namespace expo::harmony {

enum class SerializableValueType : uint8_t {
  Undefined = 1,
  Null = 2,
  Boolean = 3,
  Number = 4,
  BigInt = 5,
  String = 6,
  Object = 7,
  Array = 8,
  Map = 9,
  Set = 10,
  Worklet = 11,
  RemoteFunction = 12,
  Handle = 13,
  HostObject = 14,
  HostFunction = 15,
  ArrayBuffer = 16,
  TurboModuleLike = 17,
  Import = 18,
  Synchronizable = 19,
  Custom = 20,
};

class Serializable {
public:
  explicit Serializable(std::shared_ptr<worklets::Serializable> value);

  SerializableValueType type() const;
  const std::shared_ptr<worklets::Serializable> &value() const noexcept;
  facebook::jsi::Value toJSValue(facebook::jsi::Runtime &runtime) const;

protected:
  std::shared_ptr<worklets::Serializable> value_;
};

class WorkletRuntime;

class Worklet final : public Serializable {
public:
  explicit Worklet(std::shared_ptr<worklets::SerializableWorklet> value);

  void schedule(
      const WorkletRuntime &runtime,
      std::vector<Serializable> arguments = {}) const;
  void execute(
      const WorkletRuntime &runtime,
      std::vector<Serializable> arguments = {}) const;
  const std::shared_ptr<worklets::SerializableWorklet> &worklet() const noexcept;

private:
  std::shared_ptr<worklets::SerializableWorklet> worklet_;
};

class WorkletRuntime final {
public:
  explicit WorkletRuntime(std::weak_ptr<worklets::WorkletRuntime> runtime);
  static WorkletRuntime fromJSRuntime(facebook::jsi::Runtime &runtime);

  bool isAlive() const noexcept;
  uint64_t id() const;
  std::string name() const;
  std::shared_ptr<worklets::WorkletRuntime> requireRuntime() const;

private:
  friend class Worklet;
  std::weak_ptr<worklets::WorkletRuntime> runtime_;
};

}  // namespace expo::harmony
