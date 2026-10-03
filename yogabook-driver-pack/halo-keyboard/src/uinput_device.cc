// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "halo_keyboard/uinput_device.h"

#include <array>
#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdexcept>
#include <system_error>

#include "halo_keyboard/logging.h"

namespace halo_keyboard {

// When creating a new uinput device, you must specify these parameters like
// with an actual, physical device.  These are sane, safe values that we use
// when creating a uinput device.
constexpr int kVersionNumber = 1;

constexpr std::size_t BytesForBits(std::size_t bit_count) {
  return (bit_count + 7U) / 8U;
}

UinputDevice::UinputDevice()
    : syscall_handler_(&DefaultSyscallHandler()),
      uinput_fd_(-1),
      device_created_(false) {}

UinputDevice::UinputDevice(SyscallHandler* syscall_handler)
    : syscall_handler_(syscall_handler != nullptr ? syscall_handler
                                                  : &DefaultSyscallHandler()),
      uinput_fd_(-1),
      device_created_(false) {}

UinputDevice::~UinputDevice() {
  // Tell the OS to destroy the uinput device as this object is destructed.
  if (uinput_fd_ >= 0 && device_created_) {
    int error = syscall_handler_->ioctl(uinput_fd_, UI_DEV_DESTROY);
    if (error) {
      PLOG(ERROR) << "Unable to destroy uinput device (" << error << ")\n";
    }
  }
  if (uinput_fd_ >= 0) {
    syscall_handler_->close(uinput_fd_);
  }
}

bool UinputDevice::CreateUinputFD() {
  // Open a control file descriptor for creating a new uinput device.
  // This file descriptor is used with ioctls to configure the device and
  // receive the outgoing event information.
  if (uinput_fd_ >= 0) {
    LOG(ERROR) << "Control FD already opened! (" << uinput_fd_ << ") Quitting.\n";
    return false;
  }

  uinput_fd_ = syscall_handler_->open(kUinputControlFilename,
                                      O_WRONLY | O_NONBLOCK | O_CLOEXEC);
  if (uinput_fd_ < 0) {
    PLOG(ERROR) << "Unable to open " << kUinputControlFilename <<
                   " (" << uinput_fd_ << ")\n";
    return false;
  }
  LOG(DEBUG) << "Uinput control file descriptor opened (" << uinput_fd_ << ")\n";
  return true;
}

bool UinputDevice::EnableEventType(int ev_type) const {
  // Tell the kernel that this uinput device will report events of a
  // certain type (ABS, KEY, etc).  Individual event codes must still be
  // enabled individually, but their overarching types need to be enabled
  // first, which is done here.
  int error = syscall_handler_->ioctl(
      uinput_fd_, UI_SET_EVBIT, static_cast<unsigned long>(ev_type));
  if (error) {
    LOG(ERROR) << "Unable to enable event type 0x" << std::hex << ev_type <<
                  "(" << std::dec << error << ")\n";
    return false;
  }
  LOG(DEBUG) << "Enabled events of type 0x" << std::hex << ev_type << "\n";
  return true;
}

bool UinputDevice::EnableKeyEvent(int ev_code) const {
  // Tell the kernel that this region's uinput device will report a specific
  // key event. (eg: KEY_BACKSPACE or BTN_TOUCH)
  int error = syscall_handler_->ioctl(
      uinput_fd_, UI_SET_KEYBIT, static_cast<unsigned long>(ev_code));
  if (error) {
    LOG(ERROR) << "Unable to enable EV_KEY 0x" << std::hex << ev_code <<
                  " events (" << std::dec << ")\n";
    return false;
  }
  LOG(DEBUG) << "Enabled EV_KEY 0x" << std::hex << ev_code << " events" << "\n";
  return true;
}

bool UinputDevice::EnableAbsEvent(int ev_code) const {
  // Tell the kernel that this region's uinput device will report a specific
  // kind of ABS event. (eg: ABS_MT_POSITION_X or ABS_PRESSURE)
  int error = syscall_handler_->ioctl(
      uinput_fd_, UI_SET_ABSBIT, static_cast<unsigned long>(ev_code));
  if (error) {
    LOG(ERROR) << "Unable to enable EV_ABS 0x" << std::hex << ev_code <<
                  " events (" << std::dec << error << ")\n";
    return false;
  }
  LOG(DEBUG) << "Enabled EV_ABS 0x" << std::hex << ev_code << " events\n";
  return true;
}

bool UinputDevice::CopyABSOutputEvents(int source_evdev_fd,
                                       int width, int height,
				       int xres, int yres) const {
  // Configure this region's uinput device to report the correct kinds of
  // events by copying the events that are reported by the input device
  // who's file descriptor is passed as a reference.
  // Instead of copying the range of the absolute axes though, the user
  // specifies the width and height manually -- essentially creating a
  // cloned input device with a different size than the source device.
  int error;
  std::array<std::uint8_t, BytesForBits(EV_CNT)> supported_event_types{};
  std::array<std::uint8_t, BytesForBits(ABS_CNT)> supported_abs_event_codes{};

  // Query the source evdev file descriptor to see which event types it
  // supports to make sure it supports ABS.
  if (syscall_handler_->ioctl(
          source_evdev_fd, EVIOCGBIT(0, supported_event_types.size()),
          supported_event_types.data()) < 0) {
    PLOG(ERROR) << "Unable to query source event capabilities\n";
    return false;
  }
  if (!IsEventSupported(EV_ABS, supported_event_types.data(),
                        supported_event_types.size())) {
    LOG(ERROR) << "Touchscreen does not support EV_ABS events.\n";
    return false;
  }

  // Enable the EV_ABS event type for this device.  Fail if it can't.
  if (!EnableEventType(EV_ABS)) {
    return false;
  }

  // Query the device to find which ABS event codes are supported and then
  // enable them for this uinput device as well.
  if (syscall_handler_->ioctl(
          source_evdev_fd,
          EVIOCGBIT(EV_ABS, supported_abs_event_codes.size()),
          supported_abs_event_codes.data()) < 0) {
    PLOG(ERROR) << "Unable to query source absolute-axis capabilities\n";
    return false;
  }
  for (int ev_code = 0; ev_code < ABS_CNT; ++ev_code) {
    // Skip over any event codes that are not supported.
    if (!IsEventSupported(ev_code, supported_abs_event_codes.data(),
                          supported_abs_event_codes.size())) {
      continue;
    }

    // Enable this event code for the uinput device.
    if (!EnableAbsEvent(ev_code)) {
      return false;
    }

    // Fill in the ranges for each EV_ABS axis, modifying them for X and Y.
    struct uinput_abs_setup abs_setup {};
    abs_setup.code = ev_code;
    if (syscall_handler_->ioctl(source_evdev_fd, EVIOCGABS(ev_code),
                                &abs_setup.absinfo) < 0) {
      PLOG(ERROR) << "Unable to query source axis 0x" << std::hex << ev_code
                  << "\n";
      return false;
    }
    if (ev_code == ABS_MT_POSITION_X || ev_code == ABS_X) {
      abs_setup.absinfo.minimum = 0;
      abs_setup.absinfo.maximum = width;
      abs_setup.absinfo.resolution = xres;
    } else if (ev_code == ABS_MT_POSITION_Y || ev_code == ABS_Y) {
      abs_setup.absinfo.minimum = 0;
      abs_setup.absinfo.maximum = height;
      abs_setup.absinfo.resolution = yres;
    }
    error = syscall_handler_->ioctl(uinput_fd_, UI_ABS_SETUP, &abs_setup);
    if (error) {
      LOG(ERROR) << "Unable to set up axis for event code 0x" << std::hex <<
                    ev_code << " (" << std::dec << error << ")\n";
      return false;
    }
  }

  LOG(INFO) << "Successfully copied all EV_ABS events from source device\n";
  return true;
}

bool UinputDevice::FinalizeUinputCreation(const std::string& device_name) {
  int error;
  struct uinput_setup device_info {};

  // Build a uinput device struct and write it to the ui_fd to specify the
  // various identification parameters required such as the device name.
  snprintf(device_info.name, UINPUT_MAX_NAME_SIZE, "%s", device_name.c_str());
  device_info.id.bustype = BUS_VIRTUAL;
  device_info.id.vendor  = 0;
  device_info.id.product = 0;
  device_info.id.version = kVersionNumber;
  error = syscall_handler_->ioctl(uinput_fd_, UI_DEV_SETUP, &device_info);
  if (error) {
    LOG(ERROR) << "uinput device setup ioctl failed. (" << error << ")\n";
    return false;
  }
  // Finally request that a new uinput device is created to those specs.
  // After this step the device should be fully functional and ready to
  // send events.
  error = syscall_handler_->ioctl(uinput_fd_, UI_DEV_CREATE);
  if (error) {
    LOG(ERROR) << "uinput device creation ioctl failed. (" << error << ")\n";
    return false;
  }
  device_created_ = true;

  LOG(INFO) << "Successfully finalized uinput device creation.\n";
  return true;
}

void UinputDevice::SendEvent(int ev_type, int ev_code, int value) const {
  // Send an input event to the kernel through this uinput device.
  struct input_event ev {};
  ev.type = ev_type;
  ev.code = ev_code;
  ev.value = value;

  const ssize_t bytes_written =
          syscall_handler_->write(uinput_fd_, &ev, sizeof(struct input_event));
  if (bytes_written < 0) {
    throw std::system_error(errno, std::generic_category(), "write uinput event");
  }
  if (bytes_written != static_cast<ssize_t>(sizeof(struct input_event))) {
    throw std::runtime_error("short write while sending uinput event");
  }
}

bool UinputDevice::IsEventSupported(int event,
                                    const std::uint8_t* supported_events,
                                    std::size_t byte_count) {
  if (event < 0 || supported_events == nullptr ||
      static_cast<std::size_t>(event / 8) >= byte_count) {
    return false;
  }
  return (supported_events[event / 8] & (1U << (event % 8))) != 0;
}

}  // namespace halo_keyboard
