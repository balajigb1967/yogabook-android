// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/options.h"

#include <iostream>
#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

namespace {

int failures = 0;

void Expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

halo_keyboard::ParseResult Parse(
    std::initializer_list<std::string_view> arguments,
    halo_keyboard::Options* options, std::string* error) {
  return halo_keyboard::ParseOptions(
      std::vector<std::string_view>(arguments), options, error);
}

void ExpectRejected(std::initializer_list<std::string_view> arguments,
                    const std::string& description) {
  halo_keyboard::Options options;
  std::string error;
  Expect(Parse(arguments, &options, &error) ==
             halo_keyboard::ParseResult::kError,
         description + " should be rejected");
  Expect(!error.empty(), description + " should report an error");
}

}  // namespace

int main() {
  halo_keyboard::Options defaults;
  std::string error;
  Expect(Parse({}, &defaults, &error) == halo_keyboard::ParseResult::kSuccess,
         "defaults parse");
  Expect(defaults.debug_level == 0 && defaults.haptic_magnitude == 1.0 &&
             defaults.haptic_duration_ms == 12 &&
             defaults.config_directory.empty(),
         "defaults are stable");

  halo_keyboard::Options long_options;
  Expect(Parse({"--debug", "--debug", "--magnitude", "0.25",
                "--duration-ms", "20", "--config-directory", "/tmp/halo"},
               &long_options, &error) == halo_keyboard::ParseResult::kSuccess,
         "long options parse");
  Expect(long_options.debug_level == 2 &&
             long_options.haptic_magnitude == 0.25 &&
             long_options.haptic_duration_ms == 20 &&
             long_options.config_directory == "/tmp/halo",
         "long option values are retained");

  halo_keyboard::Options short_options;
  Expect(Parse({"-d", "-m", "0", "-D", "1000", "-c", "/etc/halo-keyboard"},
               &short_options, &error) ==
             halo_keyboard::ParseResult::kSuccess,
         "short options and boundary values parse");

  halo_keyboard::Options help_options;
  Expect(Parse({"--help"}, &help_options, &error) ==
             halo_keyboard::ParseResult::kHelp,
         "help is recognized");

  ExpectRejected({"--magnitude", "1.1"}, "out-of-range magnitude");
  ExpectRejected({"--magnitude", "nan"}, "non-finite magnitude");
  ExpectRejected({"--duration-ms", "0"}, "zero duration");
  ExpectRejected({"--duration-ms", "12ms"}, "malformed duration");
  ExpectRejected({"--duration-ms"}, "missing duration");
  ExpectRejected({"--config-directory"}, "missing configuration directory");
  ExpectRejected({"--config-directory", ""}, "empty configuration directory");
  ExpectRejected({"--unknown"}, "unknown option");

  return failures == 0 ? 0 : 1;
}
