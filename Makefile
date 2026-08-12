CC ?= gcc
CFLAGS ?= -O2 -g -Wall -Wextra -Werror -pthread
LDFLAGS ?= -static -pthread

BUILD_DIR := build
TARGET := $(BUILD_DIR)/03390aa-packet-oob
HELPER := $(BUILD_DIR)/root_helper

.PHONY: all clean

all: $(TARGET) $(HELPER)

$(BUILD_DIR):
	mkdir -p $@

$(TARGET): exploit.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

$(HELPER): root_helper.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

clean:
	rm -f $(TARGET) $(HELPER)
