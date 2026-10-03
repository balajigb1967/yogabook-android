// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef HALO_KEYBOARD_UINPUT_DEVICE_H_
#define HALO_KEYBOARD_UINPUT_DEVICE_H_

#include <cstddef>
#include <cstdint>
#include <string>

#include "halo_keyboard/syscall_handler.h"
#include "halo_keyboard/uinput_definitions.h"


namespace halo_keyboard {

// This is the file handle on disk that you use to control the uinput module.
constexpr char kUinputControlFilename[] = "/dev/uinput";

class UinputDevice {
 /* A class to allow you to easily create uinput devices and generate events.
  *
  * This class can be used to create uinput devices, setup which events they
  * are capable of generating, and actually sending them.  The general flow is
  * to instantiate a UinputDevice object and call CreateUinputFD() to get the
  * process started.  You can then use the various EnableXXXX() functions to
  * enable the correct event types that you plan to generate.  Once all the
  * events are enabled, FinalizeUinputCreation() will tell the kernel create
  * the device and SendEvent() can now be used.
  */
 public:
  UinputDevice();
  explicit UinputDevice(SyscallHandler* syscall_handler);
  virtual ~UinputDevice();

  UinputDevice(const UinputDevice&) = delete;
  UinputDevice& operator=(const UinputDevice&) = delete;

 protected:
  // Generate a new uinput file descriptor to communicate with the uinput
  // module through.
  bool CreateUinputFD();

  // Enable this uinput device to generate a certain event type.  This are
  // overarching categories, not individual events.  eg: EV_ABS, EV_KEY, etc
  bool EnableEventType(int ev_type) const;

  // Enable this uinput device to generate a specific event code under the
  // event type specified in the function name. eg: KEY_ENTER or ABS_MT_SLOT
  bool EnableKeyEvent(int ev_code) const;
  bool EnableAbsEvent(int ev_code) const;

  // Clone the EV_ABS event capability of a given evdev device.  The width and
  // height are used to setup the ranges of X and Y coordinates.
  bool CopyABSOutputEvents(int source_evdev_fd, int width, int height,
                           int xres, int yres) const;

  // Wrap up creation once all your events are enabled, and give it a name.
  // Once this is called the device is ready to start sending events out.
  bool FinalizeUinputCreation(const std::string& device_name);

  // Once the device is finalized, this function sends the actual events
  // to the input subsystem just like a normal input device.
  void SendEvent(int ev_type, int ev_code, int value) const;

 private:
  SyscallHandler *syscall_handler_;
  int uinput_fd_;
  bool device_created_;

  // A helper function that determines if an event is supported by a device
  // when trying to clone its capabilities.
  static bool IsEventSupported(int event, const std::uint8_t* supported_events,
                               std::size_t byte_count);
};

}  // namespace halo_keyboard

#endif  // HALO_KEYBOARD_UINPUT_DEVICE_H_
