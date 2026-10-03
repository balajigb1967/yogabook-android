// Copyright 2017 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "halo_keyboard/haptics/touch_ff_manager.h"

#include <cmath>
#include <stdexcept>

#include "halo_keyboard/logging.h"

namespace {
// Path for left and right vibrators.
const char kLeftVibratorPath[] = "/dev/left_vibrator";
const char kRightVibratorPath[] = "/dev/right_vibrator";
}

namespace halo_keyboard {

TouchFFManager::TouchFFManager(int max_x, int max_y, int rotation,
    double magnitude, int duration_ms)
    : touch_max_x_(0), touch_rotation_(rotation) {
    if (max_x <= 0 || max_y <= 0) {
      throw std::invalid_argument("touch dimensions must be positive");
    }
    if (!std::isfinite(magnitude) || magnitude < 0.0 || magnitude > 1.0) {
      throw std::invalid_argument("haptic magnitude must be between 0.0 and 1.0");
    }
    if (duration_ms < 1 || duration_ms > 1000) {
      throw std::invalid_argument("haptic duration must be between 1 and 1000 ms");
    }
    switch (rotation) {
      case 0:
      case 180:
        touch_max_x_ = max_x;
        break;
      case 90:
      case 270:
        touch_max_x_ = max_y;
        break;
      default:
        throw std::invalid_argument("touch rotation must be 0, 90, 180, or 270");
    }

    if (!left_driver_.Init(kLeftVibratorPath)) {
      LOG(ERROR) << "Cannot find left motor\n";
    }

    if (!right_driver_.Init(kRightVibratorPath)) {
      LOG(ERROR) << "Cannot find right motor\n";
    }

    RegisterFF(TouchKeyboardEvent::FingerDown, magnitude, duration_ms);
}

void TouchFFManager::RegisterFF(TouchKeyboardEvent event,
                                double magnitude, int length_ms) {
  // The effect is uploaded to both drivers.
  const int left_event_id = left_driver_.UploadEffect(magnitude, length_ms);
  if (left_event_id >= 0) {
    left_driver_fflib_[event] = left_event_id;
  }

  const int right_event_id = right_driver_.UploadEffect(magnitude, length_ms);
  if (right_event_id >= 0) {
    right_driver_fflib_[event] = right_event_id;
  }
}

void TouchFFManager::EventTriggered(TouchKeyboardEvent event, int x, int y) {
  // Play ff effects based on the location of the event. Currently, we drive
  // left OR right motor depend on the event possition. When the event is on the
  // left half of touch surface, only the left vibrator will run.
  int val;

  switch (touch_rotation_) {
    case 0:
      val = x;
      break;
    case 90:
      val = touch_max_x_ - y;
      break;
    case 180:
      val = touch_max_x_ - x;
      break;
    case 270:
      val = y;
      break;
    default:
      val = x;
  }

  if (val < touch_max_x_ / 2) {
    PlayEffectOfEvent(event, left_driver_, left_driver_fflib_);
  } else {
    PlayEffectOfEvent(event, right_driver_, right_driver_fflib_);
  }
}

void TouchFFManager::PlayEffectOfEvent(
    TouchKeyboardEvent event,
    FFDriver& driver,
    const std::unordered_map<TouchKeyboardEvent, int, TouchKeyboardEventHash>& lib) {
  const auto iter = lib.find(event);
  if (iter == lib.end()) {
    return;
  }
  driver.PlayEffect(iter->second);
}

}  // namespace halo_keyboard
