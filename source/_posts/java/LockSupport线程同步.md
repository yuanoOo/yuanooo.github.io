---
title: 基于LockSupport进行线程间的同步
tags:
  - 'Threads'
categories:
  - [Java]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2022-12-31 21:07:13
updated: 2022-12-31 21:07:13
cover:
description:
keywords:
---

## 描述

看到一道有意思的Java多线程面试题：要求两个线程交替打印a和b，且都打印50次，且a必须先打印。

这是一个关于线程同步的问题，显然有比较多的解法，比如利用synchronized、CyclicBarrier等来实现。下面是利用LockSupport的代码。

```java
/**
 * 要求两个线程交替打印a和b，且都打印50次，且a必须先打印。
 * 实现两个线程之间的同步
 */
public class LockSupportDemo {

    public static void main(String[] args) throws InterruptedException {
        Thread[] threads = new Thread[2];

        threads[0] = new Thread(() -> {
            int i = 51;
            while (i-- > 1) {
                System.out.printf("%s %d---> %s%n", Thread.currentThread().getName(), i, 'a');
                // 先释放b线程，然后阻塞a线程，否则a线程直接阻塞，无法向下执行
                LockSupport.unpark(threads[1]);
                LockSupport.park();
            }

        });

        threads[1] = new Thread(() -> {

            int i = 51;
            while (i-- > 1) {
                // 先阻塞次线程，防止此线程先打印出b
                LockSupport.park();
                System.out.printf("%s %d---> %s%n", Thread.currentThread().getName(), i, 'b');
                LockSupport.unpark(threads[0]);
            }
        });

        Arrays.stream(threads).forEach(Thread::start);
        Thread.currentThread().join(1_000L);
    }
}

```

