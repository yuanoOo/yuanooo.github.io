---
title: Doris Compaction从入门到跑路
tags:
  - 'Doris'
categories:
  - [Doris]
top_img: 
date: 2022-09-03 23:40:51
updated: 2022-09-03 23:40:51
cover:
description:
keywords:
---

>
>
>Doris 中用于控制Compaction的参数非常多。本文尝试以下方面，介绍这些参数的含义以及如果通过调整参数来适配场景。
>
>
>
>1. 数据版本是如何产生的，哪些因素影响数据版本的产出。
>2. 为什么需要 Base 和 Cumulative 两种类型的 Compaction。
>3. Compaction 机制是如何挑选数据分片进行 Compaction 的。
>4. 对于一个数据分片，Compaction 机制是如何确定哪些数据版本参与 Compaction 的。
>5. 在高频导入场景下，可以修改哪些参数来优化 Compaction 逻辑。
>6. Compaction 相关的查看和管理命令。

# Why  need Compaction

Doris 的数据写入模型使用了 LSM-Tree 类似的数据结构。数据都是以追加（Append）的方式写入磁盘的。这种数据结构可以将随机写变为顺序写。这是一种面向写优化的数据结构，他能增强系统的写入吞吐，但是在读逻辑中，需要通过 Merge-on-Read 的方式，在读取时合并多次写入的数据，从而处理写入时的数据变更。

Merge-on-Read 会影响读取的效率，为了降低读取时需要合并的数据量，基于 LSM-Tree 的系统都会引入后台数据合并的逻辑，以一定策略定期的对数据进行合并。Doris 中这种机制被称为 Compaction。

Doris 中每次数据写入会生成一个数据版本。Compaction的过程就是讲多个数据版本合并成一个更大的版本。Compaction 可以带来以下好处：

> - 1.数据更加有序
>
>   每个数据版本内的数据是按主键有序的，但是版本之间的数据是无序的。Compaction后形成的大版本将多个小版本的数据变成有序数据。在有序数据中进行数据检索的效率更高。
>
> - 2.消除数据变更
>
>   数据都是以追加的方式写入的，因此 Delete、Update 等操作都是写入一个标记。Compaction 操作可以处理这些标记，进行真正的数据删除或更新，从而在读取时，不再需要根据这些标记来过滤数据。
>
> - 3.增加数据聚合度
> 在聚合模型下，Compaction 能进一步聚合不同数据版本中相同 key 的数据行，从而增加数据聚合度，减少读取时需要实时进行的聚合计算。

# Compaction 的问题

用户可能需要根据实际的使用场景来调整 Compaction 的策略，否则可能遇到如下问题：

1. Compaction 速度低于数据写入速度

   在高频写入场景下，短时间内会产生大量的数据版本。如果 Compaction 不及时，就会造成大量版本堆积，最终严重影响写入速度。

2. 写放大问题

   Compaction 本质上是将已经写入的数据读取后重写写回的过程，这种数据重复写入被称为写放大。一个好的Compaction策略应该在保证效率的前提下，尽量降低写放大系数。过多的 Compaction 会占用大量的磁盘IO资源，影响系统整体效率。

# Something about Compaction(How)

## 数据版本的产生

首先，用户的数据表会按照分区和分桶规则，切分成若干个数据分片（Tablet）存储在不同 BE 节点上。每个 Tablet 都有多个副本（默认为3副本）。Compaction 是在每个 BE 上独立进行的，Compaction 逻辑处理的就是一个 BE 节点上所有的数据分片。

Doris的数据都是以追加的方式写入系统的。Doris目前的写入依然是以微批的方式进行的，每一批次的数据针对每个 Tablet 都会形成一个 rowset。而一个 Tablet 是由多个Rowset 组成的。每个 Rowset 都有一个对应的起始版本和终止版本。对于新增Rowset，起始版本和终止版本相同，表示为 [6-6]、[7-7] 等。多个Rowset经过 Compaction 形成一个大的 Rowset，起始版本和终止版本为多个版本的并集，如 [6-6]、[7-7]、[8-8] 合并后变成 [6-8]。

Rowset 的数量直接影响到 Compaction 是否能够及时完成。那么一批次导入会生成多少个 Rowset 呢？这里我们举一个例子：

