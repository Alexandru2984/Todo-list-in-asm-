ASM = nasm
ASMFLAGS = -f elf64 -g
LD = ld
LDFLAGS = 

SRC_DIR = src
OBJ_DIR = .
BIN_DIR = bin

SRCS = $(wildcard $(SRC_DIR)/*.asm)
OBJS = $(patsubst $(SRC_DIR)/%.asm, $(OBJ_DIR)/%.o, $(SRCS))
TARGET = $(BIN_DIR)/server

.PHONY: all clean run setup

all: setup $(TARGET)

setup:
	mkdir -p $(BIN_DIR) data logs

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.asm
	$(ASM) $(ASMFLAGS) $< -o $@

run: all
	./$(TARGET)

clean:
	rm -f $(OBJ_DIR)/*.o $(TARGET)
