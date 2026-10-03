// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef HALO_KEYBOARD_EVDEV_SOURCE_H_
#define HALO_KEYBOARD_EVDEV_SOURCE_H_

#include "halo_keyboard/logging.h"
#include <fcntl.h>
#include <linux/input.h>
#include <string>
#include <sys/select.h>
#include <system_error>

#include "halo_keyboard/syscall_handler.h"

namespace halo_keyboard {

// Timeout value to use when you want the EvdevSource to block indefinitely
// when calling GetNextEvent().
constexpr int kNoTimeout = -1;

bool IsExpectedSourceDeviceError(const std::error_code& error);

class EvdevSource {
 /* A class that uses an Evdev device as an event source
  *
  * This class opens an Evdev device and allows you to easily process the
  * events it is producing.  Generally speaking, you should probably derive
  * from this class instead of instantiating it directly.  Essentially you
  * should call OpenSourceDevice() at the beginning, then repeatedly
  * call GetNextEvent() to collect up the individual events being produced
  * by the Evdev device you selected.
  */
 public:
  EvdevSource();
  explicit EvdevSource(SyscallHandler* syscall_handler);
  virtual ~EvdevSource();

  EvdevSource(const EvdevSource&) = delete;
  EvdevSource& operator=(const EvdevSource&) = delete;

 protected:
  // Open the device file on disk and store the descriptor in this object.
  bool OpenSourceDevice(std::string const &source_device_path);
  // Wait for a new event to come from the source and populate *ev with it.
  bool GetNextEvent(int timeout_ms, struct input_event *ev) const;

  SyscallHandler *syscall_handler_;
  int source_fd_;
};

}  // namespace halo_keyboard

#endif  // HALO_KEYBOARD_EVDEV_SOURCE_H_