假设集群有3个 BE 节点。每个BE节点2块盘。只有一张表，2个分区，每个分区3个分桶，默认3副本。那么总分片数量是（2 * 3 * 3）18 个，如果均匀分布在所有节点上，则每个盘上3个tablet。假设一次导入涉及到其中一个分区，则一次导入总共产生9个Rowset，即平均每块盘产生1-2个 Rowset。（这里仅考虑数据完全均匀分布的情况下，实际情况中，可能多个 Tablet 集中在某一块磁盘上。）

从上面的例子我们可以得出，rowset的数量直接取决于表的分片数量。举个极端的例子，如果一个Doris集群只有3个BE节点，但是一个表有9000个分片。那么一次导入，每个BE节点就会新增3000个rowset，则至少要进行3000次compaction，才能处理完所有的分片。所以：

> **合理的设置表的分区、分桶和副本数量，避免过多的分片，可以降低Compaction的开销。**

## Base & Cumulative Compaction

Doris 中有两种 Compaction 操作，分别称为 Base Compaction(BC) 和 Cumulative Compaction(CC)。BC 是将基线数据版本（以0为起始版本的数据）和增量数据版本合并的过程，而CC是增量数据间的合并过程。BC操作因为涉及到基线数据，而基线数据通常比较大，所以操作耗时会比CC长。

如果只有 Base Compaction，则每次增量数据都要和全量的基线数据合并，写放大问题会非常严重，并且每次 Compaction 都相当耗时。因此我们需要引入 Cumulative Compaction 来先对增量数据进行合并，当增量数据合并后的大小达到一定阈值后，再和基线数据合并。这里我们有一个比较通用的 Compaction 调优策略：

> **在合理范围内，尽量减少 Base Compaction 操作。**

BC 和 CC 之间的分界线成为 Cumulative Point（CP），这是一个动态变化的版本号。比CP小的数据版本会只会触发 BC，而比CP大的数据版本，只会触发CC。



![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1662219046764-f9891cea-fe8d-4eb2-89a4-911ffb10e7e2.png)



整个过程有点类似 2048 小游戏：只有合并后大小足够，才能继续和更大的数据版本合并。



![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1662219046833-aa0766ec-9852-4766-b57d-5b24448cd2b4.png)

## 数据分片选择策略

**Compaction 的目的是合并多个数据版本，一是避免在读取时大量的 Merge 操作，二是避免大量的数据版本导致的随机IO。**因此，Compaction 策略的重点问题，就是如何选择合适的 tablet，以保证节点上不会出现数据版本过多的数据分片。

### Compaction 分数

一个自然的想法，就是每次都选择数据版本最多的数据分片进行 Compaction。这个策略也是 Doris 的默认策略。这个策略在大部分场景下都能很好的工作。但是考虑到一种情况，就是版本多的分片，可能并不是最频繁访问的分片。而 Compaction 的目的就是优化读性能。那么有可能某一张 “写多读少” 表一直在 Compaction，而另一张 “读多写少” 的表不能及时的 Compaction，导致读性能变差。

因此，Doris 在选择数据分片时还引入了 “读取频率” 的因素。“读取频率” 和 “版本数量” 会根据各自的权重，综合计算出一个 Compaction 分数，分数越高的分片，优先做 Compaction。这两个因素的权重由以下 BE 参数控制（取值越大，权重越高）：

> **compaction_tablet_scan_frequency_factor：“读取频率” 的权重值，默认为 0。**
>
> **compaction_tablet_compaction_score_factor：“版本数量” 的权重，默认为 1。**

> “读取频率” 的权重值默认为0，即默认仅考虑 “版本数量” 这个因素。*

### 生产者与消费者

Compaction 是一个 生产者-消费者 模型。由一个生产者线程负责选择需要做 Compaction 的数据分片，而多个消费者负责执行 Compaction 操作。

生产者线程只有一个，会定期扫描所有 tablet 来选择合适的 compaction 对象。因为 Base Compaction 和 Cumulative Compaction 是不同类型的任务，因此目前的策略是每生成 9 个 CC 任务，生成一个 BC 任务。任务生成的频率由以下两个参数控制：

