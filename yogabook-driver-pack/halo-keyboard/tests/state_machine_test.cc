// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/multitouch/state_machine.h"

#include <iostream>
#include <linux/input.h>
#include <string>
#include <unordered_map>

namespace {

int failures = 0;

void Expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

input_event Event(unsigned short type, unsigned short code, int value) {
  input_event event {};
  event.type = type;
  event.code = code;
  event.value = value;
  return event;
}

void AddFinger(halo_keyboard::multitouch::MtStateMachine* machine, int slot,
               int tracking_id, int x, int y) {
  machine->AddEvent(Event(EV_ABS, ABS_MT_SLOT, slot), nullptr);
  machine->AddEvent(Event(EV_ABS, ABS_MT_TRACKING_ID, tracking_id), nullptr);
  machine->AddEvent(Event(EV_ABS, ABS_MT_POSITION_X, x), nullptr);
  machine->AddEvent(Event(EV_ABS, ABS_MT_POSITION_Y, y), nullptr);
}

}  // namespace

int main() {
  using halo_keyboard::multitouch::MtFinger;
  using halo_keyboard::multitouch::MtStateMachine;

  MtStateMachine machine;
  std::unordered_map<int, MtFinger> snapshot;
  AddFinger(&machine, 2, 42, 120, 340);
  Expect(machine.AddEvent(Event(EV_SYN, SYN_REPORT, 0), &snapshot),
         "SYN_REPORT completes a frame");
  Expect(snapshot.size() == 1 && snapshot.at(42).x == 120 &&
             snapshot.at(42).y == 340,
         "normal frame produces a finger snapshot");

  machine.AddEvent(Event(EV_ABS, ABS_MT_SLOT, -1), nullptr);
  machine.AddEvent(Event(EV_ABS, ABS_MT_POSITION_X, 999), nullptr);
  machine.AddEvent(Event(EV_ABS, ABS_MT_SLOT, 10), nullptr);
  machine.AddEvent(Event(EV_ABS, ABS_MT_POSITION_Y, 999), nullptr);
  machine.AddEvent(Event(EV_SYN, SYN_REPORT, 0), &snapshot);
  Expect(snapshot.at(42).x == 120 && snapshot.at(42).y == 340,
         "invalid slot indices cannot mutate a valid slot");

  Expect(!machine.AddEvent(Event(EV_SYN, SYN_DROPPED, 0), &snapshot),
         "SYN_DROPPED does not emit a snapshot");
  AddFinger(&machine, 0, 77, 1, 2);
  Expect(!machine.AddEvent(Event(EV_SYN, SYN_REPORT, 0), &snapshot),
         "first report after SYN_DROPPED only restores synchronization");
  Expect(!machine.AddEvent(Event(EV_SYN, SYN_REPORT, 0), &snapshot) ||
             snapshot.empty(),
         "dropped events do not survive resynchronization");

  AddFinger(&machine, 0, 88, 5, 6);
  Expect(machine.AddEvent(Event(EV_SYN, SYN_REPORT, 0), &snapshot) &&
             snapshot.size() == 1 && snapshot.at(88).x == 5,
         "new frames are accepted after resynchronization");

  bool out_of_range_thrown = false;
  try {
    static_cast<void>(machine.slot(10));
  } catch (const std::out_of_range&) {
    out_of_range_thrown = true;
  }
  Expect(out_of_range_thrown, "slot accessor rejects out-of-range indices");

  return failures == 0 ? 0 : 1;
}
