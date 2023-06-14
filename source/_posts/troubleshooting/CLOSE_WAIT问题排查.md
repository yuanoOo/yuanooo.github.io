---
title: 记一次大量TCP连接CLOSE_WAIT问题排查
tags:
  - 'Troubleshooting'
  - 'paimon'
categories:
  - [Troubleshooting]
top_img: 
date: 2023-06-11 17:57:25
updated: 2023-06-12 17:57:25
cover:
description:
keywords:
---

## 问题

今天突然发现Spark SQL任务启动不起来，报下面的错误，`'org.apache.spark.network.netty.NettyBlockTransferService' could not bind on a random free port. You may check whether configuring an appropriate binding address. 2023-05-18 13:57:40,952 WARN util.Utils: Service`，看到这段日志后，表明服务器大量端口被占用，Spark申请不到端口，尝试了100次后，抛出了下面的异常。

```
20/12/21 12:55:18 WARN Utils: Service 'org.apache.spark.network.netty.NettyBlockTransferService' could not bind on a random free port. You may check whether configuring an appropriate binding address.
20/12/21 12:55:18 ERROR CoarseGrainedExecutorBackend: Executor self-exiting due to : Unable to create executor due to Address already in use: Service 'org.apache.spark.network.netty.NettyBlockTransferService' failed after 100 retries (on a random free port)! Consider explicitly setting the appropriate binding address for the service 'org.apache.spark.network.netty.NettyBlockTransferService' (for example spark.driver.bindAddress for SparkDriver) to the correct binding address.
java.net.BindException: Address already in use: Service 'org.apache.spark.network.netty.NettyBlockTransferService' failed after 100 retries (on a random free port)! Consider explicitly setting the appropriate binding address for the service 'org.apache.spark.network.netty.NettyBlockTransferService' (for example spark.driver.bindAddress for SparkDriver) to the correct binding address.
	at sun.nio.ch.Net.bind0(Native Method)
	at sun.nio.ch.Net.bind(Net.java:433)
	at sun.nio.ch.Net.bind(Net.java:425)
	at sun.nio.ch.ServerSocketChannelImpl.bind(ServerSocketChannelImpl.java:223)
	at io.netty.channel.socket.nio.NioServerSocketChannel.doBind(NioServerSocketChannel.java:128)
	at io.netty.channel.AbstractChannel$AbstractUnsafe.bind(AbstractChannel.java:558)
	at io.netty.channel.DefaultChannelPipeline$HeadContext.bind(DefaultChannelPipeline.java:1283)
	at io.netty.channel.AbstractChannelHandlerContext.invokeBind(AbstractChannelHandlerContext.java:501)
	at io.netty.channel.AbstractChannelHandlerContext.bind(AbstractChannelHandlerContext.java:486)
	at io.netty.channel.DefaultChannelPipeline.bind(DefaultChannelPipeline.java:989)
	at io.netty.channel.AbstractChannel.bind(AbstractChannel.java:254)
	at io.netty.bootstrap.AbstractBootstrap$2.run(AbstractBootstrap.java:364)
	at io.netty.util.concurrent.AbstractEventExecutor.safeExecute(AbstractEventExecutor.java:163)
	at io.netty.util.concurrent.SingleThreadEventExecutor.runAllTasks(SingleThreadEventExecutor.java:403)
	at io.netty.channel.nio.NioEventLoop.run(NioEventLoop.java:463)
	at io.netty.util.concurrent.SingleThreadEventExecutor$5.run(SingleThreadEventExecutor.java:858)
	at io.netty.util.concurrent.DefaultThreadFactory$DefaultRunnableDecorator.run(DefaultThreadFactory.java:138)
	at java.lang.Thread.run(Thread.java:745)
End of LogType:stderr
```

## 排查

执行ss命令，发现大量连接处于**CLOSE_WAIT**，状态，这非常不正常。ESTABLISHED表示连接已被建立，可以通信了，大量连接处于**ESTABLISHED**状态才有可能正常。然后执行`netstat -na | awk '/^tcp/ {++S[$NF]} END {for(a in S) print a, S[a]}'`统计TCP连接状态，发现绝大部份的链接处于**CLOSE_WAIT**状态，这是非常不可思议情况。


### 第一步

执行`netstat -na | awk '/^tcp/ {++S[$NF]} END {for(a in S) print a, S[a]}'`统计TCP连接状态。

### 第二部

用`netstat -tnap`命令进行检查。

### 第三步：查看tcp队列当前情况
```sh
ss -lntp
State       Recv-Q Send-Q  Local Address:Port  Peer Address:Port             
LISTEN      101    100  
```

Recv-Q代表当前全连接队列的大小，也就是三次握手完成，目前在全连接队列中等待被应用程序accept的socket个数。

Send-Q代表全连接队列的最大值，应用程序可以在创建ServerSocket的时候指定，tomcat默认为100，但是这个值不能超过系统的/proc/sys/net/core/somaxconn，看看jdk中关于这个值的解释，专业名词叫backlog。

