ASM ?= nasm
ASMFLAGS ?= -f elf64 -g -w+error
LD ?= ld
LDFLAGS ?= -z noexecstack -z separate-code

SRCS := $(wildcard src/*.asm)
OBJS := $(patsubst src/%.asm,build/%.o,$(SRCS))
WEB := $(wildcard web/*)
TARGET := build/server

.PHONY: all clean run test check
all: $(TARGET) build/backup build/offsite build/probe

build:
	mkdir -p build

$(TARGET): $(OBJS) build/sha256.o
	$(LD) $(LDFLAGS) -o $@ $^

build/%.o: src/%.asm src/defs.inc | build
	$(ASM) $(ASMFLAGS) $< -o $@

build/router.o: $(WEB)

build/main.o build/http.o build/json.o build/import_data.o build/import_json.o build/import_csv.o build/import_lines.o build/import_http.o: src/import.inc

build/backup: build/backup-native.o build/sha256.o build/utils.o
	$(LD) $(LDFLAGS) -o $@ $^

build/backup-native.o: native/backup.asm src/defs.inc | build
	$(ASM) $(ASMFLAGS) $< -o $@

build/sha256.o: native/sha256.asm | build
	$(ASM) $(ASMFLAGS) $< -o $@

build/offsite: build/offsite-native.o build/utils.o
	$(LD) $(LDFLAGS) -o $@ $^

build/offsite-native.o: native/offsite.asm src/defs.inc | build
	$(ASM) $(ASMFLAGS) $< -o $@

build/probe: build/probe-native.o build/utils.o
	$(LD) $(LDFLAGS) -o $@ $^

build/probe-native.o: native/probe.asm src/defs.inc | build
	$(ASM) $(ASMFLAGS) $< -o $@

run: all
	mkdir -p data
	./$(TARGET)

test: all
	python3 -m unittest discover -s tests -p 'test_*.py' -v

check: test
	node --check web/app.js

clean:
	rm -rf build
