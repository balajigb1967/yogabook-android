// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/syscall_handler.h"
#include "halo_keyboard/uinput_device.h"

#include <cerrno>
#include <iostream>
#include <linux/uinput.h>
#include <stdexcept>
#include <string>

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
  int open(const char*, int) const override { return 42; }
  int close(int fd) const override {
    closed_fd = fd;
    return 0;
  }
  ssize_t write(int, const void*, std::size_t count) const override {
    return short_write ? static_cast<ssize_t>(count - 1)
                       : static_cast<ssize_t>(count);
  }
  int ioctl(int, unsigned long request) const override {
    if (request == UI_DEV_CREATE) {
      ++create_calls;
      return fail_create ? -1 : 0;
    }
    if (request == UI_DEV_DESTROY) {
      ++destroy_calls;
    }
    return 0;
  }
  int ioctl(int, unsigned long request, void*) const override {
    if (request == UI_DEV_SETUP) {
      ++setup_calls;
    }
    return 0;
  }

  mutable int setup_calls = 0;
  mutable int create_calls = 0;
  mutable int destroy_calls = 0;
  mutable int closed_fd = -1;
  bool fail_create = false;
  bool short_write = false;
};

class TestDevice final : public halo_keyboard::UinputDevice {
 public:
  explicit TestDevice(halo_keyboard::SyscallHandler* syscalls)
      : UinputDevice(syscalls) {}

  using UinputDevice::CreateUinputFD;
  using UinputDevice::FinalizeUinputCreation;
  using UinputDevice::SendEvent;
};

}  // namespace

int main() {
  FakeSyscalls successful_syscalls;
  {
    TestDevice device(&successful_syscalls);
    Expect(device.CreateUinputFD(), "uinput descriptor opens");
    Expect(device.FinalizeUinputCreation("Halo Test"),
           "uinput device finalizes");
    device.SendEvent(EV_KEY, KEY_A, 1);
  }
  Expect(successful_syscalls.setup_calls == 1 &&
             successful_syscalls.create_calls == 1,
         "setup and create are each requested once");
  Expect(successful_syscalls.destroy_calls == 1,
         "successfully created device is destroyed");
  Expect(successful_syscalls.closed_fd == 42, "uinput descriptor is closed");

  FakeSyscalls failing_syscalls;
  failing_syscalls.fail_create = true;
  {
    TestDevice device(&failing_syscalls);
    Expect(device.CreateUinputFD(), "failing test descriptor opens");
    Expect(!device.FinalizeUinputCreation("Halo Test"),
           "failed create is reported");
  }
  Expect(failing_syscalls.destroy_calls == 0,
         "failed device creation is not destroyed");
  Expect(failing_syscalls.closed_fd == 42,
         "descriptor closes after failed creation");

  FakeSyscalls short_write_syscalls;
  short_write_syscalls.short_write = true;
  bool short_write_thrown = false;
  {
    TestDevice device(&short_write_syscalls);
    Expect(device.CreateUinputFD(), "short-write test descriptor opens");
    try {
      device.SendEvent(EV_KEY, KEY_A, 1);
    } catch (const std::runtime_error&) {
      short_write_thrown = true;
    }
  }
  Expect(short_write_thrown, "short uinput writes throw");

  return failures == 0 ? 0 : 1;
}
