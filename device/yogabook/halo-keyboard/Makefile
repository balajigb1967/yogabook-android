CXX ?= g++
CXXFLAGS ?= -O2 -Wall -Wno-unused-parameter -std=c++17 -Isrc

SRCS = \
	src/main.cc \
	src/evdevsource.cc \
	src/fakekeyboard.cc \
	src/faketouchpad.cc \
	src/uinputdevice.cc \
	src/haptic/ff_driver.cc \
	src/haptic/touch_ff_manager.cc \
	src/statemachine/eventkey.cc \
	src/statemachine/slot.cc \
	src/statemachine/statemachine.cc \
	src/logging.cc

OBJS = $(SRCS:.cc=.o)
TARGET = touch_keyboard_handler

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS) -lpthread

%.o: %.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
