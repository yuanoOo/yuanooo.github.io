---
title: Flink调优
tags:
  - 'Flink'
categories:
  - [bigdata,Flink]
top_img: '/img/bg/banner.gif'
date: 2022-08-08 20:23:04
updated: 2022-08-08 20:23:04
cover:
description:
keywords:
---

# 内存设置（1CPU配置4G内存）

> bin/flink run \
>
> -t yarn-per-job \
>
> -d \
>
> -p 5 \ 指定并行度
>
> -Dyarn.application.queue=test \ 指定yarn队列
>
> -Djobmanager.memory.process.size=2048mb \ JM2~4G足够
>
> -Dtaskmanager.memory.process.size=6144mb \ 单个TM2~8G足够
>
> -Dtaskmanager.numberOfTaskSlots=2 \ **与容器核数1core：1slot或1core：2slot**
>
> -c com.atguigu.app.dwd.LogBaseApp \
>
> /opt/module/gmall-flink/gmall-realtime-1.0-SNAPSHOT-jar-with-dependencies.jar

Flink是实时流处理，关键在于资源情况能不能抗住高峰时期每秒的数据量，通常用QPS/TPS来描述数据情况。

##  TaskManager 内存模型  

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654665961981-86c260ab-5310-4674-ac61-6a1d1f738f18.png)

### 1、内存模型详解

#### JVM 特定内存：JVM 本身使用的内存，包含 JVM 的 metaspace 和 over-head

1）JVMmetaspace：JVM 元空间

taskmanager.memory.jvm-metaspace.size，默认 256mb



2）JVMover-head执行开销：JVM执行时自身所需要的内容，包括线程堆栈、IO、编译缓存等所使用的内存。

taskmanager.memory.jvm-overhead.fraction，默认 0.1

taskmanager.memory.jvm-overhead.min，默认 192mb

taskmanager.memory.jvm-overhead.max，默认 1gb



**总进程内存\*fraction，如果小于配置的 min（或大于配置的 max）大小，则使用 min/max**

**大小**



#### 框架内存：Flink 框架，即 TaskManager 本身所占用的内存，不计入 Slot 的资源中。

堆内：taskmanager.memory.framework.heap.size，默认 128MB

堆外：taskmanager.memory.framework.off-heap.size，默认 128MB

#### Task内存：Task执行用户代码时所使用的内存

堆内：taskmanager.memory.task.heap.size，默认 none，由 Flink 内存扣除掉其他部分的内存得到。

堆外：taskmanager.memory.task.off-heap.size，默认 0，表示不使用堆外内存

#### 网络内存：网络数据交换所使用的堆外内存大小，如网络数据交换缓冲区

**堆外：**

taskmanager.memory.network.fraction，默认 0.1

taskmanager.memory.network.min，默认 64mb

taskmanager.memory.network.max，默认 1gb

**Flink 内存\*fraction，如果小于配置的 min（或大于配置的 max）大小，则使用 min/max大小**

  

#### 托管内存：用于 RocksDBStateBackend 的本地内存和批的排序、哈希表、缓存中间结果。

堆外：taskmanager.memory.managed.fraction，默认 0.4

taskmanager.memory.managed.size，默认 none

**如果 size 没指定，则等于 Flink 内存\*fraction**

## 2、案例分析  

基于Yarn模式，一般参数指定的是总进程内存，taskmanager.memory.process.size，比如指定为 4G，每一块内存得到大小如下：

（1）计算 Flink 内存

JVM 元空间 256m

JVM 执行开销： 4g*0.1=409.6m，在[192m,1g]之间，最终结果 409.6m

Flink 内存=4g-256m-409.6m=3430.4m

（2）网络内存=3430.4m*0.1=343.04m，在[64m,1g]之间，最终结果 343.04m

（3）托管内存=3430.4m*0.4=1372.16m

（4）框架内存，堆内和堆外都是 128m

（5）Task堆内内存=3430.4m-128m-128m-343.04m-1372.16m=1459.2m

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654667261844-9b48b348-1bcb-4ca8-b556-f63a3680cf83.png)

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654667279269-d43c4812-9561-433a-83fe-a8d70b5fb5b9.png)

### 所以进程内存给多大，每一部分内存需不需要调整，可以看内存的使用率来调整。

## 合理利用 cpu 资源

Yarn 的**容量调度器**默认情况下是使用“DefaultResourceCalculator”分配策略，只根据内存调度资源，所以在 Yarn 的资源管理页面上看到每个容器的 vcore 个数还是 1。

可以修改策略为 DominantResourceCalculator，该资源计算器在计算资源的时候会综合考虑 cpu 和内存的情况。在capacity-scheduler.xml 中修改属性:

```xml
<property>
  <name>yarn.scheduler.capacity.resource-calculator</name>
  <!-- <value>org.apache.hadoop.yarn.util.resource.DefaultResourceCalculator</value> -->
  <value>org.apache.hadoop.yarn.util.resource.DominantResourceCalculator</value>
</property>
```

