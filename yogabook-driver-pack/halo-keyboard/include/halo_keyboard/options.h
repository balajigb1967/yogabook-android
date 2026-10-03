// SPDX-License-Identifier: BSD-3-Clause

#ifndef HALO_KEYBOARD_OPTIONS_H_
#define HALO_KEYBOARD_OPTIONS_H_

#include <iosfwd>
#include <string>
#include <string_view>
#include <vector>

namespace halo_keyboard {

struct Options {
  int debug_level = 0;
  double haptic_magnitude = 1.0;
  int haptic_duration_ms = 12;
  std::string config_directory;
};

enum class ParseResult { kSuccess, kHelp, kError };

ParseResult ParseOptions(const std::vector<std::string_view>& arguments,
                         Options* options, std::string* error);
void PrintUsage(std::ostream& output);

}  // namespace halo_keyboard

#endif  // HALO_KEYBOARD_OPTIONS_H_
