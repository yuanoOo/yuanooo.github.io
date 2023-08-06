---
title: Linux系统编程-文件与I/O
tags:
  - os
categories:
  - - os
abbrlink: 19576
date: 2022-10-09 13:47:56
updated: 2022-10-09 13:47:56
cover:
top_img:
description:
keywords:
---

##  read/write

读常规文件是不会阻塞的，不管读多少字节，`read`一定会在有限的时间内返回。从终端设备或网络读则不一定，如果从终端输入的数据没有换行符，调用`read`读终端设备就会阻塞，如果网络上没有接收到数据包，调用`read`从网络读就会阻塞，至于会阻塞多长时间也是不确定的，如果一直没有数据到达就一直阻塞在那里。同样，写常规文件是不会阻塞的，而向终端设备或网络写则不一定。

现在明确一下阻塞（Block）这个概念。当进程调用一个阻塞的系统函数时，该进程被置于睡眠（Sleep）状态，这时内核调度其它进程运行，直到该进程等待的事件发生了（比如网络上接收到数据包，或者调用`sleep`指定的睡眠时间到了）它才有可能继续运行。与睡眠状态相对的是运行（Running）状态，在Linux内核中，处于运行状态的进程分为两种情况：

- 正在被调度执行。CPU处于该进程的上下文环境中，程序计数器（`eip`）里保存着该进程的指令地址，通用寄存器里保存着该进程运算过程的中间结果，正在执行该进程的指令，正在读写该进程的地址空间。
- 就绪状态。该进程不需要等待什么事件发生，随时都可以执行，但CPU暂时还在执行另一个进程，所以该进程在一个就绪队列中等待被内核调度。系统中可能同时有多个就绪的进程，那么该调度谁执行呢？内核的调度算法是基于优先级和时间片的，而且会根据每个进程的运行情况动态调整它的优先级和时间片，让每个进程都能比较公平地得到机会执行，同时要兼顾用户体验，不能让和用户交互的进程响应太慢。

## mmap函数系统调用

`mmap`可以把磁盘文件的一部分直接映射到内存，这样文件中的位置直接就有对应的内存地址，对文件的读写可以直接用指针来做而不需要`read`/`write`函数。

> mmap, munmap - map or unmap files or devices into memory
>
> void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
> int munmap(void *addr, size_t length);
>
> mmap() creates a new mapping in the virtual address space of the calling process.  The starting address for the new mapping is specified in addr.  The length argument specifies the length of the mapping (which must be greater than 0).

```c
#include <stdlib.h>
#include <sys/mman.h>
#include <fcntl.h>

int main(void)
{
        int *p;
        int fd = open("hello", O_RDWR);
        if (fd < 0) {
                perror("open hello");
                exit(1);
        }

          // 6：文件映射到内存的长度
          // PROT_WRITE：映射的这段内存可写
          // MAP_SHARED：多个进程对同一个文件的映射是共享的，一个进程对映射的内存做了修改，另一个进程也会看到这种变化。
          // fd：文件描述符
          // 0：offset
        p = mmap(NULL, 6, PROT_WRITE, MAP_SHARED, fd, 0);
        if (p == MAP_FAILED) {
                perror("mmap");
                exit(1);
        }
        close(fd);

      char *char_point = (char *)p;
      //p[0] = 0x30313233;
      // 修改第一个字符为i
      char_point[0] = 'i';

      // 解除内存映射
      munmap(p, 6);
      return 0;
}
```

修改后，mmap不会立即将更新同步到文件，可以用msync函数将更新刷到内存。

>  msync - synchronize a file with a memory map 
>
> int msync(void *addr, size_t length, int flags);
>
> msync() flushes changes made to the in-core copy of a file that was mapped into memory using mmap(2) back to the filesystem.  Without use of this call, there is no guarantee that changes are written back before munmap(2) is called.  To be more precise,  the  part  of the file that corresponds to the memory area starting at addr and having length length is updated.
