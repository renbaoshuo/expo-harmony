#pragma once

#include <atomic>
#include <exception>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <jsi/jsi.h>

#include <RNOH/TaskExecutor/TaskExecutor.h>

#include <ReactCommon/CallInvoker.h>
#include <folly/dynamic.h>

#include "common/SharedObjectClassIdentity.h"
#include "common/SharedObjectInvocationState.h"
#include "common/SharedObjectObservationState.h"
#include "runtime/RuntimeIdentity.h"
#include "runtime/RuntimeInvocationState.h"
#include "runtime/SerialExecutor.h"

namespace expo::harmony {

class ExpoModulesCoreTurboModule;
class ModuleRegistry;
class NativeSharedObject;

/** Core-internal canonical identity shared by ArkTS and JSI mirrors. */
struct NativeSharedObjectIdentity final {
  long objectId{0};
  std::string runtimeEpoch;
  std::string moduleName;
  std::string className;
  std::string nativeRefType;
  SharedObjectClassLineage classLineage;
};
class Promise;
class RuntimeContext;
struct ViewDefinition;

struct SharedObjectInvocationIdentity final {
  RuntimeEpoch runtimeEpoch{kInvalidRuntimeEpoch};
  long objectId{0};
};

/** Atomically leases every distinct SharedObject referenced by async args. */
class SharedObjectInvocationLeaseBundle final {
public:
  SharedObjectInvocationLeaseBundle(
      SharedObjectInvocationLeaseBundle &&other) noexcept;
  SharedObjectInvocationLeaseBundle &operator=(
      SharedObjectInvocationLeaseBundle &&other) noexcept;
  ~SharedObjectInvocationLeaseBundle() noexcept;

  SharedObjectInvocationLeaseBundle(
      const SharedObjectInvocationLeaseBundle &) = delete;
  SharedObjectInvocationLeaseBundle &operator=(
      const SharedObjectInvocationLeaseBundle &) = delete;

private:
  friend class RuntimeContext;
  using Entry = std::pair<
      SharedObjectInvocationIdentity,
      std::shared_ptr<NativeSharedObject>>;

  SharedObjectInvocationLeaseBundle(
      std::shared_ptr<RuntimeContext> context,
      std::vector<Entry> entries) noexcept;
  void reset() noexcept;

  std::shared_ptr<RuntimeContext> context_;
  std::vector<Entry> entries_;
};

/** Retires one RuntimeContext::dispatch body on every exit path. */
class RuntimeInvocationLease final {
public:
  RuntimeInvocationLease(RuntimeInvocationLease &&other) noexcept;
  ~RuntimeInvocationLease() noexcept;

  RuntimeInvocationLease(const RuntimeInvocationLease &) = delete;
  RuntimeInvocationLease &operator=(const RuntimeInvocationLease &) = delete;
  RuntimeInvocationLease &operator=(RuntimeInvocationLease &&) = delete;

private:
  friend class RuntimeContext;

  explicit RuntimeInvocationLease(
      std::shared_ptr<RuntimeContext> context) noexcept;

  std::shared_ptr<RuntimeContext> context_;
};

class RuntimeContext final : public std::enable_shared_from_this<RuntimeContext> {
public:
  static std::shared_ptr<RuntimeContext> create(
      facebook::jsi::Runtime &runtime,
      std::shared_ptr<facebook::react::CallInvoker> jsInvoker,
      rnoh::TaskExecutor::Shared taskExecutor,
      std::weak_ptr<ExpoModulesCoreTurboModule> turboModule);
  ~RuntimeContext();

  facebook::jsi::Runtime &runtime() const;
  std::shared_ptr<facebook::react::CallInvoker> jsInvoker() const;
  rnoh::TaskExecutor::Shared taskExecutor() const;
  std::shared_ptr<ExpoModulesCoreTurboModule> turboModule() const;
  void attachTurboModule(
      std::weak_ptr<ExpoModulesCoreTurboModule> turboModule);
  bool isAlive() const noexcept;
  bool isAcceptingTasks() const noexcept;
  bool isRuntimeThread() const noexcept;
  RuntimeEpoch runtimeEpoch() const noexcept;
  std::string runtimeEpochString() const;
  void assertRuntimeThread() const;
  void invalidate(std::function<void()> completion = {}) noexcept;
  void dispatchToJavaScript(std::function<void()> task);
  facebook::jsi::Value callPlatformSync(
      std::string methodName,
      std::vector<folly::dynamic> arguments = {});
  facebook::jsi::Value callPlatformSyncTyped(
      std::string methodName,
      std::vector<facebook::jsi::Value> arguments);
  facebook::jsi::Value callPlatformAsync(
      std::string methodName,
      std::vector<folly::dynamic> arguments = {});
  facebook::jsi::Value callPlatformAsyncTyped(
      std::string methodName,
      std::vector<facebook::jsi::Value> arguments);
  void updateViewProps(
      const ViewDefinition &view,
      int64_t tag,
      const std::string &componentName,
      const folly::dynamic &props);
  void mountView(int64_t tag, const std::string &componentName);
  void requireMountedView(
      int64_t tag,
      const std::string &componentName) const;
  std::optional<std::string> mountedViewComponentNameIfPresent(
      int64_t tag) const;
  bool unmountView(
      int64_t tag,
      const std::string &componentName) noexcept;

  void initializeModuleRegistry();
  bool hasModuleRegistry() const noexcept;
  ModuleRegistry &moduleRegistry() const;

