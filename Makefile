ASM ?= nasm
ASMFLAGS ?= -f elf64 -g -w+error
LD ?= ld
LDFLAGS ?= -z noexecstack -z separate-code

SRCS := $(wildcard src/*.asm)
OBJS := $(patsubst src/%.asm,build/%.o,$(SRCS))
WEB := $(wildcard web/*)
TARGET := build/server

.PHONY: all clean run test check
all: $(TARGET)

build:
	mkdir -p build

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

build/%.o: src/%.asm src/defs.inc | build
	$(ASM) $(ASMFLAGS) $< -o $@

build/router.o: $(WEB)

run: all
	mkdir -p data
	./$(TARGET)

test: all
	python3 -m unittest discover -s tests -p 'test_*.py' -v

check: test
	node --check web/app.js

clean:
	rm -rf build