> **cumulative_compaction_rounds_for_each_base_compaction_round：多少个CC任务后生成一个BC任务。**
>
> **generate_compaction_tasks_min_interval_ms：任务生成的间隔。**

> *这两个参数通常情况下不需要调整。*

生产者线程产生的任务会被提交到消费者线程池。因为 Compaction 是一个IO密集型的任务，为了保证 Compaction 任务不会过多的占用IO资源，Doris 限制了每个磁盘上能够同时进行的 Compaction 任务数量，以及节点整体的任务数量，这些限制由以下参数控制：

> compaction_task_num_per_disk：每个磁盘上的任务数，默认为2。该参数必须大于等于2，以保证 BC 和 CC 任务各自至少有一个线程。
>
> max_compaction_threads：消费者线程，即Compaction线程的总数。默认为 10。
>

举个例子，假设一个 BE 节点配置了3个数据目录（即3块磁盘），每个磁盘上的任务数配置为2，总线程数为5。则同一时间，最多有5个 Compaction 任务在进行，而每块磁盘上最多有2个任务在进行。并且最多有3个 BC 任务在进行，因为每块盘上会自动预留一个线程给CC任务。

**另一方面，Compaction 任务同时也是一个内存密集型任务，因为其本质是一个多路归并排序的过程，每一路是一个数据版本。**如果一个 Compaction 任务涉及的数据版本很多，则会占用更多的内存，如果仅限制任务数，而不考虑任务的内存开销，则有可能导致系统内存超限。因此，Doris 在上述任务个数限制之外，还增加了一个任务配额限制：

> total_permits_for_compaction_score：Compaction 任务配额，默认 10000。

每个 Compaction 任务都有一个配额，其数值就是任务涉及的数据版本数量。假设一个任务需要合并100个版本，则其配额为100。当正在运行的任务配额总和超过配置后，新的任务将被拒绝。

三个配置共同决定了节点所能承受的 Compaction 任务数量。

### 数据版本选择策略

一个 Compaction 任务对应的是一个数据分片（Tablet）。消费线程拿到一个 Compaction 任务后，会根据 Compaction 的任务类型，选择 tablet 中合适的数据版本（Rowset）进行数据合并。下面分别介绍 Base Compaction 和 Cumulative Compaction 的数据分片选择策略。

#### Base Compaction

前文说过，BC 任务是增量数据和基线数据的合并任务。并且只有比 Cumulative Point（CP） 小的数据版本才会参与 BC 任务。因此，BC 任务的数据版本选取策略比较简单。

首先，会选取所有版本在 0到 CP之间的 rowset。然后根据以下几个配置参数，判断是否启动一个 BC 任务：

> base_compaction_num_cumulative_deltas：一次 BC 任务最小版本数量限制。默认为5。该参数主要为了避免过多 BC 任务。当数据版本数量较少时，BC 是没有必要的。
>
> base_compaction_interval_seconds_since_last_operation：第一个参数限制了当版本数量少时，不会进行 BC 任务。但我们需要避免另一种情况，即某些 tablet 可能仅会导入少量批次的数据，因此当 Doris 发现一个 tablet 长时间没有执行过 BC 任务时，也会触发 BC 任务。这个参数就是控制这个时间的，默认是 86400，单位是秒。
>

*> 以上两个参数通常情况下不需要修改，在某些情况下如何需要想尽快合并基线数据，可以尝试改小 **base_compaction_num_cumulative_deltas 参数。但这个参数只会影响到 “被选中的 tablet”。而 “被选中” 的前提是这个 tablet 的数据版本数量是最多的。***

#### Cumulative Compaction

CC 任务只会选取版本比 CP 大的数据版本。其本身的选取策略也比较简单，即从 CP 版本开始，依次向后选取数据版本。最终的数据版本集合由以下参数控制：

> min_cumulative_compaction_num_singleton_deltas：一次 CC 任务最少的版本数量限制。这个配置是和 cumulative_size_based_compaction_lower_size_mbytes 配置同时判断的。即如果版本数量小于阈值，并且数据量也小于阈值，则不会触发 CC 任务。以避免过多不必要的 CC 任务。默认是5。
>
> max_cumulative_compaction_num_singleton_deltas：一次 CC 任务最大的版本数量限制。以防止一次 CC 任务合并的版本数量过多，占用过多资源。默认是1000。
>
> cumulative_size_based_compaction_lower_size_mbytes：一次 CC 任务最少的数据量，和min_cumulative_compaction_num_singleton_delta 同时判断。默认是 64，单位是 MB。
>

