// Copyright 2016 The Chromium OS Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef HALO_KEYBOARD_SYSCALL_HANDLER_H_
#define HALO_KEYBOARD_SYSCALL_HANDLER_H_

#include <cstddef>
#include <cstdint>
#include <sys/select.h>
#include <sys/types.h>

namespace halo_keyboard {

class SyscallHandler {
 public:
  virtual ~SyscallHandler() = default;

  virtual int open(const char* pathname, int flags) const;
  virtual int close(int fd) const;
  virtual ssize_t write(int fd, const void* buffer, std::size_t count) const;
  virtual ssize_t read(int fd, void* buffer, std::size_t count) const;
  virtual int select(int nfds, fd_set* readfds, fd_set* writefds,
                     fd_set* exceptfds, struct timeval* timeout) const;
  virtual int ioctl(int fd, unsigned long request_code) const;
  virtual int ioctl(int fd, unsigned long request_code,
                    unsigned long argument) const;
  virtual int ioctl(int fd, unsigned long request_code, void* argument) const;
};

SyscallHandler& DefaultSyscallHandler();

}  // namespace halo_keyboard

#endif  // HALO_KEYBOARD_SYSCALL_HANDLER_H_
