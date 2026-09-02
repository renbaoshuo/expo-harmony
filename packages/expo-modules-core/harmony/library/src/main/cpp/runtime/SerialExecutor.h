#pragma once

#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>

namespace expo::harmony {

// Runtime-owned FIFO executor for native module bodies.
class SerialExecutor final {
public:
  using ErrorHandler = std::function<void(std::string)>;
  using StoppedHandler = std::function<void()>;

  explicit SerialExecutor(ErrorHandler errorHandler = {});
  ~SerialExecutor() noexcept;

  SerialExecutor(const SerialExecutor &) = delete;
  SerialExecutor &operator=(const SerialExecutor &) = delete;

  bool dispatch(std::function<void()> task);
  // Stops work, waits up to `timeout`, and optionally reports a detached worker.
  bool shutdown(
      std::chrono::milliseconds timeout = std::chrono::milliseconds(250),
      StoppedHandler onStopped = {}) noexcept;
  bool isAcceptingTasks() const noexcept;
  std::thread::id threadId() const noexcept;

private:
  struct State final {
    explicit State(ErrorHandler handler)
        : errorHandler(std::move(handler)) {}

    mutable std::mutex mutex;
    std::condition_variable condition;
    std::deque<std::function<void()>> tasks;
    ErrorHandler errorHandler;
    StoppedHandler onStopped;
    bool accepting{true};
    bool detached{false};
    bool stopping{false};
    bool stopped{false};
    std::thread::id workerThread;
  };

  static void run(const std::shared_ptr<State> &state) noexcept;

  std::shared_ptr<State> state_;
  std::mutex shutdownMutex_;
  std::thread worker_;
};

}  // namespace expo::harmony