### 1.1.1    使用DefaultResourceCalculator 策略

```shell
bin/flink run \
-t yarn-per-job \
-d \
-p 5 \
-Drest.flamegraph.enabled=true \
-Dyarn.application.queue=test \
-Djobmanager.memory.process.size=1024mb \
-Dtaskmanager.memory.process.size=4096mb \
-Dtaskmanager.numberOfTaskSlots=2 \
-c com.atguigu.flink.tuning.UvDemo \
/opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar
```

可以看到一个容器只有一个 vcore：

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654668251950-033e4bc0-4b65-4fe8-b309-45a29956922b.png)

### 1.1.2    使用DominantResourceCalculator 策略

修改后 yarn 配置后，分发配置并重启 yarn，再次提交 flink 作业：

> bin/flinkrun\
>
> -tyarn-per-job\
>
> -d\
>
> -p5\
>
> -Drest.flamegraph.enabled=true\
>
> -Dyarn.application.queue=test\
>
> -Djobmanager.memory.process.size=1024mb \
>
> -Dtaskmanager.memory.process.size=4096mb\
>
> -Dtaskmanager.numberOfTaskSlots=2\
>
> -ccom.atguigu.flink.tuning.UvDemo\
>
> /opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar

看到容器的 vcore 数变了:

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654668344371-82744e2d-89b2-4fab-8a09-f77475df1088.png)

JobManager1 个，占用 1 个容器，vcore=1

TaskManager3 个，占用 3 个容器，每个容器 vcore=2，总 vcore=2*3=6，因为默认单个容器的 vcore 数=单 TM 的slot 数

### 1.1.3    使用 DominantResourceCalculator 策略并指定容器**vcore 数**

指定yarn 容器的 vcore 数，提交：

> bin/flinkrun\
>
> -tyarn-per-job\
>
> -d\
>
> -p5\
>
> -Drest.flamegraph.enabled=true\
>
> -Dyarn.application.queue=test\
>
> -Dyarn.containers.vcores=3\
>
>  -Djobmanager.memory.process.size=1024mb \ -Dtaskmanager.memory.process.size=4096mb \ -Dtaskmanager.numberOfTaskSlots=2 \ -c com.atguigu.flink.tuning.UvDemo \ /opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar  

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654668509233-7292aa6f-0e54-4799-ba38-ab72659ef824.png)

JobManager1 个，占用 1 个容器，vcore=1

TaskManager3 个，占用 3 个容器，每个容器vcore =3，总 vcore=3*3=9

# RocksDB大状态调优

RocksDB 是基于 LSM Tree 实现的（类似HBase），写数据都是先缓存到内存中，所以RocksDB 的写请求效率比较高。RocksDB 使用内存结合磁盘的方式来存储数据，每次获取数据时，先从内存中 blockcache 中查找，如果内存中没有再去磁盘中查询。优化后差不多单并行度 TPS 5000 record/s。**使用RocksDB 时，状态大小仅受可用磁盘空间量的限制，性能瓶颈主要在于 RocksDB对磁盘的读请求，每次读写操作都必须对数据进行反序列化或者序列化。**所以当处理性能不够时，仅需要横向扩展并行度即可提高整个Job 的吞吐量。

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654669015363-a35261ab-d4ff-4068-a013-eecfe78a5c7d.png)



从 Flink1.10 开始，Flink 默认将 RocksDB 的内存大小配置为每个 taskslot 的托管内存。调试内存性能的问题主要是通过调整配置项 taskmanager.memory.managed.size或者 taskmanager.memory.managed.fraction以增加 Flink 的托管内存(即堆外的托管内存)。进一步可以调整一些参数进行高级性能调优，这些参数也可以在应用程序中通过RocksDBStateBackend.setRocksDBOptions(RocksDBOptionsFactory)指定。下面介绍

提高资源利用率的几个重要配置：

### 2.1.1   开启State访问性能监控

Flink 1.13 中引入了 State 访问的性能监控，即 latency trackig state。此功能不局限于 StateBackend 的类型，自定义实现的 StateBackend 也可以复用此功能。

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654670053632-0e169f44-1340-4202-ab6a-bd9a6173a14a.png)

State访问性能监控会产生一定的性能影响，所以，默认每 100次做一次取样(sample)，对不同的 StateBackend 性能损失影响不同：

- 对于 RocksDBStateBackend，性能损失大概在 1% 左右
- 对于 HeapStateBackend，性能损失最多可达 10%

```yaml
state.backend.latency-track.keyed-state-enabled：true #启用访问状态的性能监控 
state.backend.latency-track.sample-interval: 100 #采样间隔 
state.backend.latency-track.history-size: 128 #保留的采样数据个数，越大越精确 
state.backend.latency-track.state-name-as-variable: true #将状态名作为变量  
```

正常开启第一个参数即可。

