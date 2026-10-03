cmake_minimum_required(VERSION 3.22)

project(halo_keyboard VERSION 1.0.0 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)
find_package(PkgConfig REQUIRED)

option(HALO_KEYBOARD_ENABLE_SANITIZERS
  "Build tests and binaries with AddressSanitizer and UndefinedBehaviorSanitizer"
  OFF)
option(HALO_KEYBOARD_WARNINGS_AS_ERRORS
  "Treat compiler warnings as errors"
  OFF)

pkg_check_modules(SYSTEMD QUIET systemd)
if(SYSTEMD_FOUND)
  pkg_get_variable(SYSTEMD_SYSTEM_UNIT_DIR systemd systemdsystemunitdir)
else()
  set(SYSTEMD_SYSTEM_UNIT_DIR "${CMAKE_INSTALL_PREFIX}/lib/systemd/system"
    CACHE PATH "systemd system unit directory")
endif()

pkg_check_modules(UDEV QUIET udev)
if(UDEV_FOUND)
  pkg_get_variable(UDEV_DIR udev udevdir)
else()
  set(UDEV_DIR "${CMAKE_INSTALL_PREFIX}/lib/udev"
    CACHE PATH "udev data directory")
endif()

function(halo_keyboard_target_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_17)
  set_target_properties(${target} PROPERTIES CXX_EXTENSIONS OFF)
  target_compile_options(${target} PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wformat=2
  )
  if(HALO_KEYBOARD_WARNINGS_AS_ERRORS)
    target_compile_options(${target} PRIVATE -Werror)
  endif()

  if(HALO_KEYBOARD_ENABLE_SANITIZERS)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
      target_compile_options(${target} PUBLIC
        -fno-omit-frame-pointer
        -fsanitize=address,undefined
      )
      target_link_options(${target} PUBLIC -fsanitize=address,undefined)
    else()
      message(FATAL_ERROR "Sanitizers require GCC or Clang")
    endif()
  endif()
endfunction()

add_library(halo-keyboard-core STATIC
  src/evdev_source.cc
  src/fake_keyboard.cc
  src/fake_touchpad.cc
  src/hardware_config.cc
  src/haptics/ff_driver.cc
  src/haptics/touch_ff_manager.cc
  src/logging.cc
  src/multitouch/event_key.cc
  src/multitouch/slot.cc
  src/multitouch/state_machine.cc
  src/options.cc
  src/syscall_handler.cc
  src/uinput_device.cc
)
target_include_directories(halo-keyboard-core
  PUBLIC "${PROJECT_SOURCE_DIR}/include"
  PRIVATE "${PROJECT_SOURCE_DIR}/third_party/fast_cpp_csv_parser"
)
halo_keyboard_target_defaults(halo-keyboard-core)

add_executable(halo-keyboard-handler src/main.cc)
target_link_libraries(halo-keyboard-handler PRIVATE halo-keyboard-core)
target_compile_definitions(halo-keyboard-handler PRIVATE
  HALO_KEYBOARD_DEFAULT_CONFIG_DIRECTORY="${CMAKE_INSTALL_FULL_SYSCONFDIR}/halo-keyboard"
)
halo_keyboard_target_defaults(halo-keyboard-handler)

install(TARGETS halo-keyboard-handler DESTINATION "${CMAKE_INSTALL_SBINDIR}")
install(DIRECTORY config/layouts DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/halo-keyboard")
install(FILES config/hardware.csv config/touchpad.csv
  DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/halo-keyboard")
install(FILES udev/60-halo-keyboard.rules DESTINATION "${UDEV_DIR}/rules.d")
install(FILES udev/61-halo-keyboard.hwdb DESTINATION "${UDEV_DIR}/hwdb.d")
install(FILES libwacom/wacom-yoga-book.tablet
  DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/libwacom")
install(FILES systemd/halo-keyboard.service systemd/halo-keyboard-backlight.service
  DESTINATION "${SYSTEMD_SYSTEM_UNIT_DIR}")
install(PROGRAMS libexec/ensure-backlight-minimum
  DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/halo-keyboard")
install(FILES docs/halo-keyboard-handler.8 DESTINATION "${CMAKE_INSTALL_MANDIR}/man8")
install(FILES ATTRIBUTION.md README.md
  DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/doc/halo-keyboard")

if(BUILD_TESTING)
  foreach(test_name IN ITEMS evdev_source hardware_config options state_machine uinput_device)
    add_executable(${test_name}-test tests/${test_name}_test.cc)
    target_link_libraries(${test_name}-test PRIVATE halo-keyboard-core)
    halo_keyboard_target_defaults(${test_name}-test)
    add_test(NAME ${test_name} COMMAND ${test_name}-test)
  endforeach()

  add_test(
    NAME project-metadata
    COMMAND bash "${PROJECT_SOURCE_DIR}/tests/check-project.sh" "${PROJECT_SOURCE_DIR}"
  )
  add_test(
    NAME input-database
    COMMAND bash "${PROJECT_SOURCE_DIR}/tests/check-input-database.sh" "${PROJECT_SOURCE_DIR}"
  )
  add_test(
    NAME backlight-policy
    COMMAND bash "${PROJECT_SOURCE_DIR}/tests/check-backlight-policy.sh" "${PROJECT_SOURCE_DIR}"
  )
  add_test(
    NAME maintainer-scripts
    COMMAND bash "${PROJECT_SOURCE_DIR}/tests/check-maintainer-scripts.sh" "${PROJECT_SOURCE_DIR}"
  )
  add_test(
    NAME handler-config
    COMMAND bash "${PROJECT_SOURCE_DIR}/tests/check-handler-config.sh"
      "$<TARGET_FILE:halo-keyboard-handler>"
  )
endif()
