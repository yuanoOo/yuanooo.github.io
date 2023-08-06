---
title: Netty与Reactor模型
tags:
  - Netty
categories:
  - - Netty
abbrlink: 22006
date: 2022-11-29 19:35:27
updated: 2022-11-29 19:35:27
cover:
top_img:
description:
keywords:
---

> Netty is *an asynchronous event-driven network application framework* for rapid development of maintainable high performance protocol servers & clients.

## 基本概念：

- 1、Netty是对JDK NIO进行的一系列封装，使得更容易更快速的编写出高性能的安全的网络应用程序。

- 2、Java NIO与BIO一个重要的不同点是非阻塞，在Linux中，Java NIO依赖于Linux的epoll实现.

- 3、epoll是Linux中的专有名词或实现：epoll是一种I/O事件通知机制，是linux 内核实现IO多路复用的一个实现。

  > Linu主要通过暴漏三个系统调用供上层应用使用epoll：int epoll_create(int size)、 int epoll_ctl(int epfd， int op， int fd， struct epoll_event *event)、int epoll_wait(int epfd， struct epoll_event *events， int maxevents， int timeout);
  >
  > 
  >
  > IO多路复用是指，在一个操作里同时监听多个输入输出源，在其中一个或多个输入输出源可用的时候返回，然后对其的进行读写操作。



## Reactor模型

> NIO 服务端编程采用的是 Reactor 模式（也叫做 Dispatcher 模式，分派模式），Reactor 模式有两个要义：
>
> 1）基于 IO 多路复用技术，多个连接共用一个多路复用器，应用程序的线程无需阻塞等待所有连接，只需阻塞等待多路复用器即可。当某个连接上有新数据可以处理时，应用程序的线程从阻塞状态返回，开始处理这个连接上的业务。
>
> 2）基于线程池技术复用线程资源，不必为每个连接创建专用的线程，应用程序将连接上的业务处理任务分配给线程池中的线程进行处理，一个线程可以处理多个连接的业务。

### 主从 Reactor 多线程模式

针对单 Reactor 多线程模型中，Reactor 在单个线程中运行，面对高并发的场景易成为性能瓶颈的缺陷，主从 Reactor 多线程模式让 Reactor 在多个线程中运行（分成 MainReactor 线程与 SubReactor 线程）。这种模式的基本工作流程为：

- 1）Reactor 主线程 MainReactor 对象通过 select 监听客户端连接事件，收到事件后，通过 Acceptor 处理客户端连接事件。
- 2）当 Acceptor 处理完客户端连接事件之后（与客户端建立好 Socket 连接），MainReactor 将连接分配给 SubReactor。（即：MainReactor 只负责监听客户端连接请求，和客户端建立连接之后将连接交由 SubReactor 监听后面的 IO 事件。）
- 3）SubReactor 将连接加入到自己的连接队列进行监听，并创建 Handler 对各种事件进行处理。
- 4）当连接上有新事件发生的时候，SubReactor 就会调用对应的 Handler 处理。
- 5）Handler 通过 read 从连接上读取请求数据，将请求数据分发给 Worker 线程池进行业务处理。
- 6）Worker 线程池会分配独立线程来完成真正的业务处理，并将处理结果返回给 Handler。Handler 通过 send 向客户端发送响应数据。
- 7）一个 MainReactor 可以对应多个 SubReactor，即一个 MainReactor 线程可以对应多个 SubReactor 线程。

这种模式的优点是：

- 1）MainReactor 线程与 SubReactor 线程的数据交互简单职责明确，MainReactor 线程只需要接收新连接，SubReactor 线程完成后续的业务处理。
- 2）MainReactor 线程与 SubReactor 线程的数据交互简单， MainReactor 线程只需要把新连接传给 SubReactor 线程，SubReactor 线程无需返回数据。
- 3）多个 SubReactor 线程能够应对更高的并发请求。

