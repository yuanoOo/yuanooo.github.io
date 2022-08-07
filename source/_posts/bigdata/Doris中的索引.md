---
title: Doris中的索引
tags:
  - 'Doris'
categories:
  - [bigdata,Doris]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2022-08-07 10:51:08
updated: 2022-08-07 10:51:08
cover:
description:
keywords:
---

> **不同于传统的数据库设计，Doris 不支持在任意列上创建索引。**Doris 这类 MPP 架构的 OLAP 数据库，通常都是通过提高并发，来处理大量数据的。
>
> Doris 支持比较丰富的索引结构，来减少数据的扫描：
>
> - Sorted Compound Key Index，可以最多指定三个列组成复合排序键，通过该索引，能够有效进行数据裁剪，从而能够更好支持高并发的报表场景
> - Z-order Index ：使用 Z-order 索引，可以高效对数据模型中的任意字段组合进行范围查询
> - Min/Max ：有效过滤数值类型的等值和范围查询
> - Bloom Filter ：对高基数列的等值过滤裁剪非常有效
> - Invert Index ：能够对任意字段实现快速检索
