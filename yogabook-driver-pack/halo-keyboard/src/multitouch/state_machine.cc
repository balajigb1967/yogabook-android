// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "halo_keyboard/multitouch/state_machine.h"

#include <stdexcept>

namespace halo_keyboard::multitouch {

bool MtStateMachine::AddEvent(
    struct input_event const &ev,
    std::unordered_map<int, struct MtFinger> *out_snapshot) {
  // Here we process an event.  This function returns true at the end of a full
  // snapshot of the data (whenever there is a SYN event) and if you
  // pass it a pointer to an appropriate map, it will fill it with the
  // current state.  If you pass NULL, it will skip that step.
  if (ev.type == EV_SYN && ev.code == SYN_DROPPED) {
    Reset();
    dropping_events_ = true;
    return false;
  }
  if (dropping_events_) {
    if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
      dropping_events_ = false;
    }
    return false;
  }

  EventKey key(ev);
  if (key.IsSlot()) {
    current_slot_ =
        ev.value >= 0 && ev.value < static_cast<int>(kNumSlots) ? ev.value : -1;
  } else if (key.IsSyn()) {
    if (out_snapshot) {
      FillSnapshot(out_snapshot);
    }
    return true;
  } else if (ev.type == EV_ABS && current_slot_ >= 0) {
    slots_[static_cast<std::size_t>(current_slot_)][key] = ev.value;
  }
  return false;
}

void MtStateMachine::FillSnapshot(
    std::unordered_map<int, struct MtFinger> *out_snapshot) {
  out_snapshot->clear();

  for (const Slot& slot : slots_) {
    int tid = slot.FindValueByEvent(EV_ABS, ABS_MT_TRACKING_ID);
    if (tid == -1) {
      continue;
    }
    MtFinger finger;
    finger.x = slot.FindValueByEvent(EV_ABS, ABS_MT_POSITION_X);
    finger.y = slot.FindValueByEvent(EV_ABS, ABS_MT_POSITION_Y);
    finger.p = slot.FindValueByEvent(EV_ABS, ABS_MT_PRESSURE);
    finger.touch_major = slot.FindValueByEvent(EV_ABS, ABS_MT_TOUCH_MAJOR);
    (*out_snapshot)[tid] = finger;
  }
}

const Slot& MtStateMachine::slot(std::size_t index) const {
  if (index >= slots_.size()) {
    throw std::out_of_range("multitouch slot index is out of range");
  }
  return slots_[index];
}

void MtStateMachine::Reset() noexcept {
  for (Slot& slot : slots_) {
    slot.clear();
  }
  current_slot_ = 0;
  dropping_events_ = false;
}

}  // namespace halo_keyboard::multitouch
