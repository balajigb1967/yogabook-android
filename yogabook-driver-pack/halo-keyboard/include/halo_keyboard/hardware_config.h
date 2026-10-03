// SPDX-License-Identifier: BSD-3-Clause

#ifndef HALO_KEYBOARD_HARDWARE_CONFIG_H_
#define HALO_KEYBOARD_HARDWARE_CONFIG_H_

#include <filesystem>

namespace halo_keyboard {

struct HardwareConfig {
  int rotation = 0;
  int res_x = 0;
  int res_y = 0;
  double width_mm = 0.0;
  double height_mm = 0.0;
  double left_margin_mm = 0.0;
  double top_margin_mm = 0.0;
};

bool IsSupportedRotation(int rotation) noexcept;
HardwareConfig LoadHardwareConfig(const std::filesystem::path& path);

}  // namespace halo_keyboard

#endif  // HALO_KEYBOARD_HARDWARE_CONFIG_H_