从上面的输出可以发现Recv-Q已经大于Send-Q，而且这个数量长时间不变，可以得出两个结论：

1.部分socket一直堆积在队列中没有被accept；

2.由于tcp全连接队列已满，所以新的socket自然是进不来了。



## 结论

服务端接口耗时较长，客户端主动断开了连接，此时，服务端就会出现 close_wait。

那怎么解决呢？看看代码为啥耗时长吧。

另外，如果代码不规范的话，说不定在收到对方发起的fin后，自己根本就不会给人家发fin。（比如netty自己开发的框架那种）

没啥好说的，检查自己的代码吧，反正close_wait基本就是自己这边的问题了。



### 补充TCP知识

![](https://raw.githubusercontent.com/yuanoOo/learngit/b6713af0a1b426be22a510bcd51cb0cddef43ea6/jpg/tcp01.jpeg)

用中文来描述下这个过程：

Client: `服务端大哥，我事情都干完了，准备撤了`，这里对应的就是客户端发了一个**FIN**

Server：`知道了，但是你等等我，我还要收收尾`，这里对应的就是服务端收到 **FIN** 后回应的 **ACK**

经过上面两步之后，服务端就会处于 **CLOSE_WAIT** 状态。过了一段时间 **Server** 收尾完了

Server：`小弟，哥哥我做完了，撤吧`，服务端发送了**FIN**

Client：`大哥，再见啊`，这里是客户端对服务端的一个 **ACK**

到此服务端就可以跑路了，但是客户端还不行。为什么呢？客户端还必须等待 **2MSL** 个时间，这里为什么客户端还不能直接跑路呢？主要是为了防止发送出去的 **ACK** 服务端没有收到，服务端重发 **FIN** 再次来询问，如果客户端发完就跑路了，那么服务端重发的时候就没人理他了。这个等待的时间长度也很讲究。

> **Maximum Segment Lifetime** 报文最大生存时间，它是任何报文在网络上存在的最长时间，超过这个时间报文将被丢弃

这里一定不要被图里的 **client／server** 和项目里的客户端服务器端混淆，你只要记住：主动关闭的一方发出 **FIN** 包（Client），被动关闭（Server）的一方响应 **ACK** 包，此时，被动关闭的一方就进入了 **CLOSE_WAIT** 状态。如果一切正常，稍后被动关闭的一方也会发出 **FIN** 包，然后迁移到 **LAST_ACK** 状态。

## Apache Paimon相关issue

https://github.com/apache/incubator-paimon/issues/1277

没有关闭`ParquetFileReader reader = getParquetReader(fileIO, path)`,导致TCP泄露，这种bug非常难以排查，需要对源码非常熟悉。

paimon-format/src/main/java/org/apache/paimon/format/parquet/ParquetUtil.java

```java
    public static Map<String, Statistics<?>> extractColumnStats(FileIO fileIO, Path path)
            throws IOException {
        ParquetMetadata parquetMetadata = getParquetReader(fileIO, path).getFooter();
        List<BlockMetaData> blockMetaDataList = parquetMetadata.getBlocks();
        Map<String, Statistics<?>> resultStats = new HashMap<>();
        for (BlockMetaData blockMetaData : blockMetaDataList) {
            List<ColumnChunkMetaData> columnChunkMetaDataList = blockMetaData.getColumns();
            for (ColumnChunkMetaData columnChunkMetaData : columnChunkMetaDataList) {
                Statistics<?> stats = columnChunkMetaData.getStatistics();
                String columnName = columnChunkMetaData.getPath().toDotString();
                Statistics<?> midStats;
                if (!resultStats.containsKey(columnName)) {
                    midStats = stats;
                } else {
                    midStats = resultStats.get(columnName);
                    midStats.mergeStatistics(stats);
        try (ParquetFileReader reader = getParquetReader(fileIO, path)) {
            ParquetMetadata parquetMetadata = reader.getFooter();
            List<BlockMetaData> blockMetaDataList = parquetMetadata.getBlocks();
            Map<String, Statistics<?>> resultStats = new HashMap<>();
            for (BlockMetaData blockMetaData : blockMetaDataList) {
                List<ColumnChunkMetaData> columnChunkMetaDataList = blockMetaData.getColumns();
                for (ColumnChunkMetaData columnChunkMetaData : columnChunkMetaDataList) {
                    Statistics<?> stats = columnChunkMetaData.getStatistics();
                    String columnName = columnChunkMetaData.getPath().toDotString();
                    Statistics<?> midStats;
                    if (!resultStats.containsKey(columnName)) {
                        midStats = stats;
                    } else {
                        midStats = resultStats.get(columnName);
                        midStats.mergeStatistics(stats);
                    }
                    resultStats.put(columnName, midStats);
                }
                resultStats.put(columnName, midStats);
            }
            return resultStats;
        }
        return resultStats;
    }

```