这种模式的缺点是编程复杂度较高。但是由于其优点明显，在许多项目中被广泛使用，包括 Nginx、Memcached、Netty 等。

这种模式也被叫做服务器的 1+M+N 线程模式，即使用该模式开发的服务器包含一个（或多个，1 只是表示相对较少）连接建立线程+M 个 IO 线程+N 个业务处理线程。这是业界成熟的服务器程序设计模式。

![img](https://cdn.nlark.com/yuque/0/2023/png/2500465/1673152576136-995fd1ff-596e-4fb3-ba45-f0e4d1acb066.png)



![img](https://cdn.nlark.com/yuque/0/2023/png/2500465/1673152583079-a32e69fe-81e7-40a3-9858-74322d9839e6.png)

### Netty 的模样

Netty 的设计主要基于主从 Reactor 多线程模式，并做了一定的改进。本节将使用一种渐进式的描述方式展示 Netty 的模样，即先给出 Netty 的简单版本，然后逐渐丰富其细节，直至展示出 Netty 的全貌。

简单版本的 Netty 的模样如下：

![img](https://cdn.nlark.com/yuque/0/2023/png/2500465/1673152847905-7f0fdd30-a8f1-40e9-92ed-5bea54a51e78.png)

![img](https://cdn.nlark.com/yuque/0/2023/png/2500465/1673152884186-ed746066-7cfd-4cab-a58a-ca42eed7e0c1.png)

![img](https://cdn.nlark.com/yuque/0/2023/png/2500465/1673153242717-36ef2c61-2c76-4aae-9480-d2b5a5324778.png)

关于这张图，作以下几点说明：

- 1）Netty 抽象出两组线程池：BossGroup 和 WorkerGroup，也可以叫做 BossNioEventLoopGroup 和 WorkerNioEventLoopGroup。每个线程池中都有 NioEventLoop 线程。BossGroup 中的线程专门负责和客户端建立连接，WorkerGroup 中的线程专门负责处理连接上的读写。BossGroup 和 WorkerGroup 的类型都是 NioEventLoopGroup。
- 2）NioEventLoopGroup 相当于一个事件循环组，这个组中含有多个事件循环，每个事件循环就是一个 NioEventLoop。
- 3）NioEventLoop 表示一个不断循环的执行事件处理的线程，每个 NioEventLoop 都包含一个 Selector，用于监听注册在其上的 Socket 网络连接（Channel）。
- 4）NioEventLoopGroup 可以含有多个线程，即可以含有多个 NioEventLoop。
- 5）每个 BossNioEventLoop 中循环执行以下三个步骤：
- 5.1）**select**：轮训注册在其上的 ServerSocketChannel 的 accept 事件（OP_ACCEPT 事件）
- 5.2）**processSelectedKeys**：处理 accept 事件，与客户端建立连接，生成一个 NioSocketChannel，并将其注册到某个 WorkerNioEventLoop 上的 Selector 上
- 5.3）**runAllTasks**：再去以此循环处理任务队列中的其他任务
- 6）每个 WorkerNioEventLoop 中循环执行以下三个步骤：
- 6.1）**select**：轮训注册在其上的 NioSocketChannel 的 read/write 事件（OP_READ/OP_WRITE 事件）
- 6.2）**processSelectedKeys**：在对应的 NioSocketChannel 上处理 read/write 事件
- 6.3）**runAllTasks**：再去以此循环处理任务队列中的其他任务
- 7）在以上两个**processSelectedKeys**步骤中，会使用 Pipeline（管道），Pipeline 中引用了 Channel，即通过 Pipeline 可以获取到对应的 Channel，Pipeline 中维护了很多的处理器（拦截处理器、过滤处理器、自定义处理器等）。这里暂时不详细展开讲解 Pipeline。

![img](https://cdn.nlark.com/yuque/0/2023/png/2500465/1673163809861-7044728c-de2f-4a93-9d19-062318927467.png)