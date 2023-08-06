---
title: 初识Apache Druid
tags:
  - Druid
categories:
  - - Druid
abbrlink: 17536
date: 2023-06-11 17:57:25
updated: 2023-06-12 17:57:25
top_img:
cover:
description:
keywords:
---

## Why Druid

> OLAP 是一种让用户可以用从不同视角方便快捷的分析数据的计算方法。主流的 OLAP 可以分为3类：多维 MOLAP ( Multi-dimensional OLAP )、关系型 ROLAP ( Relational OLAP ) 和混合 HOLAP ( Hybrid OLAP ) 三大类。

在海量数据上进行亚秒级的多维分析，并且要求高并发，可以选择的OLAP系统并不多。而其中MOLAP最为知名的就是Apache Kylin和Apache Druid。

先前我们一直采用Apache Kylin进行离线多维分析，在使用中发现了一系列问题，让我们不得不将目光放在Druid上面：

- 1、由于Kylin构建cube的数量和维度的关系是2的n次方，指数级增长是非常可怕的，一般超过20个维度，在Kylin中就要小心了，因此使用Kylin需要时刻担心维度爆炸的问题。
- 2、Kylin目前要求不超过63个Normal维度，这是因为cubeid是Long类型，而Long的最大值是**2^63 -1**，所以不能超过63个维度。而我们的业务场景最大会有二百多个维度，Kylin已经不满足我们的要求。
- 3、当维度中存在大基数列\维度的时候，还需要面临磁盘空间占用极度膨胀的问题。构建出来的cube占用的空间会远大于原数据占用的空间，这难以令人接受。
- 4、预计算时间长度不稳定，会随着维度的增加，不可控的延长，难以保证数据的新鲜度，且不可控。

Druid的优点：

- 可以选择性的Rollup，Druid的Rollup预计算相当于Kylin中只进行Base Cube构建，因此无需担心维度数量的问题。
- 基于LSM，Druid可以在进行海量数据实时导入的同时进行预计算，Druid可以实时导入。
- Druid在每个维度列上面构建索引，来加速多维分析，而不是像Kylin那样完全的预计算。Druid中默认为每个维度列创建Bitmap索引, 都是先做字典在做bitmap。https://tianzhipeng-git.github.io/2020/09/07/bitmap-index.html
- Druid经过Rollup的数据会比原始数据大量减少，占用的存储空间大大小于Kylin，节约了成本。