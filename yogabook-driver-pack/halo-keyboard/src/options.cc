// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/options.h"

#include <charconv>
#include <cmath>
#include <ostream>

namespace halo_keyboard {
namespace {

template <typename T>
bool ParseNumber(std::string_view text, T* value) {
  const char* begin = text.data();
  const char* end = begin + text.size();
  const auto result = std::from_chars(begin, end, *value);
  return result.ec == std::errc{} && result.ptr == end;
}

bool TakeValue(const std::vector<std::string_view>& arguments, std::size_t* index,
               std::string_view option, std::string_view* value,
               std::string* error) {
  if (*index + 1 >= arguments.size()) {
    *error = "missing value for " + std::string(option);
    return false;
  }
  *value = arguments[++(*index)];
  return true;
}

}  // namespace

ParseResult ParseOptions(const std::vector<std::string_view>& arguments,
                         Options* options, std::string* error) {
  if (options == nullptr || error == nullptr) {
    return ParseResult::kError;
  }

  for (std::size_t index = 0; index < arguments.size(); ++index) {
    const std::string_view argument = arguments[index];
    if (argument == "-h" || argument == "--help") {
      return ParseResult::kHelp;
    }
    if (argument == "-d" || argument == "--debug") {
      ++options->debug_level;
      continue;
    }

    std::string_view value;
    if (argument == "-m" || argument == "--magnitude") {
      if (!TakeValue(arguments, &index, argument, &value, error) ||
          !ParseNumber(value, &options->haptic_magnitude) ||
          !std::isfinite(options->haptic_magnitude) ||
          options->haptic_magnitude < 0.0 || options->haptic_magnitude > 1.0) {
        *error = "haptic magnitude must be a number between 0.0 and 1.0";
        return ParseResult::kError;
      }
      continue;
    }
    if (argument == "-D" || argument == "--duration-ms") {
      if (!TakeValue(arguments, &index, argument, &value, error) ||
          !ParseNumber(value, &options->haptic_duration_ms) ||
          options->haptic_duration_ms < 1 || options->haptic_duration_ms > 1000) {
        *error = "haptic duration must be between 1 and 1000 milliseconds";
        return ParseResult::kError;
      }
      continue;
    }
    if (argument == "-c" || argument == "--config-directory") {
      if (!TakeValue(arguments, &index, argument, &value, error) ||
          value.empty()) {
        *error = "configuration directory must not be empty";
        return ParseResult::kError;
      }
      options->config_directory = value;
      continue;
    }

    *error = "unknown option: " + std::string(argument);
    return ParseResult::kError;
  }
  return ParseResult::kSuccess;
}

void PrintUsage(std::ostream& output) {
  output << "Usage: halo-keyboard-handler [options]\n"
         << "  -h, --help                 Show this help\n"
         << "  -d, --debug                Enable debug logging (repeatable)\n"
         << "  -m, --magnitude VALUE      Haptic magnitude from 0.0 to 1.0\n"
         << "  -D, --duration-ms VALUE    Haptic duration from 1 to 1000 ms\n"
         << "  -c, --config-directory DIR Configuration directory\n";
}

}  // namespace halo_keyboard
