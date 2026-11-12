/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <exception>
#include <utility>

#include <RNOH/TaskExecutor/TaskExecutor.h>

namespace expo::harmony {

template <typename Task>
void runRnohSyncTask(rnoh::TaskExecutor &executor, rnoh::TaskThread thread, Task &&task) {
  if (executor.isOnTaskThread(thread)) {
    std::forward<Task>(task)();
    return;
  }

  // RNOH 0.86 rethrows task errors before clearing its thread wait dependency.
  // Carry the error to the caller after the executor has finished unwinding.
  std::exception_ptr error;
  executor.runSyncTask(thread, [&]() noexcept {
    try {
      std::forward<Task>(task)();
    } catch (...) {
      error = std::current_exception();
    }
  });

  if (error) {
    std::rethrow_exception(error);
  }
}

}  // namespace expo::harmony
