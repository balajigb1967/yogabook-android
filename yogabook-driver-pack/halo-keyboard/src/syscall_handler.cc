// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "halo_keyboard/syscall_handler.h"

#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace halo_keyboard {

int SyscallHandler::open(const char* pathname, int flags) const {
  return ::open(pathname, flags);
}

int SyscallHandler::close(int fd) const { return ::close(fd); }

ssize_t SyscallHandler::write(int fd, const void* buffer,
                              std::size_t count) const {
  return ::write(fd, buffer, count);
}

ssize_t SyscallHandler::read(int fd, void* buffer, std::size_t count) const {
  return ::read(fd, buffer, count);
}

int SyscallHandler::select(int nfds, fd_set* readfds, fd_set* writefds,
                           fd_set* exceptfds, struct timeval* timeout) const {
  return ::select(nfds, readfds, writefds, exceptfds, timeout);
}

int SyscallHandler::ioctl(int fd, unsigned long request_code) const {
  return ::ioctl(fd, request_code);
}

int SyscallHandler::ioctl(int fd, unsigned long request_code,
                          unsigned long argument) const {
  return ::ioctl(fd, request_code, argument);
}

int SyscallHandler::ioctl(int fd, unsigned long request_code,
                          void* argument) const {
  return ::ioctl(fd, request_code, argument);
}

SyscallHandler& DefaultSyscallHandler() {
  static SyscallHandler handler;
  return handler;
}

}  // namespace halo_keyboard