> bin/flink run \
>
> -t yarn-per-job \
>
> -d \
>
> -p 5 \
>
> -Drest.flamegraph.enabled=true \
>
> -Dyarn.application.queue=test \
>
> -Djobmanager.memory.process.size=1024mb \
>
> -Dtaskmanager.memory.process.size=4096mb \
>
> -Dtaskmanager.numberOfTaskSlots=2 \
>
>  -Dstate.backend.latency-track.keyed-state-enabled=true \ 
>
> -c com.atguigu.flink.tuning.RocksdbTuning \ /opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar  

### 2.1.2    开启增量检查点和本地恢复

1）开启增量检查点

RocksDB 是目前唯一可用于支持有状态流处理应用程序增量检查点的状态后端，可以修改参数开启增量检查点：

state.backend.incremental: true #默认 false，改为 true。 

或代码中指定 new EmbeddedRocksDBStateBackend(true)  

2）开启本地恢复

当 Flink任务失败时，可以基于本地的状态信息进行恢复任务，可能不需要从 hdfs拉取数据。本地恢复目前仅涵盖键控类型的状态后端（RocksDB），MemoryStateBackend不支持本地恢复并忽略此选项。

state.backend.local-recovery:true

### 2.1.3    调整预定义选项

Flink针对不同的设置为 RocksDB提供了一些预定义的选项集合,其中包含了后续提到的一些参数，如果调整预定义选项后还达不到预期，再去调整后面的 block、writebuffer等参数。

当 前 支 持 的 预 定 义 选 项 有   DEFAULT 、 SPINNING_DISK_OPTIMIZED 、

SPINNING_DISK_OPTIMIZED_HIGH_MEM 或FLASH_SSD_OPTIMIZED。有条件上 SSD

的，可以指定为 FLASH_SSD_OPTIMIZED

 state.backend.rocksdb.predefined-options： SPINNING_DISK_OPTIMIZED_HIGH_MEM #设置为机械硬盘+内存模式  

### 2.1.4    增大 block 缓存

整个 RocksDB 共享一个 blockcache，读数据时内存的 cache 大小，该参数越大读

数据时缓存命中率越高，默认大小为8MB，建议设置到64~256MB。

state.backend.rocksdb.block.cache-size:64m     #默认8m  

### 2.1.5    增大writebuffer 和 level 阈值大小

RocksDB 中，每个 State 使用一个 ColumnFamily，每个 ColumnFamily 使用独占的 writebuffer，默认 64MB，建议调大。

调整这个参数通常要适当增加 L1层的大小阈值 max-size-level-base，默认 256m。

该值太小会造成能存放的 SST 文件过少，层级变多造成查找困难，太大会造成文件过多，合并困难。建议设为 target_file_size_base（默认 64MB） 的倍数，且不能太小，例如 5~10倍，即 320~640MB。

state.backend.rocksdb.writebuffer.size: 128m

state.backend.rocksdb.compaction.level.max-size-level-base:320m   

### 2.1.6    增大write buffer 数量

每个 ColumnFamily对应的 writebuffer 最大数量，这实际上是内存中“只读内存表“的最大数量，默认值是 2。对于机械磁盘来说，如果内存足够大，可以调大到 5左右

state.backend.rocksdb.writebuffer.count:5                                                                     

### 2.1.7    增大后台线程数和writebuffer 合并数

1）增大线程数

用于后台 flush和合并 sst文件的线程数，默认为 1，建议调大，机械硬盘用户可以改为 4等更大的值

state.backend.rocksdb.thread.num: 4                                                                             

2）增大writebuffer 最小合并数

将数据从 writebuffer 中 flush 到磁盘时，需要合并的 writebuffer 最小数量，默认

值为 1，可以调成 3。

state.backend.rocksdb.writebuffer.number-to-merge:3                                             

### 2.1.8    开启分区索引功能

Flink1.13 中对 RocksDB 增加了分区索引功能，复用了 RocksDB 的partitionedIndex&filter 功能，简单来说就是对 RocksDB 的 partitionedIndex 做了多级索引。也就是将内存中的最上层常驻，下层根据需要再 load回来，这样就大大降低了数据 Swap竞争。线上测试中，相对于**内存比较小**的场景中，性能提升 10 倍左右。如果在内存管控下 Rocksdb 性能不如预期的话，这也能成为一个性能优化点。

state.backend.rocksdb.memory.partitioned-index-filters:true   #默认false                



**2.1.9**    **参数设定案例**

