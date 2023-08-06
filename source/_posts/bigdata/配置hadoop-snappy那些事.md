---
title: 配置hadoop-snappy那些事
tags:
  - ''
categories:
  - []
abbrlink: 27401
date: 2022-11-01 17:46:42
updated: 2022-11-01 17:46:42
cover:
top_img:
description:
keywords:
---

## 前言

在Apache Hadoop3.x社区二进制发行版中已经包含hadoop-snappy，同时Centos7已经自带snappy本地库。因此Hadoop3.x+Centos7无需配置snappy本地库。可运行`hadoop checknative -a`检查snappy本地库是否可用。

> 看了网上繁琐的Hadoop Snappy配置过程，配置了半天，才发现是白费功夫。原来是Hive的一个Bug。

## Hive3.1.2中orc文件snappy压缩的Bug

### Bug描述

- 创建一个Hive表，存储为orc文件，同时启用snappy压缩。

  ```hive
  CREATE TABLE `default`.`user_orc` (
    `tid` INT,
    `userid` STRING
  )
  STORED AS orc
  TBLPROPERTIES (
    "orc.compress"="SNAPPY"
  );
  ```
  
- Insert overwrite进一些数据

  ```hive
  insert overwrite table user_orc select * from user_1;
  ```

- 会在HDFS生成/user/hadoop/warehouse/user_orc/000000_0文件，文件没有带有.orc后缀

- 使用`hive --orcfiledump /user/hadoop/warehouse/user_orc/000000_0`查看该orc文件信息，发现Compression: ZLIB，即默认的ZLIB压缩算法，snappy压缩算法没有生效。

### 解决

- 1、设置`set hive.exec.orc.default.compress=snappy;`参数，可暂时解决。
- 2、升级到hive-3.1.3，貌似已经修复该问题。