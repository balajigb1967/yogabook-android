// Copyright 2017 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "halo_keyboard/haptics/ff_driver.h"

#include <algorithm>
#include <cmath>
#include <cerrno>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "halo_keyboard/logging.h"

namespace {
// This value drive the vibrator at max strength.
constexpr int kMaxDriverInput = 0xffff;
}

namespace halo_keyboard {

FFDriver::FFDriver() : fd_(-1) {}

FFDriver::~FFDriver() {
  CloseFDIfValid();
}

// Try to open the device, will return false if failed.
bool FFDriver::Init(const std::string& device_path) {
  struct input_event gain_event {};
  // Close the fd if previously inited.
  CloseFDIfValid();

  fd_ = open(device_path.c_str(), O_RDWR | O_CLOEXEC);
  if (fd_ == -1) {
    PLOG(ERROR) << "Fail to open haptic device\n";
    return false;
  }

  gain_event.type = EV_FF;
  gain_event.code = FF_GAIN;
  gain_event.value = kMaxDriverInput;

  if (write(fd_, &gain_event, sizeof(gain_event)) !=
      static_cast<ssize_t>(sizeof(gain_event))) {
    PLOG(ERROR) << "Failed to set FF gain\n";
  }

  return true;
}

int FFDriver::UploadEffect(float magnitude, int time_ms) {
  if (fd_ == -1) {
    LOG(DEBUG) << "Cannot upload effect because FFDriver is not initialized\n";
    return -1;
  }
  if (!std::isfinite(magnitude) || magnitude < 0.0F || magnitude > 1.0F ||
      time_ms <= 0 || time_ms > 1000) {
    LOG(ERROR) << "Invalid force-feedback effect parameters\n";
    return -1;
  }
  struct ff_effect effect {};
  // Set up the effect with parameters.
  effect.type = FF_RUMBLE;
  effect.id = -1;
  effect.u.rumble.strong_magnitude =
      static_cast<unsigned short>(std::clamp(magnitude, 0.0F, 1.0F) *
                                  kMaxDriverInput);
  effect.u.rumble.weak_magnitude = 0;
  effect.replay.length = time_ms;
  effect.replay.delay = 0;

  if (ioctl(fd_, EVIOCSFF, &effect) == -1) {
    PLOG(ERROR) << "Fail to upload effect\n";
    return -1;
  }

  return effect.id;
}

bool FFDriver::PlayEffect(int id) {
  if (fd_ == -1) {
    LOG(DEBUG) << "Cannot play effect because FFDriver is not initialized\n";
    return false;
  }

  if (id < 0) {
    LOG(ERROR) << "Invalid effect id\n";
    return false;
  }

  struct input_event play {};
  play.type = EV_FF;
  play.code = id;
  play.value = 1;

  if (write(fd_, &play, sizeof(play)) != static_cast<ssize_t>(sizeof(play))) {
    PLOG(ERROR) << "Fail to play effect\n";
    return false;
  }
  return true;
}

void FFDriver::CloseFDIfValid() {
  if (fd_ != -1) {
    close(fd_);
    fd_ = -1;
  }
}

}  // namespace halo_keyboard