```sh
bin/flinkrun\
-tyarn-per-job\
-d\
-p5\
-Drest.flamegraph.enabled=true\
-Dyarn.application.queue=test\
-Djobmanager.memory.process.size=1024mb \
-Dtaskmanager.memory.process.size=4096mb\
-Dtaskmanager.numberOfTaskSlots=2\
-Dstate.backend.incremental=true\
-Dstate.backend.local-recovery=true\
-Dstate.backend.rocksdb.predefined-options=SPINNING_DISK_OPTIMIZED_HIGH_MEM\
-Dstate.backend.rocksdb.block.cache-size=64m\
-Dstate.backend.rocksdb.writebuffer.size=128m\
-Dstate.backend.rocksdb.compaction.level.max-size-level-base=320m\
-Dstate.backend.rocksdb.writebuffer.count=5 \
-Dstate.backend.rocksdb.thread.num=4\
-Dstate.backend.rocksdb.writebuffer.number-to-merge=3\
-Dstate.backend.rocksdb.memory.partitioned-index-filters=true\
-Dstate.backend.latency-track.keyed-state-enabled=true\
-ccom.atguigu.flink.tuning.RocksdbTuning\
/opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar
```



### 设置本地 RocksDB 多目录

在flink-conf.yaml 中配置：

```plain
state.backend.rocksdb.localdir: /data1/flink/rocksdb,/data2/flink/rocksdb,/data3/flink/rocksdb
```



注意：不要配置单块磁盘的多个目录，务必将目录配置到多块不同的磁盘上，让多块磁盘来分担压力。**当设置多个 RocksDB 本地磁盘目录时，Flink 会****随机选择****要使用的目录，所以就可能存在三个并行度共用同一目录的情况。**如果服务器磁盘数较多，一般不会出现该情况，但是如果任务重启后吞吐量较低，可以检查是否发生了多个并行度共用同一块磁盘的情况。

**当一个 TaskManager 包含 3 个 slot 时，那么单个服务器上的三个并行度都对磁盘造成频繁读写，从而导致三个并行度的之间相互争抢同一个磁盘 io，这样务必导致三个并行度的吞吐量都会下降。设置多目录实现三个并行度使用不同的硬盘从而减少资源竞争。**

如下所示是测试过程中磁盘的 IO 使用率，可以看出三个大状态算子的并行度分别对应了三块磁盘，这三块磁盘的 IO 平均使用率都保持在 45% 左右，IO 最高使用率几乎都是 100%，而其他磁盘的 IO 平均使用率相对低很多。**由此可见使用 RocksDB 做为状态后端且有大状态的频繁读取时， 对磁盘IO性能消耗确实比较大。**

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654662632337-7fe1e6c6-5fe2-412e-82e8-77f3c81458b7.png)

如下图所示，其中两个并行度共用了 sdb 磁盘，一个并行度使用 sdj磁盘。可以看到 sdb 磁盘的 IO 使用率已经达到了 91.6%，就会导致 sdb 磁盘对应的两个并行度吞吐量大大降低，从而使得整个 Flink 任务吞吐量降低。**如果每个服务器上有一两块 SSD，强烈建议将 RocksDB 的本地磁盘目录配置到 SSD 的目录下**，**从 HDD 改为 SSD 对于性能的提升可能比配置 10 个优化参数更有效。**

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654662673431-6575b710-490c-49c4-bec7-f4b7964b3fc7.png)

- **state.backend.incremental：**开启增量检查点，默认false，改为true。
- **state.backend.rocksdb.predefined-options：**SPINNING_DISK_OPTIMIZED_HIGH_MEM设置为机械硬盘+内存模式，有条件上SSD，指定为FLASH_SSD_OPTIMIZED
- **state.backend.rocksdb.block.cache-size**: 整个 RocksDB 共享一个 block cache，读数据时内存的 cache 大小，该参数越大读数据时缓存命中率越高，默认大小为 8 MB，建议设置到 64 ~ 256 MB。
- **state.backend.rocksdb.thread.num**: 用于后台 flush 和合并 sst 文件的线程数，默认为 1，建议调大，机械硬盘用户可以改为 4 等更大的值。
- **state.backend.rocksdb.writebuffer.size**: RocksDB 中，每个 State 使用一个 Column Family，每个 Column Family 使用独占的 write buffer，建议调大，例如：32M
- **state.backend.rocksdb.writebuffer.count**: 每个 Column Family 对应的 writebuffer 数目，默认值是 2，对于机械磁盘来说，如果内存⾜够大，可以调大到 5 左右
- **state.backend.rocksdb.writebuffer.number-to-merge**: 将数据从 writebuffer 中 flush 到磁盘时，需要合并的 writebuffer 数量，默认值为 1，可以调成3。
- **state.backend.local-recovery**: 设置本地恢复，当 Flink 任务失败时，可以基于本地的状态信息进行恢复任务，可能不需要从 hdfs 拉取数据

## Checkpoint设置

一般我们的 Checkpoint 时间间隔可以设置为分钟级别（1~5分钟），例如 1 分钟、3 分钟，对于状态很大的任务每次 Checkpoint 访问 HDFS 比较耗时，可以设置为 5~10 分钟一次Checkpoint，并且调大两次 Checkpoint 之间的暂停间隔，例如设置两次Checkpoint 之间至少暂停 4或8 分钟。

同时，也需要考虑时效性的要求,需要在时效性和性能之间做一个平衡，如果时效性要求高，结合 end- to-end 时长，设置秒级或毫秒级。