简单来说，默认配置下，就是从 CP 版本开始往后选取 rowset。最少选5个，最多选 1000 个，然后判断数据量是否大于阈值即可。

CC 任务还有一个重要步骤，就是在合并任务结束后，设置新的 Cumulative Point。CC 任务合并完成后，会产生一个合并后的新的数据版本，而我们要做的就是判断这个新的数据版是 “晋升” 到 BC 任务区，还是依然保留在 CC 任务区。举个例子：

假设当前 CP 是 10。有一个 CC 任务合并了 [10-13] [14-14] [15-15] 后生成了 [10-15] 这个版本。如果决定将 [10-15] 版本移动到 BC 任务区，则需修改 CP 为 15，否则 CP 保持不变，依然为 10。

**CP 只会增加，不会减少。** 以下参数决定了是否更新 CP：

> cumulative_size_based_promotion_ratio：晋升比率。默认 0.05。
>
> cumulative_size_based_promotion_min_size_mbytes：最小晋升大小，默认 64，单位 MB。
>
> cumulative_size_based_promotion_size_mbytes：最大晋升大小，默认 1024，单位 MB。
>

以上参数比较难理解，这里我们先解释下 “晋升” 的原则。一个 CC 任务生成的 rowset 的晋升原则，是其数据大小和基线数据的大小在 “同一量级”。这个类似 2048 小游戏，只有相同的数字才能合并形成更大的数字。而上面三个参数，就是用于判断一个新的rowset是否匹配基线数据的数量级。举例说明：

在默认配置下，假设当前基线数据（即所有 CP 之前的数据版本）的数据量为 10GB，则晋升量级为 （10GB * 0.05）512MB。这个数值大于 64 MB 小于 1024 MB，满足条件。所以如果 CC 任务生成的新的 rowset 的大小大于 512 MB，则可以晋升，即 CP 增加。而假设基线数据为 50GB，则晋升量级为（50GB * 0.05）2.5GB。这个数值大于 64 MB 也大于 1024 MB，因此晋升量级会被调整为 1024 MB。所以如果 CC 任务生成的新的 rowset 的大小大于 1024 MB，则可以晋升，即 CP 增加。

从上面的例子可以看出，cumulative_size_based_promotion_ratio 用于定义 “同一量级”，0.05 即表示数据量大于基线数据的 5% 的 rowset 都有晋升的可能，而 cumulative_size_based_promotion_min_size_mbytes 和 cumulative_size_based_promotion_size_mbytes 用于保证晋升不会过于频繁或过于严格。

> *这三个参数会直接影响 BC 和 CC 任务的频率，尤其在高频导入场景下需要适当调整。我们会在后续文章中举例说明。*

### 其他 Compaction 参数和注意事项

还有一些参数和 Compaction 相关，在某些情况下需要修改：

disable_auto_compaction：默认为 false，修改为 true 则会禁止 Compaction 操作。该参数仅在一些调试情况，或者 compaction 异常需要临时关闭的情况下才需使用。

#### Delete 灾难

通过 DELETE FROM 语句执行的数据删除操作，在 Doris 中也会生成一个数据版本用于标记删除。这种类型的数据版本比较特殊，我们成为 “删除版本”。删除版本只能通过 Base Compaction 任务处理。因此在在遇到删除版本时，Cumulative Point 会强制增加，将删除版本移动到 BC 任务区。**因此数据导入和删除交替发生的场景通常会导致 Compaction 灾难**。比如以下版本序列：

```
[0-10]
[11-11] 删除版本
[12-12]
[13-13] 删除版本
[14-14]
[15-15] 删除版本
[16-16]
[17-17] 删除版本
...
```

在这种情况下，CC 任务几乎不会被触发（因为CC任务只能选择一个版本，而无法处理删除版本），所有版本都会交给 Base Compaction 处理，导致 Compaction 进度缓慢。目前Doris还无法很好的处理这种场景，因此需要在业务上尽量避免。
