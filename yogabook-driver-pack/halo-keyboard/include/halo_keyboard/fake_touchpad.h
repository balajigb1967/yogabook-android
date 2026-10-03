// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef HALO_KEYBOARD_FAKE_TOUCHPAD_H_
#define HALO_KEYBOARD_FAKE_TOUCHPAD_H_

#include <filesystem>
#include <string>
#include <vector>

#include "halo_keyboard/evdev_source.h"
#include "halo_keyboard/hardware_config.h"
#include "halo_keyboard/multitouch/state_machine.h"
#include "halo_keyboard/uinput_device.h"

namespace halo_keyboard {

class FakeTouchpad : public UinputDevice, public EvdevSource {
 /* Generate a "fake" touchpad device that pulls it's touch events from a sub-
  * region of a larger touch sensor.
  *
  * This class collects evdev events from one touch sensor and creates a
  * similar device with udev, then pipes events from a certain area through.
  * It also handles various bookkeeping with respect to which fingers are
  * within the "touchpad" region.  In essence, you initialize one of these
  * objects with a source device and the area you want to treat as a touchpad.
  * Then, when you run Start() it sets up the devices and will block forever
  * passing though the appropriate events and modifying them to maintain the
  * illusion of a normal touchpad.
  */
 public:
  FakeTouchpad(const HardwareConfig& hardware_config,
               const std::filesystem::path& layout_path);

  FakeTouchpad(const FakeTouchpad&) = delete;
  FakeTouchpad& operator=(const FakeTouchpad&) = delete;

  [[noreturn]] void Run(const std::string& source_device_path,
                        const std::string& touchpad_device_name);

 private:
  // Load touchpad geometry from file
  bool LoadLayout(const std::filesystem::path& layout_path);

  // Loop forever consuming events from the source and emitting them from the
  // fake touchpad -- the main workhorse function that Start() calls.
  [[noreturn]] void Consume();

  // Send button events indicating how many fingers are currently on the fake
  // touchpad.
  void SendTouchpadBtnEvents(int touch_count) const;

  // Test to see if the finger who's data is stored in the slot is currently
  // within the region defined as the touchpad.
  bool Contains(multitouch::Slot const &slot) const;

  // Check the state of the input touch and sync the fake touchpad by passing
  // through any new updates.
  int SyncTouchEvents();

  // Used by SyncTouchEvents, this function blindly duplicates the state stored
  // in the slot for the fake touchpad by replicating events for each value.
  bool PassEventsThrough(multitouch::Slot const &slot) const;

  // These member variables store the ranges of x/y coordinates that make up
  // the "touchpad" area on the source input device.
  int xmin_, xmax_, ymin_, ymax_;

  // 'Real world' touchpad width and height in mm
  double width_mm_, height_mm_;

  HardwareConfig hardware_config_;

  // Every FakeTouchpad needs a state machine to interpret incoming events, it
  // is defined and created here as a member of each object.
  multitouch::MtStateMachine sm_;

  // Here we store a mapping that determines which slots are in the touchpad
  // region or not currently.
  std::vector<bool> slot_memberships_;

};

}  // namespace halo_keyboard

#endif  // HALO_KEYBOARD_FAKE_TOUCHPAD_H_
