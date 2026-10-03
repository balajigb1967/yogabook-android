// SPDX-License-Identifier: BSD-3-Clause

#include "halo_keyboard/hardware_config.h"

#include <cmath>
#include <stdexcept>
#include <string>

#define CSV_IO_NO_THREAD
#include "csv.h"

namespace halo_keyboard {
namespace {

void Validate(const HardwareConfig& config) {
  if (config.res_x <= 0 || config.res_y <= 0) {
    throw std::runtime_error("hardware resolution must be positive");
  }
  if (!std::isfinite(config.width_mm) || config.width_mm <= 0.0 ||
      !std::isfinite(config.height_mm) || config.height_mm <= 0.0) {
    throw std::runtime_error("hardware dimensions must be finite and positive");
  }
  if (!std::isfinite(config.left_margin_mm) || config.left_margin_mm < 0.0 ||
      !std::isfinite(config.top_margin_mm) || config.top_margin_mm < 0.0) {
    throw std::runtime_error("hardware margins must be finite and non-negative");
  }
  if (!IsSupportedRotation(config.rotation)) {
    throw std::runtime_error("hardware rotation must be 0, 90, 180, or 270 degrees");
  }
}

}  // namespace

bool IsSupportedRotation(int rotation) noexcept {
  return rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270;
}

HardwareConfig LoadHardwareConfig(const std::filesystem::path& path) {
  io::CSVReader<7, io::trim_chars<' ', '\t'>, io::no_quote_escape<';'>> csv(
      path.string());
  csv.read_header(io::ignore_no_column, "resolution_x", "resolution_y",
                  "width_mm", "height_mm", "left_margin_mm", "top_margin_mm",
                  "rotation_cw");

  HardwareConfig config;
  if (!csv.read_row(config.res_x, config.res_y, config.width_mm,
                    config.height_mm, config.left_margin_mm,
                    config.top_margin_mm, config.rotation)) {
    throw std::runtime_error("hardware configuration has no data row: " +
                             path.string());
  }
  Validate(config);
  return config;
}

}  // namespace halo_keyboard