如果 Checkpoint 语义配置为 EXACTLY_ONCE，那么在 Checkpoint 过程中还会存在 barrier 对齐的过程，可以通过 Flink Web UI 的 Checkpoint 选项卡来查看 Checkpoint 过程中各阶段的耗时情况，从而确定到底是哪个阶段导致 Checkpoint 时间过长然后针对性的解决问题。

RocksDB相关参数在1.3中已说明，可以在flink-conf.yaml指定，也可以在Job的代码中调用API单独指定，这里不再列出。

```scala
// 使⽤ RocksDBStateBackend 做为状态后端，并开启增量 Checkpoint
RocksDBStateBackend rocksDBStateBackend = new RocksDBStateBackend("hdfs://hadoop102:8020/flink/checkpoints", true);
env.setStateBackend(rocksDBStateBackend);

// 开启Checkpoint，间隔为 3 分钟
env.enableCheckpointing(TimeUnit.MINUTES.toMillis(3));
// 配置 Checkpoint
CheckpointConfig checkpointConf = env.getCheckpointConfig();
checkpointConf.setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE)
// 最小间隔 4分钟
checkpointConf.setMinPauseBetweenCheckpoints(TimeUnit.MINUTES.toMillis(4))
// 超时时间 10分钟
checkpointConf.setCheckpointTimeout(TimeUnit.MINUTES.toMillis(10));
// 保存checkpoint
checkpointConf.enableExternalizedCheckpoints(
CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION);
```

# 反压处理

## 3.1 概述

Flink 网络流控及反压的介绍：

https://flink-learning.org.cn/article/detail/138316d1556f8f9d34e517d04d670626

### 3.1.1    反压的理解

简单来说，Flink 拓扑中每个节点（Task）间的数据都以阻塞队列的方式传输，下游来不及消费导致队列被占满后，上游的生产也会被阻塞，最终导致数据源的摄入被阻塞。

反压（BackPressure）通常产生于这样的场景：短时间的负载高峰导致系统接收数据的速率远高于它处理数据的速率。许多日常问题都会导致反压，例如，垃圾回收停顿可能会导致流入的数据快速堆积，或遇到大促、秒杀活动导致流量陡增。

### 3.1.2    反压的危害

反压如果不能得到正确的处理，可能会影响到 checkpoint时长和 state大小，甚至可能会导致资源耗尽甚至系统崩溃。

- 1）影响 checkpoint 时长：barrier 不会越过普通数据，数据处理被阻塞也会导致checkpointbarrier 流经整个数据管道的时长变长，导致 checkpoint 总体时间（End toEndDuration）变长。
- 2）影响 state 大小：barrier 对齐时，接受到较快的输入管道的 barrier 后，它后面数据会被缓存起来但不处理，直到较慢的输入管道的 barrier 也到达，这些被缓存的数据会被放到 state 里面，导致 checkpoint 变大。

这两个影响对于生产环境的作业来说是十分危险的，因为 checkpoint 是保证数据一致性的关键，checkpoint 时间变长有可能导致 checkpoint**超时失败**，而 state 大小同样可能拖慢 checkpoint 甚至导致 **OOM**（使用 Heap-basedStateBackend）或者物理内存使用**超出容器资源**（使用 RocksDBStateBackend）的稳定性问题。

**因此，我们在生产中要尽量避免出现反压的情况。**

## 3.2 定位反压节点

解决反压首先要做的是定位到造成反压的节点，排查的时候，先把operatorchain 禁用，方便定位到具体算子。



提交UvDemo:

> bin/flinkrun\
>
> -tyarn-per-job\
>
> -d\
>
> -p5 \
>
> -Drest.flamegraph.enabled=true\
>
> -Dyarn.application.queue=test\
>
> -Djobmanager.memory.process.size=1024mb \
>
> -Dtaskmanager.memory.process.size=2048mb\
>
> -Dtaskmanager.numberOfTaskSlots=2\
>
> -ccom.atguigu.flink.tuning.UvDemo \
>
> /opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar

### 3.2.1    利用 FlinkWebUI 定位

FlinkWebUI 的反压监控提供了 SubTask 级别的反压监控，1.13 版本以前是通过周期性对  Task  线程的栈信息采样，得到线程被阻塞在请求  Buffer（意味着被下游队列阻塞）

的频率来判断该节点是否处于反压状态。默认配置下，这个频率在 0.1以下则为 OK，0.1

至 0.5为 LOW，而超过 0.5则为 HIGH。

Flink1.13 优化了反压检测的逻辑（使用基于任务 Mailbox计时，而不在再于堆栈采样），并且重新实现了作业图的 UI展示：Flink现在在 UI 上通过颜色和数值来展示繁忙和反压的程度。

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654674284140-b680f841-3ad4-4250-87fd-8c331333f1f5.png)

