---
title: 从SS-Table到LSM-Tree
tags:
  - 'LSM-Tree'
categories:
  - [data-structure]
top_img: 
date: 2022-09-11 11:45:16
updated: 2022-09-11 11:45:16
cover:
description:
keywords:
---

## SS-Table

- SSTable 最早出自 Google 的 Bigtable 论文

  >An SSTable provides a persistent, ordered immutable map from keys to values, where both keys and values are arbitrary byte strings. Operations are provided to look up the value associated with a specified key, and to iterate over all key/value pairs in a specified key range. Internally, each SSTable contains a sequence of blocks (typically each block is 64KB in size, but this is configurable). A block index (stored at the end of the SSTable) is used to locate blocks; the index is loaded into memory when the SSTable is opened. A lookup can be performed with a single disk seek: we first find the appropriate block by performing a binary search in the in-memory index, and then reading the appropriate block from disk. Optionally, an SSTable can be completely mapped into memory, which allows us to perform lookups and scans without touching disk.
  >
  >
  >
  >通过以上描述，我们可以把 SSTable 抽象为以下结构，每个 SSTable 包含了很多按照 key 排序的 key-value 对，key 和 value 都是任意的字节数组。SSTable 可以方便的支持基于 key 的查找和范围扫描。SSTable 会把数据分成块进行存储，并在 SSTable 文件尾部保存块索引(Block Index), 块索引记录每个块结束的 key 及对应的offset。块索引一般会在 SSTable 打开的时候载入内存。每次读取 SSTable 的时候，在内存中找到对应的块，再进行一次磁盘访问，读取到块中的数据。当然，把 SSTable 大小限定在可以加载进内存的大小，每次直接加载进内存访问也是一种方法。

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1662868513341-45eab64f-2958-447b-8fc5-328a4942dfa1.png)

> SSTable本身是个简单而有用的数据结构, 而往往由于工业界对于它的overload, 导致大家的误解
> 它本身就像他的名字一样, 就是a set of sorted key-value pairs
> 如下图左, 当文件比较大的时候, 也可以建立key:offset的index, 用于快速分段定位, 但这个是可选的.
>
> 这个结构和普通的key-value pairs的区别, **可以support range query和random r/w**

## SSTables and Log Structured Merge Trees

仅仅SSTable数据结构本身仍然无法support高效的range query和random r/w的场景
还需要一整套的机制来完成从memory sort, flush to disk, compaction以及快速读取……这样的一个完成的机制和架构称为,"[The Log-Structured Merge-Tree](http://nosqlsummer.org/paper/lsm-tree)" (**LSM Tree**)
名字很形象, 首先是基于log的, 不断产生SSTable结构的log文件, 并且是需要不断merge以提高效率的

下图很好的描绘了LSM Tree的结构和大部分操作

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1662868915058-01727c5c-f5e9-402b-8737-41408cc5323d.png)

![img](https://cdn.nlark.com/yuque/0/2022/webp/2500465/1662868956879-bb12a4e1-38b5-47c0-a25e-4d0d8f8ce788.webp)

> - 写操作：Tablet 把响应的操作写入操作日志（tablet log），然后将具体的内容写入内存中 MemTable
> - 读操作：读操作需要同时读 Memtable 和 SSTable，将结果合并返回。Memtable 和 SSTable 都是按照 key 有序的，可以快速的进行类似归并排序的合并。
> - Minor Compaction：随着写请求的不断增多，Memtable 在内存中的空间不断增大，当 Memtable 的大小达到一定阈值时，Memtable 被 dump 到 GFS 中成为不可变的 SSTable。
> - Merging Compaction：随着 Memtable 不断的变为 SSTable，SSTable 也不断增多，意味着读操作需要读取的 SSTable 也越来越多，为了限制 SSTable 的个数，Tablet Server 会在后台将多个 SSTable 合并为一个
> - Major Compaction：Major Compaction 是一种特殊的 Merging Compaction，只把所有的 SSTable 合并为一个 SSTable，在 非 Major Compaction 产生的 SSTable 中可能包含已经删除的数据，Major Compaction 的过程会将这些数据真正的剔除掉，避免这些数据浪费存储空间。

LSM Tree 的索引机制和 B+ Tree 的索引机制是明显不同的，B+ Tree 为所有的数据维护了一个索引，LSM Tree 则是为每个 磁盘文件维护了一个 Index。



## 列行存储

![image.png](https://cdn.nlark.com/yuque/0/2022/png/2500465/1662869279366-ddf2ea3e-ed85-4708-854f-7306682043b4.png)

![image.png](https://cdn.nlark.com/yuque/0/2022/png/2500465/1662869286634-2e3183d7-1ce6-410d-95c2-68a26db82e60.png)

>在Doris中，数据从 MemTable 刷写到磁盘的过程分为两个阶段，第一阶段是将 MemTable 中的行存结构在内存中转换为列存结构，并为每一列生成对应的索引结构；第二阶段是将转换后的列存结构写入磁盘，生成 Segment 文件。

## 参考

- https://www.igvita.com/2012/02/06/sstable-and-log-structured-storage-leveldb/
