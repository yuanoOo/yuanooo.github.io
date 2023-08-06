---
title: HBase如何实现MVCC？
tags:
  - HBase
  - MVCC
categories:
  - - bigdata
    - HBase
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
abbrlink: 6299
date: 2022-07-05 15:13:53
updated: 2022-07-05 15:13:53
cover:
description:
keywords:
---

## HBase的事务一致性保证

**HBase 是一个强一致性数据库，不是“最终一致性”数据库，官网给出的介绍**

![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1657001617770-e017f8b5-f8c4-4b1e-9721-a934e51df162.png)

> - 每个值只出现在一个 Region
> - 同一时间一个 Region 只分配给一个 RS
> - 行内的 mutation 操作都是原子的

**HBase 降低可用性提高了一致性。**

当某台 RS fail 的时候，它管理的 Region failover 到其他 RS 时，需要根据 WAL（Write-Ahead Logging）来 redo (redolog，有一种日志文件叫做重做日志文件)，
这时候进行 redo 的 Region 应该是不可用的，所以 HBase 降低了可用性，提高了一致性。

设想一下，如果 redo 的 Region 能够响应请求，那么可用性提高了，则必然返回不一致的数据(因为 redo 可能还没完成)，那么 HBase 就降低一致性来提高可用性了。

## HBase MVCC实现流程

数据库为了保证一致性，在执行读写操作时往往会对数据做一些锁操作，比如两个client同时修改一条数据，我们无法确定最终的数据到底是哪一个client执行的结果，所以需要通过加锁来保证数据的一致性。

但是锁操作的代价是比较大的，往往需要对加锁操作进行优化，主流的数据库Mysql，PG等都采用MVCC（多版本并发控制）来尽量避免使用不必要的锁以提高性能。本文主要介绍HBase的MVCC实现机制。

在讲解HBase的MVCC之前，我们先了解一下现有的隔离级别，sql标准定义了4种隔离级别：

> 1.read uncommitted    读未提交
>
> 2.read committed        读已提交
>
> 3.repeatable read        可重复读
>
> 4.serializable               可串行化

**HBase不支持跨行事务，目前只支持单行级别的read uncommitted和read committed隔离级别。下面主要讲解HBase的read committed实现机制。**



![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1657001352637-015609d0-a12b-4a30-b262-8869b85c9b85.png)

HBase采用LSM树结构，当client发送数据给regionserver端时，regionserver会将数据写入对应的region中，region是由一个memstore和多个storeFile组成，我们可以将memstore看做是一个skipList（跳表），所有写入的数据首先存放在memstore中，当memstore增大到指定的大小后，memstore中的数据flush到磁盘生成一个新的storeFile。

### HBase的写入主要分两步：

> **1.数据首先写入memstore**
>
> **2.数据写入WAL**
>
> 写入WAL的目的是为了持久化，防止memstore中的数据还未落盘时宕机造成的数据丢失，只有数据写入WAL成功之后才会认为该数据写入成功。
>

**下面我们考虑一个问题：**

根据前面的讨论可知，假如数据已经写入memstore，但还没有写入WAL，此时认为该条数据还没有写成功，如果按照read committed隔离界别的定义，用户在进行查询操作时（尤其是查询memstore时），是不应该看到这条数据的，那HBase是如何区分正在写入和写入成功的数据呢？

我们可以简单理解HBase在每次put操作时，都会为该操作分配一个id，可以类比mysql里面的事务id，是本次put的唯一标识，该id是region级别递增的，并且每个region还有一个MVCC控制中心，它还同时维护了两个pos：一个readpoint，一个writepoint。readpoint指向目前已经插入完成的id，当put操作完成时会更新readpoint；而writepoint指向目前正在插入的最大id，可以认为writepoint永远和最新申请的put的事务id是一样的。



![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1657001352762-41efd7fd-cfbd-4077-b218-c451a0d80e5c.png)

**下面我们画图解释：**

1.client插入数据时（这里的client我们可以理解为是regionserver），首先会向MVCC控制中心（MultiVersionConsistencyControl类）申请最新的事务id，其实就是返回write point++，每一个region各自拥有一个独立MVCC控制中心。

