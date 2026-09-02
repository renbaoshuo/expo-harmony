#include "SerialExecutor.h"

#include <algorithm>
#include <exception>

#if defined(__OHOS__)
#include "errors/CodedError.h"
#endif

namespace expo::harmony {

SerialExecutor::SerialExecutor(ErrorHandler errorHandler)
    : state_(std::make_shared<State>(std::move(errorHandler))),
      worker_([state = state_] { run(state); }) {}

SerialExecutor::~SerialExecutor() noexcept {
  shutdown();
}

bool SerialExecutor::dispatch(std::function<void()> task) {
  if (!task) {
    return false;
  }
  {
    std::scoped_lock lock(state_->mutex);
    if (!state_->accepting) {
      return false;
    }
    state_->tasks.push_back(std::move(task));
  }
  state_->condition.notify_one();
  return true;
}

bool SerialExecutor::shutdown(
    std::chrono::milliseconds timeout,
    StoppedHandler onStopped) noexcept {
  const auto waitDuration = std::max(timeout, std::chrono::milliseconds::zero());
  auto state = state_;
  std::thread worker;
  bool calledFromWorker = false;
  {
    std::scoped_lock shutdownLock(shutdownMutex_);
    {
      std::scoped_lock lock(state->mutex);
      calledFromWorker = state->workerThread == std::this_thread::get_id();
      state->accepting = false;
      state->stopping = true;
      state->tasks.clear();
    }
    if (!worker_.joinable()) {
      state->condition.notify_all();
    } else if (worker_.get_id() == std::this_thread::get_id()) {
      // run() owns the state independently of this object.
      worker_.detach();
      {
        std::scoped_lock lock(state->mutex);
        state->detached = true;
        if (onStopped && !state->onStopped) {
          state->onStopped = std::move(onStopped);
        }
      }
      state->condition.notify_all();
    } else {
      // Release the mutex before join so a worker can call shutdown().
      worker = std::move(worker_);
    }
  }
  state->condition.notify_all();
  if (calledFromWorker) {
    if (onStopped) {
      std::scoped_lock lock(state->mutex);
      if (!state->stopped && !state->onStopped) {
        state->onStopped = std::move(onStopped);
      }
    }
    return false;
  }

  if (worker.joinable()) {
    std::unique_lock lock(state->mutex);
    const bool stopped = state->condition.wait_for(lock, waitDuration, [&] {
      return state->stopped;
    });
    if (stopped) {
      lock.unlock();
      worker.join();
      return true;
    }
    // Keep the check and callback registration under State's mutex.
    if (onStopped && !state->onStopped) {
      state->onStopped = std::move(onStopped);
    }
    state->detached = true;
    worker.detach();
    lock.unlock();
    state->condition.notify_all();
    return false;
  }

  // Wait for a concurrent joiner, but never wait unboundedly.
  std::unique_lock lock(state->mutex);
  if (state->detached) {
    if (state->stopped) {
      return true;
    }
    if (onStopped && !state->onStopped) {
      state->onStopped = std::move(onStopped);
    }
    return false;
  }
  state->condition.wait_for(lock, waitDuration, [&] {
    return state->stopped || state->detached;
  });
  if (state->stopped) {
    return true;
  }
  if (onStopped && !state->onStopped) {
    state->onStopped = std::move(onStopped);
  }
  return false;
}

bool SerialExecutor::isAcceptingTasks() const noexcept {
  std::scoped_lock lock(state_->mutex);
  return state_->accepting;
}

std::thread::id SerialExecutor::threadId() const noexcept {
  std::scoped_lock lock(state_->mutex);
  return state_->workerThread;
}

void SerialExecutor::run(const std::shared_ptr<State> &state) noexcept {
  const auto reportError = [&state](std::string message) noexcept {
    if (!state->errorHandler) {
      return;
    }
    try {
      state->errorHandler(std::move(message));
    } catch (...) {
      // Error reporting must not terminate the runtime-owned worker.
    }
  };

  {
    std::scoped_lock lock(state->mutex);
    state->workerThread = std::this_thread::get_id();
  }
  state->condition.notify_all();

  while (true) {
    std::function<void()> task;
    {
      std::unique_lock lock(state->mutex);
      state->condition.wait(lock, [&] {
        return state->stopping || !state->tasks.empty();
      });
      if (state->stopping) {
        auto onStopped = std::move(state->onStopped);
        state->stopped = true;
        lock.unlock();
        state->condition.notify_all();
        if (onStopped) {
          try {
            onStopped();
          } catch (...) {
            // Runtime teardown continuations must never escape the worker.
          }
        }
        return;
      }
      task = std::move(state->tasks.front());
      state->tasks.pop_front();
    }
    try {
      task();
#if defined(__OHOS__)
    } catch (const CodedError &error) {
      reportError(error.what());
#endif
    } catch (const std::exception &error) {
      reportError(error.what());
    } catch (...) {
      reportError("Unknown native exception");
    }
  }
}

}  // namespace expo::harmony
