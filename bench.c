/*
 * bench.c - 微基准测试程序
 * 功能: 执行固定次数的整数运算,测量耗时
 * 输出: 耗时(微秒)
 */

#include <stdio.h>
#include <time.h>
#include <stdint.h>

// 循环次数,可调整以适应不同性能的设备
#define ITERATIONS 1000000

// 使用volatile防止编译器优化
volatile uint64_t result = 0;

int main() {
    struct timespec start, end;
    uint64_t sum = 0;
    
    // 获取开始时间
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    // 执行固定次数的整数运算
    for (int i = 0; i < ITERATIONS; i++) {
        sum += i * 2 + 1;  // 简单的整数运算
    }
    
    // 获取结束时间
    clock_gettime(CLOCK_MONOTONIC, &end);
    
    // 将结果存储到volatile变量,防止整个循环被优化掉
    result = sum;
    
    // 计算耗时(微秒)
    long seconds = end.tv_sec - start.tv_sec;
    long nanoseconds = end.tv_nsec - start.tv_nsec;
    double elapsed_us = seconds * 1000000.0 + nanoseconds / 1000.0;
    
    // 输出耗时(微秒),保留两位小数
    printf("%.2f\n", elapsed_us);
    
    return 0;
}
