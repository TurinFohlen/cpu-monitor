# Makefile for CPU Monitor Benchmark

CC = clang
CFLAGS = -O0 -Wall
TARGET = bench
SRC = bench.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)
	@echo "编译完成: $(TARGET)"
	@echo "运行 ./$(TARGET) 测试程序"

clean:
	rm -f $(TARGET)
	@echo "清理完成"

test: $(TARGET)
	@echo "运行测试..."
	@./$(TARGET)
