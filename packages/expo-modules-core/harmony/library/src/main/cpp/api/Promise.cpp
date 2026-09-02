#include "Promise.h"

#include "errors/CodedError.h"
#include "modules/internal/ModuleDefinition.h"
#include "runtime/RuntimeContext.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

void CancellationToken::throwIfCancellationRequested() const {
  if (isCancellationRequested()) {
    throw CodedError("ERR_CANCELLED", "The native asynchronous operation was cancelled.");
  }
}

Promise::Promise(
    std::shared_ptr<RuntimeContext> context,
    jsi::Function resolve,
    jsi::Function reject)
    : context_(context),
      resolve_(std::make_unique<jsi::Function>(std::move(resolve))),
      reject_(std::make_unique<jsi::Function>(std::move(reject))),
      cancellationToken_(std::make_shared<CancellationToken>()) {}

jsi::Value Promise::create(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    Setup setup) {
  auto constructor = runtime.global().getPropertyAsFunction(runtime, "Promise");
  auto executorName = jsi::PropNameID::forAscii(runtime, "expoPromiseExecutor");
  auto executor = jsi::Function::createFromHostFunction(
      runtime,
      executorName,
      2,
      [context, setup = std::move(setup)](
          jsi::Runtime &rt,
          const jsi::Value &,
          const jsi::Value *arguments,
          size_t count) {
        if (count != 2 || !arguments[0].isObject() || !arguments[1].isObject()) {
          throw CodedJSError(
              rt, "ERR_PROMISE_SETUP", "JavaScript Promise supplied invalid callbacks.");
        }

        auto promise = std::shared_ptr<Promise>(new Promise(
            context,
            arguments[0].getObject(rt).getFunction(rt),
            arguments[1].getObject(rt).getFunction(rt)));
        context->retainPromise(promise);

        try {
          setup(promise);
        } catch (const CodedError &error) {
          promise->reject(error);
        } catch (const std::exception &error) {
          promise->reject("ERR_UNEXPECTED", error.what());
        } catch (...) {
          promise->reject(
              "ERR_UNEXPECTED",
              "The native Promise setup threw a non-standard exception.");
        }
        return jsi::Value::undefined();
      });
  return constructor.callAsConstructor(runtime, executor);
}

jsi::Value Promise::rejected(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    std::string code,
    std::string message) {
  return create(
      runtime,
      context,
      [code = std::move(code), message = std::move(message)](
          const std::shared_ptr<Promise> &promise) {
        promise->reject(code, message);
      });
}

bool Promise::settle(SettlementBody body) {
  if (!settlementState_.trySettle()) {
    // Repeated settlement is a no-op.
    return false;
  }

  auto retainedResources = takeRetainedResources();
  auto context = context_.lock();
  if (!context || !context->isAlive()) {
    return true;
  }

  auto task = [self = shared_from_this(),
               body = std::move(body),
               retainedResources = std::move(retainedResources)]() mutable {
    // Keep invocation leases alive through JS settlement.
    (void)retainedResources;

    auto context = self->context_.lock();
    // Invalidation may detach this queued callback; do not touch cleared handles.
    if (!context || !context->isAlive() || !context->isAcceptingTasks() || !self->resolve_ || !self->reject_) {
      return;
    }

    auto resolve = std::move(self->resolve_);
    auto reject = std::move(self->reject_);
    context->releasePromise(self.get());

    // The invocation lease keeps teardown from racing conversion or callbacks.
    body(context->runtime(), *resolve, *reject);
  };

  try {
    context->dispatchToJavaScript(std::move(task));
  } catch (...) {
    // Dispatch may fail during invalidation.
  }

  return true;
}

void Promise::resolve(ValueFactory valueFactory) {
  (void)tryResolve(std::move(valueFactory));
}

bool Promise::tryResolve(ValueFactory valueFactory) {
  return settle([valueFactory = std::move(valueFactory)](
                    jsi::Runtime &runtime,
                    jsi::Function &resolve,
                    jsi::Function &reject) mutable {
    try {
      resolve.call(runtime, valueFactory(runtime));
    } catch (const CodedError &error) {
      reject.call(runtime, CodedJSError(runtime, error).value());
    } catch (const jsi::JSError &error) {
      reject.call(runtime, error.value());
    } catch (const std::exception &error) {
      reject.call(
          runtime,
          CodedJSError(runtime, "ERR_UNEXPECTED", error.what()).value());
    } catch (...) {
      reject.call(
          runtime,
          CodedJSError(
              runtime,
              "ERR_UNEXPECTED",
              "The native Promise result conversion threw a non-standard exception.")
              .value());
    }
  });
}

void Promise::resolveUndefined() {
  resolve([](jsi::Runtime &) { return jsi::Value::undefined(); });
}

void Promise::reject(std::string code, std::string message) {
  reject(CodedError(std::move(code), std::move(message)));
}

void Promise::reject(
    std::string code,
    std::string message,
    std::shared_ptr<const CodedError> cause) {
  reject(CodedError(
      std::move(code),
      std::move(message),
      ExceptionOrigin{},
      std::move(cause)));
}

void Promise::reject(CodedError codedError) {
  settle([codedError = std::move(codedError)](
             jsi::Runtime &runtime,
             jsi::Function &,
             jsi::Function &reject) {
    CodedJSError error(runtime, codedError);
    reject.call(runtime, error.value());
  });
}

std::shared_ptr<const CancellationToken> Promise::cancellationToken() const noexcept {
  return cancellationToken_;
}

bool Promise::isSettled() const noexcept {
  return settlementState_.isSettled();
}

void Promise::retainUntilSettled(std::shared_ptr<void> resource) {
  if (!resource) {
    return;
  }

  std::scoped_lock lock(retainedResourcesMutex_);
  if (!settlementState_.isSettled()) {
    retainedResources_.push_back(std::move(resource));
  }
}

void Promise::requestCancellation() noexcept {
  cancellationToken_->cancel();
}

void Promise::cancelAndReject() noexcept {
  requestCancellation();
  auto context = context_.lock();
  if (!context || !context->isAlive() || !context->isRuntimeThread() || !reject_) {
    invalidate();
    return;
  }
  // Keep promises in the teardown snapshot observable to JS until rejection.
  settlementState_.markSettled();
  releaseRetainedResources();

  try {
    CodedJSError error(
        context->runtime(),
        CodedError(
            "ERR_CANCELLED",
            "The native asynchronous operation was cancelled because the runtime was destroyed."));
    reject_->call(context->runtime(), error.value());
  } catch (...) {
    // Teardown is noexcept.
  }

  resolve_.reset();
  reject_.reset();
}

void Promise::invalidate() noexcept {
  requestCancellation();
  settlementState_.markSettled();
  releaseRetainedResources();
  resolve_.reset();
  reject_.reset();
}

void Promise::releaseRetainedResources() noexcept {
  (void)takeRetainedResources();
}

std::vector<std::shared_ptr<void>> Promise::takeRetainedResources() noexcept {
  try {
    std::vector<std::shared_ptr<void>> resources;
    {
      std::scoped_lock lock(retainedResourcesMutex_);
      resources.swap(retainedResources_);
    }
    return resources;
  } catch (...) {
    return {};
  }
}

}  // namespace expo::harmony
