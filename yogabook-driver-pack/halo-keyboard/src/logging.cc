#include <iostream>
#include <streambuf>

#include "halo_keyboard/logging.h"

namespace {

class NullBuffer : public std::streambuf {
 public:
  int_type overflow(int_type character) override { return character; }
};

NullBuffer null_buffer;
std::ostream null_stream(&null_buffer);
LogSeverity min_severity = INFO;

}  // namespace

std::ostream& get_log_stream(enum LogSeverity severity)
{
  if (severity >= min_severity) {
    return std::clog;
  }
  return null_stream;
}

void SetMinimumLogSeverity(enum LogSeverity severity)
{
  min_severity = severity;
}