1）通过WebUI看到 Map算子处于反压：

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654674446026-5ec8c33c-cadc-44c9-9d00-b644899f52d6.png)

3）分析瓶颈算子

如果处于反压状态，那么有两种可能性：

（1）  该节点的发送速率跟不上它的产生数据速率。这一般会发生在一条输入多条输出的 Operator（比如 flatmap）。这种情况，该节点是反压的根源节点，它是从 SourceTask到 Sink Task 的第一个出现反压的节点。**（很少出现，表现为：反压算子一进多出，后面的算子处理速度慢，从这个反压算子开始，后面的算子都反压了。图示，绿色为反压节点：**

**（OK-> OK->** **反** **->反 -> 反 ）**

**一进多出，输入缓存区使用率可能高也可能低，输出缓存区使用率高**

（2）  下游的节点接受速率较慢，通过反压机制限制了该节点的发送速率。这种情况，需要继续排查下游节点，一直找到第一个为OK的一般就是根源节点。**（表现为：这个反压算子处理速度慢，阻塞了前面的算子，导致前面的算子反压了，其后面的算子表现为不反压。图示，绿色为反压节点：**

​      **（反 -> 反 ->** **OK**-> OK-> OK）

**输入缓存区使用率高，输出缓存区使用率低**

总体来看，如果我们找到第一个出现反压的节点，反压根源要么是就这个节点，要么是它紧接着的下游节点。

通常来讲，第二种情况更常见。如果无法确定，还需要结合 Metrics进一步判断。

### 3.2.2    利用 Metrics 定位

监控反压时会用到的 Metrics 主要和 Channel 接受端的 Buffer 使用率有关，最为

有用的是以下几个 Metrics:

| **Metris**                        | **描述**                        |
| --------------------------------- | ------------------------------- |
| outPoolUsage                      | 发送端 Buffer 的使用率          |
| inPoolUsage                       | 接收端 Buffer 的使用率          |
| floatingBuffersUsage（1.9 以上）  | 接收端 FloatingBuffer 的使用率  |
| exclusiveBuffersUsage（1.9 以上） | 接收端 ExclusiveBuffer 的使用率 |

其中 inPoolUsage = floatingBuffersUsage + exclusiveBuffersUsage。

#### 1）根据指标分析反压

分析反压的大致思路是：如果一个 Subtask 的发送端 Buffer占用率很高，则表明它被下游反压限速了；如果一个 Subtask 的接受端 Buffer 占用很高，则表明它将反压传导至上游。反压情况可以根据以下表格进行对号入座(1.9 以上):

|                                            | **outPoolUsage** **低**                                      | **outPoolUsage** **高**                    |
| ------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------ |
| **inPoolUsage** **低**                     | 正常                                                         | 被下游反压，处于临时情况（还没传递到上游） |
| 可能是反压的根源，一条输入多条输出的场景   |                                                              |                                            |
| **inPoolUsage** **高**                     | 如果上游所有 outPoolUsage 都是低，有可能最终可能导致反压（还没传递到上游） | 被下游反压                                 |
| 如果上游的 outPoolUsage 是高，则为反压根源 |                                                              |                                            |

#### 2）可以进一步分析数据传输

Flink1.9 及以上版本，还可以根据 floatingBuffersUsage/exclusiveBuffersUsage 以及其上游 Task 的 outPoolUsage 来进行进一步的分析一个 Subtask 和其上游Subtask 的数据传输。

在流量较大时，Channel  的  ExclusiveBuffer  可能会被写满，此时  Flink  会向  BufferPool 申请剩余的 FloatingBuffer。这些 **FloatingBuffer 属于备用 Buffer。**



|                                                              | **exclusiveBuffersUsage** **低**        | **exclusiveBuffersUsage** **高**                  |
| ------------------------------------------------------------ | --------------------------------------- | ------------------------------------------------- |
| **floatingBuffersUsage** **低**所有上游**outPoolUsage** **低** | 正常                                    |                                                   |
| **floatingBuffersUsage** **低**上游某个**outPoolUsage** **高** | 潜在的网络瓶颈                          |                                                   |
| **floatingBuffersUsage**高所有上游**outPoolUsage** **低**    | 最终对部分inputChannel 反压（正在传递） | 最终对大多数或所有   inputChannel反压（正在传递） |
| **floatingBuffersUsage**高上游某个**outPoolUsage** **高**    | 只对部分 inputChannel 反压              | 对大多数或所有 inputChannel 反压                  |

总结：

- 1）floatingBuffersUsage 为高，则表明反压正在传导至上游
- 2）同时 exclusiveBuffersUsage 为低，则表明可能有倾斜



比如，floatingBuffersUsage 高、exclusiveBuffersUsage 低为有倾斜，因为少数

channel 占用了大部分的 FloatingBuffer。

## 3.3 反压的原因及处理

注意：反压可能是暂时的，可能是由于负载高峰、CheckPoint 或作业重启引起的数据积压而导致反压。如果反压是暂时的，应该忽略它。另外，请记住，断断续续的反压会影响我们分析和解决问题。

