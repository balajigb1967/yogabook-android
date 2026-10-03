#ifndef HALO_KEYBOARD_LOGGING_H_
#define HALO_KEYBOARD_LOGGING_H_

#include <cerrno>
#include <cstring>
#include <iostream>

enum LogSeverity {
  VERBOSE,
  DEBUG,
  INFO,
  WARNING,
  ERROR,
  FATAL_WITHOUT_ABORT,
  FATAL,
};

void SetMinimumLogSeverity(enum LogSeverity severity);
std::ostream& get_log_stream(enum LogSeverity severity);

#define LOG(severity) (get_log_stream(severity) << #severity[0] << " ")
#define PLOG(severity) (LOG(severity) << std::strerror(errno) << ": ")

#endif  // HALO_KEYBOARD_LOGGING_H_
