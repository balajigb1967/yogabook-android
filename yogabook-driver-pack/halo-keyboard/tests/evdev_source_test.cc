// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/evdev_source.h"
#include "halo_keyboard/syscall_handler.h"

#include <cerrno>
#include <iostream>
#include <string>
#include <system_error>

namespace {

int failures = 0;

void Expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

class FakeSyscalls final : public halo_keyboard::SyscallHandler {
 public:
  int open(const char*, int) const override {
    errno = open_error;
    return open_result;
  }

  int close(int fd) const override {
    closed_fd = fd;
    return 0;
  }

  int open_result = 42;
  int open_error = 0;
  mutable int closed_fd = -1;
};

class TestSource final : public halo_keyboard::EvdevSource {
 public:
  explicit TestSource(halo_keyboard::SyscallHandler* syscalls)
      : EvdevSource(syscalls) {}

  using EvdevSource::OpenSourceDevice;
};

void ExpectOpenError(int error_number, bool expected_transition,
                     const std::string& description) {
  FakeSyscalls syscalls;
  syscalls.open_result = -1;
  syscalls.open_error = error_number;
  TestSource source(&syscalls);

  try {
    static_cast<void>(source.OpenSourceDevice("/dev/halo_keyboard"));
    Expect(false, description + " throws");
  } catch (const std::system_error& error) {
    Expect(error.code() == std::error_code(error_number,
                                           std::generic_category()),
           description + " preserves errno");
    Expect(halo_keyboard::IsExpectedSourceDeviceError(error.code()) ==
               expected_transition,
           description + " has the expected transition classification");
  }
}

}  // namespace

int main() {
  FakeSyscalls successful_syscalls;
  {
    TestSource source(&successful_syscalls);
    Expect(source.OpenSourceDevice("/dev/halo_keyboard"),
           "source device opens normally");
  }
  Expect(successful_syscalls.closed_fd == 42,
         "opened source descriptor is closed");

  ExpectOpenError(ENOENT, true, "disappeared source symlink");
  ExpectOpenError(ENODEV, true, "removed source device");
  ExpectOpenError(EACCES, false, "source permission failure");

  return failures == 0 ? 0 : 1;
}
