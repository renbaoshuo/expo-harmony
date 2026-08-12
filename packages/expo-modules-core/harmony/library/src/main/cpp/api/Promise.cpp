#include "Promise.h"

#include "errors/CodedError.h"
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
    jsi::Runtime& runtime,
    const std::shared_ptr<RuntimeContext>& context,
    Setup setup) {
  auto constructor = runtime.global().getPropertyAsFunction(runtime, "Promise");
  auto executorName = jsi::PropNameID::forAscii(runtime, "expoPromiseExecutor");
  auto executor = jsi::Function::createFromHostFunction(
      runtime,
      executorName,
      2,
      [context, setup = std::move(setup)](
          jsi::Runtime& rt,
          const jsi::Value&,
          const jsi::Value* arguments,
          size_t count) {
        if (count != 2 || !arguments[0].isObject() || !arguments[1].isObject()) {
          throw makeJSError(
              rt, "ERR_PROMISE_SETUP", "JavaScript Promise supplied invalid callbacks.");
        }
        auto promise = std::shared_ptr<Promise>(new Promise(
            context,
            arguments[0].getObject(rt).getFunction(rt),
            arguments[1].getObject(rt).getFunction(rt)));
        context->retainPromise(promise);
        try {
          setup(promise);
        } catch (const CodedError& error) {
          promise->reject(error);
        } catch (const std::exception& error) {
          promise->reject("ERR_UNEXPECTED", error.what());
        }
        return jsi::Value::undefined();
      });
  return constructor.callAsConstructor(runtime, executor);
}

jsi::Value Promise::rejected(
    jsi::Runtime& runtime,
    const std::shared_ptr<RuntimeContext>& context,
    std::string code,
    std::string message) {
  return create(
      runtime,
      context,
      [code = std::move(code), message = std::move(message)](
          const std::shared_ptr<Promise>& promise) {
        promise->reject(code, message);
      });
}

void Promise::settle(std::function<void(jsi::Runtime&)> body) {
  if (settled_.exchange(true, std::memory_order_acq_rel)) {
    // Promise settlement is idempotent on the public JS surface. Throwing
    // here can escape a worker callback and terminate the native process.
    return;
  }
  auto context = context_.lock();
  if (!context || !context->isAlive()) return;
  auto task = [self = shared_from_this(), body = std::move(body)](
                  jsi::Runtime& runtime) mutable {
    auto context = self->context_.lock();
    if (!context || !context->isAlive()) return;
    try {
      body(runtime);
    } catch (...) {
      self->resolve_.reset();
      self->reject_.reset();
      context->releasePromise(self.get());
      throw;
    }
    self->resolve_.reset();
    self->reject_.reset();
    context->releasePromise(self.get());
  };
  if (context->isRuntimeThread()) {
    task(context->runtime());
  } else {
    context->jsInvoker()->invokeAsync(std::move(task));
  }
}

void Promise::resolve(ValueFactory valueFactory) {
  settle([self = shared_from_this(), valueFactory = std::move(valueFactory)](
             jsi::Runtime& runtime) mutable {
    try {
      self->resolve_->call(runtime, valueFactory(runtime));
    } catch (const CodedError& error) {
      self->reject_->call(runtime, makeJSError(runtime, error).value());
    } catch (const jsi::JSError& error) {
      self->reject_->call(runtime, error.value());
    } catch (const std::exception& error) {
      self->reject_->call(
          runtime,
          makeJSError(runtime, "ERR_UNEXPECTED", error.what()).value());
    } catch (...) {
      self->reject_->call(
          runtime,
          makeJSError(
              runtime,
              "ERR_UNEXPECTED",
              "The native Promise result conversion threw a non-standard exception.")
              .value());
    }
  });
}

void Promise::resolveUndefined() {
  resolve([](jsi::Runtime&) { return jsi::Value::undefined(); });
}

void Promise::reject(std::string code, std::string message) {
  reject(CodedError(std::move(code), std::move(message)));
}

void Promise::reject(
    std::string code,
    std::string message,
    std::shared_ptr<const CodedError> cause) {
  if (cause) {
    message += "\n→ Caused by: ";
    message += cause->what();
  }
  reject(CodedError(
      std::move(code),
      std::move(message),
      ExceptionOrigin{},
      std::move(cause)));
}

void Promise::reject(CodedError codedError) {
  settle([self = shared_from_this(), codedError = std::move(codedError)](
             jsi::Runtime& runtime) {
    auto error = makeJSError(runtime, codedError);
    self->reject_->call(runtime, error.value());
  });
}

std::shared_ptr<const CancellationToken> Promise::cancellationToken() const noexcept {
  return cancellationToken_;
}

bool Promise::isSettled() const noexcept {
  return settled_.load(std::memory_order_acquire);
}

void Promise::invalidate() noexcept {
  cancellationToken_->cancel();
  settled_.store(true, std::memory_order_release);
  resolve_.reset();
  reject_.reset();
}

} // namespace expo::harmony
