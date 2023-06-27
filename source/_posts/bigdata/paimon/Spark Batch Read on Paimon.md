---
title: Spark Batch Read Paimon源码分析
tags:
  - 'paimon'
categories:
  - [bigdata,paimon]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2023-06-21 17:57:25
updated: 2023-06-21 17:57:25
cover:
description:
keywords:
---

> A bucket is the smallest storage unit for reads and writes, so the number of buckets limits the maximum processing parallelism. This number should not be too big, though, as it will result in lots of small files and low read performance. In general, the recommended data size in each bucket is about 1GB.
>
> | num-sorted-run.compaction-trigger | 5    | Integer | The sorted run number to trigger compaction. Includes level0 files (one file one sorted run) and high-level runs (one level one sorted run). |
> | --------------------------------- | ---- | ------- | ------------------------------------------------------------ |

## Paimon Bucket && Sorted Run

对于Paimon Primary Key主键表，一个Bucket对应一个LSM树，一个LSM树由多个Sorted Run构成。

一个Sorted Run可能包含一个或多个文件，但是每个文件只能属于一个Sorted Run。

- 对于Level-0层来说：一个SST文件对应一个Sorted Run，Level-0的文件是每次刷盘形成的，而Flink流写Paimon刷盘的时机是CheckPoint的时候或memory buffer is full。所以Level-0层会不断产生新文件，而每个文件就是一个Sorted Run，为了防止Level-0层小文件过多，Paimon会按照合并策略进行小文件合并。Paimon采用类似RocksDB中的UniversalCompaction合并策略，进行合并。
- 对于其他Level层来说：一层对应一个Sorted Run。

在排序运行中，数据文件的主键范围永远不会重叠。不同的排序运行可能具有重叠的主键范围，甚至可能包含相同的主键。查询LSM树时，必须合并所有排序的运行，并且必须根据用户指定的[合并引擎](https://paimon.apache.org/docs/master/concepts/primary-key-table/#merge-engines)和每条记录的时间戳来合并具有相同主键的所有记录。



## Spark批读Paimon

Spark批读Paimon的核心实现类为`org.apache.paimon.spark.SparkScan`。将Paimon表中的文件分成一个个Split交给Spark，Spark会一个Task读取一个Split，然后Spark就可以同时启动多个Task并行读取Paimon了。

那么Paimon是如何将Paimon表中的文件划分成一个个Split呢？对于主键表，其核心实现类为`org.apache.paimon.table.source.MergeTreeSplitGenerator`。注释写的非常清楚，这个类就是为了将每个Bucket下面的文件划分为一个个Split，以达到并行执行的目的，大致流程如下：

- 1、将文件划分为一个个section，该算法保证，每个section中的数据文件的主键范围永远不会重叠。这是为了保证Split和Split之间不存在主键范围重叠，这样每个Spark Task在读取Split的时候根据MergeEngine进行合并去重，就能保证全局范围上的主键唯一性。当然这个全局范围是指每个桶内主键不会重复，同时Paimon要求bucket-key必须为主键的一部分，这样就保证了Paimon在分区内主键的唯一性。
- 2、根据算法将一个个section合并为一个个split，该算法主要是为了将一些小section合并为一个split，减少小文件过多对查询性能的影响。

```java
    @Override
    public List<List<DataFileMeta>> split(List<DataFileMeta> files) {
        /*
         * The generator aims to parallel the scan execution by slicing the files of each bucket
         * into multiple splits. The generation has one constraint: files with intersected key
         * ranges (within one section) must go to the same split. Therefore, the files are first to go
         * through the interval partition algorithm to generate sections and then through the
         * OrderedPack algorithm. Note that the item to be packed here is each section, the capacity
         * is denoted as the targetSplitSize, and the final number of the bins is the number of
         * splits generated.
         *
         * For instance, there are files: [1, 2] [3, 4] [5, 180] [5, 190] [200, 600] [210, 700]
         * with targetSplitSize 128M. After interval partition, there are four sections:
         * - section1: [1, 2]
         * - section2: [3, 4]
         * - section3: [5, 180], [5, 190]
         * - section4: [200, 600], [210, 700]
         *
         * After OrderedPack, section1 and section2 will be put into one bin (split), so the final result will be:
         * - split1: [1, 2] [3, 4]
         * - split2: [5, 180] [5,190]
         * - split3: [200, 600] [210, 700]
         */
        List<List<DataFileMeta>> sections =
                new IntervalPartition(files, keyComparator)
                        .partition().stream().map(this::flatRun).collect(Collectors.toList());

        return packSplits(sections);
    }
```



## Paimon主键表分区数据量最佳大小

那么Paimon每个分区的数据量，这里指data size in each bucket，多少是最合适呢？文档中推荐为1GB。

根据上文可知，存在overlap的文件必须划分进一个Split，也就是一个并行度。如果是几个大文件存在overlap，这几个文件就只能划分进一个Split，就会造成只能一个Task读取合并这几个大文件，这个Task会处理的很慢，进而拖慢整个作业，甚至会在合并去重的时候，因为内存不足造成Task失败，进而造成整个Job失败，这显然不能接受。因此data size in each bucket一定不能太大。

Parquet最佳文件大小为每个文件数百 Mb（最高可达 1 GB）。那么data size in each bucket的最佳文件大小也应该为数百 Mb（最高可达 1 GB）。