2.假设初始状态read和write point都指向2，表明目前没有正在进行的put操作，新的put请求过来时，该region的MVCC控制中心向它自己维护的队列中插入一个新的entry，表示发起了一个新的put事务，并且第一步中将write point++。

3.向client返回本次事务的id为3.

4.client向memstore中插入数据，并且该数据附带本次事务的id号：3

5.将本次的put操作写入WAL，写入成功后代表数据写入成功

6.此时移动read point至3，表示任何MVCC值小于等于3的数据此时都可以被新创建的scan查询检索到。

scan执行查询操作时，首先会向MVCC控制中心拿到目前的read point，然后对memstore和storeFiles进行查询，并过滤掉MVCC值大于本次scan MVCC的数据，保证了scan不会检索到还未提交成功的数据。这也说明HBase默认即为read committed级别，只不过是单行事务。





![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1657001352817-f8176f99-9cd4-477c-ac8e-153fdc023be7.png)

真正业务场景下是会有很多个client同时写入的，此时不管向MVCC申请事务id还是更新read point都会涉及到多用户竞争的情况。如图client A B C分别写入了数据de/fg/hi，有可能A C已经写入成功了，而B还未执行完，下面我们看一下MVCC控制中心是如何协调并发请求的。

先介绍一下MVCC控制中心–**MultiVersionConsistencyControl**类.

**它包含了三个重要的成员：**

1.memstoreRead：即我们提到的read point，记录可以已执行完毕的事务id

2.memstoreWrite：即我们提到的write point，记录当前正在执行的最大事务id

3.writeQueue：一个LinkedList，每一个元素是一个WriteEntry对象。

**WriteEntry类包含两个属性：**

1.writeNumber：事务id

2.completed： True/False，数据写入成功后，写入线程会将其设置为True



![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1657001352718-eea3b630-fac5-4e86-8c07-7629c40cb12e.png)

**下面详细解释MVCC控制中心针对多用户请求是如何做到同步的：**

1.当一个client写入数据时，首先lock住MVCC控制中心的写入队列LinkedList，并向其插入一个新的entry，并将之前的write point+1赋予entry的num（write point+1也是同步操作），表示发起了一个新的写入事务。Flag值此时为False，表名目前事务还未完成，数据还在写入过程中。

2.第二步client将数据写入memstore和WAL，此时认为数据已经持久化，可以结束该事务。

3.client调用MVCC控制中心的completeMemstoreInsert(num)方法，该方法采用synchronized关键字，可以理解就是同步方法，将该num对应的entry的Flag设置为True，表示该entry对应的事务完成。但是单单将Flag设置为True是不够的，我们的最终目的是要让scan能够看到最新写入完成的数据，也就是说还需要更新read point。

4.更新read point：同样在completeMemstoreInsert方法中完成，每一个client将其对应的entry的Flag设置为True后，都会去按照队列顺序，从read point开始遍历，假如遍历到的entry的Flag为True，则将read point更新至此位置，直到遇到Flag为False的位置时停止。也就是说每个client写入之后，都会尽力去将read point更新到目前最大连续的已经完成的事务的点（因为是有可能后开始的事务先于之前的事务完成）。

看到这里，可能大家会想了，那假如事务A先于事务C，事务A还未完成，但事务C已经完成，事务C也只能将read point更新到事务A之前的位置，如果此时事务C返回写入成功，那按道理来说scan是应该能够查到事务C的数据，但是由于read point没有更新到C，就会造成一个现象就是：事务C明明提示执行成功，但是查询的时候却看不到。

所以上面说的第4步其实还并没有完，client在执行completeMemstoreInsert后，还会执行一个waitForRead(entry)方法，参数的entry就是该事务对应的entry，该方法会一直等待read point大于等于该entry的num时才会返回，这样保证了事务有序完成。

以上就是HBase写入时MVCC的工作流程，scan就比较好理解了，每一个scan请求都会申请一个readpoint，保证了该read point之后的事务不会被检索到。



**说明**：HBase也同样支持read uncommitted级别，也就是我们在查询的时候将scan的mvcc值设置为一个超大的值，大于目前所有申请的MVCC值，那么查询时同样会返回正在写入的数据。

