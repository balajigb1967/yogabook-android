// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "halo_keyboard/evdev_source.h"

#include <cerrno>
#include <stdexcept>
#include <system_error>

namespace halo_keyboard {

EvdevSource::EvdevSource()
    : syscall_handler_(&DefaultSyscallHandler()), source_fd_(-1) {}

EvdevSource::EvdevSource(SyscallHandler* syscall_handler)
    : syscall_handler_(syscall_handler != nullptr ? syscall_handler
                                                  : &DefaultSyscallHandler()),
      source_fd_(-1) {}

EvdevSource::~EvdevSource() {
  if (source_fd_ >= 0) {
    syscall_handler_->close(source_fd_);
  }
}

bool EvdevSource::OpenSourceDevice(std::string const &source_device_path) {
  if (source_fd_ >= 0) {
    return false;
  }
  source_fd_ = syscall_handler_->open(source_device_path.c_str(),
                                      O_RDONLY | O_CLOEXEC);
  if (source_fd_ < 0) {
    const int open_error = errno;
    throw std::system_error(open_error, std::generic_category(),
                            "open source device " + source_device_path);
  }
  return true;
}

bool IsExpectedSourceDeviceError(const std::error_code& error) {
  return error == std::errc::no_such_file_or_directory ||
         error == std::errc::no_such_device;
}

bool EvdevSource::GetNextEvent(int timeout_ms, struct input_event *ev) const {
  if (ev == nullptr) {
    throw std::invalid_argument("input event destination is null");
  }
  if (timeout_ms >= 0) {
    int num_ready;
    struct timeval timeout = {timeout_ms / 1000,
                              (timeout_ms % 1000) * 1000};
    fd_set set;

    // Block until there's something to read or we hit a timeout.
    FD_ZERO(&set);
    FD_SET(source_fd_, &set);
    num_ready = syscall_handler_->select(source_fd_ + 1, &set,
                                         nullptr, nullptr, &timeout);

    if (num_ready < 0) {
      throw std::system_error(errno, std::generic_category(), "select input device");
    }
    if (num_ready == 0) {
      return false;
    }
  }

  const ssize_t num_bytes_read = syscall_handler_->read(source_fd_, ev, sizeof(*ev));
  if (num_bytes_read < 0) {
    throw std::system_error(errno, std::generic_category(), "read input device");
  }
  if (num_bytes_read != static_cast<ssize_t>(sizeof(*ev))) {
    throw std::runtime_error("short read from input device");
  }
  return true;
}

}  // namespace halo_keyboard
