CC ?= gcc
CFLAGS ?= -nostdlib -no-pie
TARGET = fake-statuscord-asm

all: $(TARGET)

$(TARGET): main.s
	$(CC) $(CFLAGS) main.s -o $(TARGET)

clean:
	rm -f $(TARGET) discord-rpc

.PHONY: all clean