  long allocateSharedObjectId();
  long registerNativeSharedObject(std::shared_ptr<NativeSharedObject> object);
  std::shared_ptr<NativeSharedObject> getNativeSharedObject(long objectId) const;
  std::shared_ptr<NativeSharedObject> getNativeSharedObject(
      long objectId,
      const std::string &moduleName,
      const std::string &className) const;
  NativeSharedObjectIdentity nativeSharedObjectIdentity(
      const std::shared_ptr<NativeSharedObject> &object) const;
  NativeSharedObjectIdentity nativeSharedObjectIdentity(long objectId) const;
  SharedObjectInvocationIdentity captureSharedObjectInvocation(
      const std::shared_ptr<NativeSharedObject> &object) const;
  SharedObjectInvocationLeaseBundle acquireSharedObjectInvocations(
      const std::vector<std::shared_ptr<NativeSharedObject>> &objects);
  facebook::jsi::Value materializeNativeSharedObject(
      std::string moduleName,
      std::string className,
      std::shared_ptr<NativeSharedObject> object);
  facebook::jsi::Value bindNativeSharedObject(
      std::string moduleName,
      std::string className,
      std::shared_ptr<NativeSharedObject> object,
      facebook::jsi::Object javaScriptObject);
  void retainSharedObject(
      long objectId,
      const facebook::jsi::Object &object);
  void releaseSharedObject(long objectId);
  void scheduleSharedObjectRelease(long objectId) noexcept;
  facebook::jsi::Value getSharedObject(long objectId);
  size_t beginObservingSharedObject(
      long objectId,
      std::string eventName,
      SharedObjectObservationState::StopHook stopHook);
  bool endObservingSharedObject(
      long objectId,
      const std::string &eventName);
  bool isObservingSharedObject(
      long objectId,
      const std::string &eventName) const noexcept;

  void retainClass(
      std::string moduleName,
      std::string className,
      const facebook::jsi::Function &klass);
  facebook::jsi::Value getClass(
      const std::string &moduleName,
      const std::string &className);

  void retainModule(
      std::string name,
      const facebook::jsi::Object &module);
  facebook::jsi::Value getModule(const std::string &name);
  void clearJSIReferences();
  void retainPromise(const std::shared_ptr<Promise> &promise);
  void releasePromise(const Promise *promise);

private:
  friend class RuntimeInvocationLease;
  friend class SharedObjectInvocationLeaseBundle;

  RuntimeContext(
      facebook::jsi::Runtime &runtime,
      std::shared_ptr<facebook::react::CallInvoker> jsInvoker,
      rnoh::TaskExecutor::Shared taskExecutor,
      std::weak_ptr<ExpoModulesCoreTurboModule> turboModule);
  void scheduleMountedViewTeardown() noexcept;
  void invalidateAfterViewTeardown() noexcept;
  void continueInvalidationAfterExecutorStop() noexcept;
  void continueInvalidationAfterDispatchedInvocations() noexcept;
  void scheduleInvalidationAfterDispatchedInvocations() noexcept;
  void maybeFinishInvalidationAfterSharedObjects() noexcept;
  void finishInvalidation() noexcept;
  bool destroyMountedViews() noexcept;
  void cancelAndRejectPendingPromises() noexcept;
  void releaseAllSharedObjects() noexcept;
  void finalizeSharedObjectRelease(long objectId);
  void releaseSharedObjectInvocations(
      std::vector<SharedObjectInvocationLeaseBundle::Entry> entries) noexcept;
  void scheduleSharedObjectReleaseFinalization(long objectId) noexcept;
  bool beginDispatchedInvocation() noexcept;
  void releaseDispatchedInvocation() noexcept;
  void drainModuleListeners() noexcept;

  const RuntimeEpoch runtimeEpoch_;
  facebook::jsi::Runtime *runtime_;
  std::shared_ptr<facebook::react::CallInvoker> jsInvoker_;
  rnoh::TaskExecutor::Shared taskExecutor_;
  std::weak_ptr<ExpoModulesCoreTurboModule> turboModule_;
  std::atomic_bool alive_{true};
  std::atomic_bool acceptingTasks_{true};
  std::atomic_bool invalidating_{false};
  std::atomic_bool invalidationScheduled_{false};
  std::atomic_long nextObjectId_{1};
  std::thread::id runtimeThread_;
  SerialExecutor modulesExecutor_;
  mutable std::mutex mutex_;
  std::unique_ptr<ModuleRegistry> moduleRegistry_;
  std::unordered_map<long, std::shared_ptr<facebook::jsi::WeakObject>> sharedObjects_;
  std::unordered_map<long, std::shared_ptr<facebook::jsi::Object>>
      deferredSharedObjectEmitters_;
  std::unordered_map<long, std::shared_ptr<NativeSharedObject>> nativeSharedObjects_;
  std::unordered_map<const NativeSharedObject *, long> nativeSharedObjectIds_;
  std::unordered_map<long, std::pair<std::string, std::string>> nativeSharedObjectClasses_;
  SharedObjectInvocationState sharedObjectInvocations_;
  SharedObjectObservationState sharedObjectObservations_;
  RuntimeInvocationState runtimeInvocations_;
  std::unordered_map<std::string, std::unique_ptr<facebook::jsi::Object>> modules_;
  std::unordered_map<std::string, std::unique_ptr<facebook::jsi::Function>> classes_;
  std::unordered_map<const Promise *, std::shared_ptr<Promise>> promises_;
  std::vector<std::function<void()>> invalidationCompletions_;
  std::shared_ptr<RuntimeContext> invalidationLease_;
  bool invalidationViewTeardownCompleted_{false};
  bool invalidationExecutorStopped_{false};
  bool invalidationContinuationScheduled_{false};
  bool invalidationWaitingForSharedObjects_{false};
  bool invalidationFinishing_{false};
  bool sharedObjectReleaseSweepActive_{false};
  std::unordered_map<int64_t, folly::dynamic> viewProps_;
  std::unordered_map<int64_t, std::string> mountedViews_;
};

}  // namespace expo::harmony
