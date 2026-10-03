// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/hardware_config.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unistd.h>

namespace {

int failures = 0;

void Expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

std::filesystem::path WriteConfig(const std::string& row) {
  static int sequence = 0;
  const auto path = std::filesystem::temp_directory_path() /
                    ("halo-keyboard-config-test-" +
                     std::to_string(::getpid()) + "-" +
                     std::to_string(sequence++) + ".csv");
  std::ofstream output(path);
  output << "resolution_x;resolution_y;width_mm;height_mm;left_margin_mm;"
            "top_margin_mm;rotation_cw\n"
         << row << '\n';
  return path;
}

void ExpectRejected(const std::string& row, const std::string& description) {
  const auto path = WriteConfig(row);
  try {
    static_cast<void>(halo_keyboard::LoadHardwareConfig(path));
    Expect(false, description + " should be rejected");
  } catch (const std::exception&) {
  }
  std::filesystem::remove(path);
}

}  // namespace

int main() {
  const auto valid_path = WriteConfig("1920;1080;256.0;144.0;1.5;2.5;270");
  const auto config = halo_keyboard::LoadHardwareConfig(valid_path);
  std::filesystem::remove(valid_path);

  Expect(config.res_x == 1920 && config.res_y == 1080,
         "valid resolution is loaded");
  Expect(config.width_mm == 256.0 && config.height_mm == 144.0,
         "valid dimensions are loaded");
  Expect(config.rotation == 270, "valid rotation is loaded");
  Expect(halo_keyboard::IsSupportedRotation(90), "90 degrees is supported");
  Expect(!halo_keyboard::IsSupportedRotation(45), "45 degrees is unsupported");

  ExpectRejected("0;1080;256;144;0;0;0", "zero resolution");
  ExpectRejected("1920;1080;256;144;0;0;45", "invalid rotation");
  ExpectRejected("1920;1080;nan;144;0;0;0", "NaN dimension");
  ExpectRejected("1920;1080;256;144;-1;0;0", "negative margin");

  return failures == 0 ? 0 : 1;
}