定位到反压节点后，分析造成原因的办法主要是观察 TaskThread。按照下面的顺序，一步一步去排查。

### 3.3.1    查看是否数据倾斜

**在实践中，很多情况下的反压是由于数据倾斜造成的，这点我们可以通过 Web UI各**

**个 SubTask 的 RecordsSent 和 RecordReceived 来确认，另外 Checkpointdetail里不同 SubTask 的 Statesize 也是一个分析数据倾斜的有用指标。**

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654675365111-f2598a4c-7ae6-4c6b-852b-a2c31b53623e.png)

（关于数据倾斜的详细解决方案，会在下一章节详细讨论）

### 3.3.2    使用火焰图分析

如果不是数据倾斜，最常见的问题可能是用户代码的执行效率问题（频繁被阻塞或者性能问题），需要找到瓶颈算子中的哪部分计算逻辑消耗巨大。

最有用的办法就是对 TaskManager 进行 CPUprofile，从中我们可以分析到 TaskThread 是否跑满一个 CPU 核：如果是的话要分析 CPU 主要花费在哪些函数里面；如果不是的话要看 TaskThread 阻塞在哪里，可能是用户函数本身有些同步的调用，可能是checkpoint 或者 GC 等系统活动导致的暂时系统暂停。

#### 1）开启火焰图功能

Flink1.13直接在 WebUI提供 JVM的 CPU 火焰图，这将大大简化性能瓶颈的分析，默认是不开启的，需要修改参数：

rest.flamegraph.enabled:true#默认false                                                                          



也可以在提交时指定：

> bin/flinkrun\
>
> -tyarn-per-job\
>
> -d\
>
> -p5 \
>
> -Drest.flamegraph.enabled=true\
>
> -Dyarn.application.queue=test\
>
> -Drest.flamegraph.enabled=true\
>
> -Djobmanager.memory.process.size=1024mb \
>
> -Dtaskmanager.memory.process.size=2048mb\
>
> -Dtaskmanager.numberOfTaskSlots=2\
>
> -ccom.atguigu.flink.tuning.UvDemo \
>
> /opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar

#### 2）WebUI 查看火焰图

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654675647317-7df4c4eb-e01f-4637-9d0e-a9980331f2c2.png)

火焰图是通过对堆栈跟踪进行多次采样来构建的。每个方法调用都由一个条形表示，其中条形的长度与其在样本中出现的次数成正比。

- On-CPU: 处于 [RUNNABLE, NEW]状态的线程
- Off-CPU: 处于 [TIMED_WAITING, WAITING, BLOCKED]的线程，用于查看在样本中发现的阻塞调用。

#### 3）分析火焰图

颜色没有特殊含义，具体查看：

- 纵向是调用链，从下往上，顶部就是正在执行的函数
- 横向是样本出现次数，可以理解为执行时长。

**看顶层的哪个函数占据的宽度最大。只要有"平顶"（plateaus），就表示该函数可能存在性能问题。**

如果是 Flink1.13 以前的版本，可以手动做火焰图：

如何生成火焰图：http://www.54tianzhisheng.cn/2020/10/05/flink-jvm-profiler/

### 3.3.3    分析GC 情况

TaskManager 的内存以及 GC 问题也可能会导致反压，包括 TaskManagerJVM 各区内存不合理导致的频繁 FullGC 甚至失联。通常建议使用默认的 G1 垃圾回收器。

可以通过打印 GC 日志（-XX:+PrintGCDetails），使用 GC 分析器（GCViewer 工具）来验证是否处于这种情况。



- 在 Flink 提交脚本中,设置 JVM 参数，打印 GC 日志：

> bin/flinkrun\
>
> -tyarn-per-job\
>
> -d\
>
> -p5 \
>
> -Drest.flamegraph.enabled=true\
>
> -Denv.java.opts="-XX:+PrintGCDetails-XX:+PrintGCDateStamps"\
>
> -Dyarn.application.queue=test\
>
> -Djobmanager.memory.process.size=1024mb \
>
> -Dtaskmanager.memory.process.size=2048mb\
>
> -Dtaskmanager.numberOfTaskSlots=2\
>
> -ccom.atguigu.flink.tuning.UvDemo \
>
> /opt/module/flink-1.13.1/myjar/flink-tuning-1.0-SNAPSHOT.jar



- 下载 GC 日志的方式：

因为是 onyarn 模式，运行的节点一个一个找比较麻烦。可以打开 WebUI，选择JobManager 或者 TaskManager，点击 Stdout，即可看到 GC 日志，点击下载按钮即可将 GC日志通过 HTTP的方式下载下来。

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654679097595-18b82b7c-8bd5-4d21-b720-44c795ce377a.png)

- 分析 GC 日志：

通过 GC 日志分析出单个 FlinkTaskmanager 堆总大小、年轻代、老年代分配的内存空间、FullGC 后老年代剩余大小等，相关指标定义可以去 Github 具体查看。

