// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

#include "halo_keyboard/fake_keyboard.h"
#include "halo_keyboard/fake_touchpad.h"
#include "halo_keyboard/hardware_config.h"
#include "halo_keyboard/haptics/touch_ff_manager.h"
#include "halo_keyboard/logging.h"
#include "halo_keyboard/options.h"

namespace {

constexpr char kTouchSensorDevicePath[] = "/dev/halo_keyboard";

#ifndef HALO_KEYBOARD_DEFAULT_CONFIG_DIRECTORY
#error "HALO_KEYBOARD_DEFAULT_CONFIG_DIRECTORY must be defined by the build"
#endif

pid_t SpawnWorker(std::string_view name, const std::function<void()>& worker) {
  const pid_t pid = fork();
  if (pid < 0) {
    throw std::runtime_error("unable to fork " + std::string(name) +
                             " worker");
  }
  if (pid == 0) {
    try {
      worker();
      LOG(ERROR) << name << " worker returned unexpectedly\n";
    } catch (const std::system_error& error) {
      if (halo_keyboard::IsExpectedSourceDeviceError(error.code())) {
        LOG(INFO) << name
                  << " worker stopped because the Halo surface entered pen mode\n";
        std::cerr.flush();
        _exit(EXIT_SUCCESS);
      }
      LOG(ERROR) << name << " worker failed: " << error.what() << "\n";
    } catch (const std::exception& error) {
      LOG(ERROR) << name << " worker failed: " << error.what() << "\n";
    } catch (...) {
      LOG(ERROR) << name << " worker failed with an unknown exception\n";
    }
    std::cerr.flush();
    _exit(EXIT_FAILURE);
  }
  return pid;
}

pid_t WaitForWorker(int* status) {
  pid_t result;
  do {
    result = waitpid(-1, status, 0);
  } while (result < 0 && errno == EINTR);
  return result;
}

void StopWorker(pid_t pid) {
  if (pid <= 0) {
    return;
  }
  if (kill(pid, SIGTERM) < 0 && errno != ESRCH) {
    PLOG(ERROR) << "unable to stop worker " << pid << "\n";
  }
  while (waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {
  }
}

int Supervise(pid_t keyboard_pid, pid_t touchpad_pid) {
  int status = 0;
  bool expected_stop = false;
  const pid_t exited_pid = WaitForWorker(&status);
  if (exited_pid < 0) {
    PLOG(ERROR) << "waitpid failed\n";
    StopWorker(keyboard_pid);
    StopWorker(touchpad_pid);
    return EXIT_FAILURE;
  } else if (WIFEXITED(status)) {
    expected_stop = WEXITSTATUS(status) == EXIT_SUCCESS;
    if (expected_stop) {
      LOG(INFO) << "worker " << exited_pid
                << " stopped for the keyboard-to-pen mode transition\n";
    } else {
      LOG(ERROR) << "worker " << exited_pid << " exited with status "
                 << WEXITSTATUS(status) << "\n";
    }
  } else if (WIFSIGNALED(status)) {
    LOG(ERROR) << "worker " << exited_pid << " terminated by signal "
               << WTERMSIG(status) << "\n";
  }

  if (exited_pid == keyboard_pid) {
    StopWorker(touchpad_pid);
  } else if (exited_pid == touchpad_pid) {
    StopWorker(keyboard_pid);
  } else {
    StopWorker(keyboard_pid);
    StopWorker(touchpad_pid);
  }
  return expected_stop ? EXIT_SUCCESS : EXIT_FAILURE;
}

}  // namespace

int main(int argc, char* argv[]) {
  std::vector<std::string_view> arguments;
  arguments.reserve(static_cast<std::size_t>(argc > 0 ? argc - 1 : 0));
  for (int index = 1; index < argc; ++index) {
    arguments.emplace_back(argv[index]);
  }

  halo_keyboard::Options options;
  std::string option_error;
  switch (halo_keyboard::ParseOptions(arguments, &options, &option_error)) {
    case halo_keyboard::ParseResult::kHelp:
      halo_keyboard::PrintUsage(std::cout);
      return EXIT_SUCCESS;
    case halo_keyboard::ParseResult::kError:
      std::cerr << option_error << "\n";
      halo_keyboard::PrintUsage(std::cerr);
      return EXIT_FAILURE;
    case halo_keyboard::ParseResult::kSuccess:
      break;
  }

  if (options.debug_level > 0) {
    SetMinimumLogSeverity(DEBUG);
  }

  pid_t keyboard_pid = -1;
  pid_t touchpad_pid = -1;
  try {
    const std::filesystem::path config_directory =
        options.config_directory.empty()
            ? HALO_KEYBOARD_DEFAULT_CONFIG_DIRECTORY
            : options.config_directory;
    const halo_keyboard::HardwareConfig hardware_config =
        halo_keyboard::LoadHardwareConfig(config_directory / "hardware.csv");
    LOG(INFO) << "Starting halo-keyboard-handler for " << hardware_config.res_x
              << "x" << hardware_config.res_y << " sensor, rotation "
              << hardware_config.rotation << " degrees, configuration "
              << config_directory << "\n";

    keyboard_pid = SpawnWorker("keyboard", [&] {
      halo_keyboard::TouchFFManager haptics(
          hardware_config.res_x, hardware_config.res_y,
          hardware_config.rotation, options.haptic_magnitude,
          options.haptic_duration_ms);
      halo_keyboard::FakeKeyboard keyboard(
          hardware_config, haptics, config_directory / "layout.csv");
      keyboard.Run(kTouchSensorDevicePath, "Halo Keyboard");
    });

    touchpad_pid = SpawnWorker("touchpad", [&] {
      halo_keyboard::FakeTouchpad touchpad(
          hardware_config, config_directory / "touchpad.csv");
      touchpad.Run(kTouchSensorDevicePath, "Halo Keyboard Touchpad");
    });

    return Supervise(keyboard_pid, touchpad_pid);
  } catch (const std::exception& error) {
    LOG(ERROR) << "halo-keyboard-handler failed: " << error.what() << "\n";
    StopWorker(keyboard_pid);
    StopWorker(touchpad_pid);
    return EXIT_FAILURE;
  }
}