GCViewer 地址：https://github.com/chewiebug/GCViewer

Linux 下分析：

java -jargcviewer_1.3.4.jargc.log                                                                                    

Windows 下分析：

直接双击gcviewer_1.3.4.jar，打开GUI界面，选择gc的log打开         

​                      

扩展：最重要的指标是FullGC 后，老年代剩余大小这个指标，按照《Java 性能优化权威指南》这本书 Java 堆大小计算法则，设 FullGC 后老年代剩余大小空间为 M，那么堆的大小建议 3~4 倍 M，新生代为 1~1.5 倍 M，老年代应为 2~3 倍 M。

### 3.3.4    外部组件交互

如果发现我们的 Source端数据读取性能比较低或者 Sink端写入性能较差，需要检查第三方组件是否遇到瓶颈，还有就是做维表join时的性能问题。

例如：

Kafka集群是否需要扩容，Kafka 连接器是否并行度较低

HBase的 rowkey 是否遇到热点问题，是否请求处理不过来

ClickHouse并发能力较弱，是否达到瓶颈

……

关于第三方组件的性能问题，需要结合具体的组件来分析，最常用的思路：

- 1）异步 io+热缓存来优化读写性能
- 2）先攒批再读写维表join参考：

https://flink-learning.org.cn/article/detail/b8df32fbc6542257a5b449114e137cc3

https://www.jianshu.com/p/a62fa483ff54



# 四、数据倾斜

## 4.1  判断是否存在数据倾斜

相同 Task 的多个 Subtask 中， 个别 Subtask 接收到的数据量明显大于其他Subtask 接收到的数据量，通过 FlinkWebUI 可以精确地看到每个 Subtask 处理了多少数据，即可判断出 Flink 任务是否存在数据倾斜。通常，数据倾斜也会引起反压。

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654692839400-88f4eb2d-9389-4011-a676-2f6da336cb39.png)

另外， 有时 Checkpointdetail 里不同 SubTask 的 Statesize 也是一个分析数据倾斜的有用指标。

## 4.2 数据倾斜的解决

### 4.2.1    keyBy 后的聚合操作存在数据倾斜

#### 1）为什么不能直接用二次聚合来处理（没有卵用）

Flink是实时流处理，如果keyby之后的聚合操作存在数据倾斜，且没有开窗口（没攒批）的情况下，简单的认为使用两阶段聚合，是不能解决问题的。因为这个时候Flink是来一条处理一条，且向下游发送一条结果，对于原来 keyby的维度（第二阶段聚合）来讲，数据量并没有减少，且结果重复计算（非 FlinkSQL，未使用回撤流），如下图所示：

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1654692995562-f3b6caac-04e3-45ac-87bc-92286cb10e2b.png)

#### 2）使用 LocalKeyBy 的思想

在 keyBy 上游算子数据发送之前，首先在上游算子的本地对数据进行聚合后，再发送到下游，使下游接收到的数据量大大减少，从而使得 keyBy 之后的聚合操作不再是任务的瓶颈。类似 MapReduce中 Combiner的思想，但是这要求聚合操作必须是多条数据或者一批数据才能聚合，单条数据没有办法通过聚合来减少数据量。从 FlinkLocalKeyBy实现原理来讲，必然会存在一个积攒批次的过程，在上游算子中必须攒够一定的数据量，对这些数据聚合后再发送到下游。

#### 实现方式：

- DataStreamAPI 需要自己写代码实现
- SQL 可以指定参数，开启miniBatch 和 LocalGlobal 功能（推荐，后续介绍）

### 4.1.1    keyBy之前发生数据倾斜

如果 keyBy 之前就存在数据倾斜，上游算子的某些实例可能处理的数据较多，某些实例可能处理的数据较少，产生该情况可能是因为数据源的数据本身就不均匀，例如由于某些原因 Kafka 的 topic 中某些 partition 的数据量较大，某些 partition 的数据量较少。

对于不存在 keyBy 的 Flink 任务也会出现该情况。

这种情况，需要让 Flink 任务强制进行shuffle。使用 shuffle、rebalance 或 rescale

算子即可将数据均匀分配，从而解决数据倾斜的问题。

### 4.1.2    keyBy 后的窗口聚合操作存在数据倾斜

因为使用了窗口，变成了有界数据（攒批）的处理，窗口默认是触发时才会输出一条结果发往下游，所以可以使用两阶段聚合的方式：

#### 1）实现思路：

- 第一阶段聚合：key拼接随机数前缀或后缀，进行 keyby、开窗、聚合

**注意：聚合完不再是 WindowedStream，要获取 WindowEnd 作为窗口标记作为第二阶段分组依据，避免不同窗口的结果聚合到一起）**

- 第二阶段聚合：按照原来的 key 及windowEnd 作keyby、聚合

SQL写法参考：https://zhuanlan.zhihu.com/p/197299746
