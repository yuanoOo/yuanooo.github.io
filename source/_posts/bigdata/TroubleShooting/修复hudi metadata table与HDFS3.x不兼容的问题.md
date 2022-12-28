---
title: 修复hudi metadata table与HDFS3.x不兼容的问题
tags:
  - 'Troubleshooting'
categories:
  - [Troubleshooting]
top_img: 
date: 2022-12-28 17:57:25
updated: 2022-12-28 17:57:25
cover:
description:
keywords:
---

> From 0.11.0 release, we have upgraded the HBase version to 2.4.9, which is released based on Hadoop 2.x. Hudi's metadata table uses HFile as the base file format, relying on the HBase library. When enabling metadata table in a Hudi table on HDFS using Hadoop 3.x, NoSuchMethodError can be thrown due to compatibility issues between Hadoop 2.x and 3.x.



## 简述

hudi的metadata table使用HFile作为基础文件格式，HFile依赖于HBase库。在Hudi0.12.1中使用HBase2.4.9版本，HBase2.4.9默认构建在Hadoop2.X，因此在HDFS3.x上使用Hudi metadata table会出现兼容性问题。抛出NoSuchMethodException异常。

## 修复方法

- 1、Download HBase source code from `https://github.com/apache/hbase`，切换到git checkout rel/2.4.9分支。

- 2、mvn install HBase2.4.9 with Hadoop3。构建基于Hadoop3的HBase2.4.9版本，mvn install安装到本地maven仓库，以便后续编译hudi的时候使用正确的版本。

  ```shell
  mvn clean install -Denforcer.skip -DskipTests -Dhadoop.profile=3.0 -Psite-install-step
  ```

- 3、分别重新编译hudi with Flink && Spark

  - Spark3.2x

    ```shell
    mvn clean package -DskipTests -Dspark3.2 -Dscala-2.12
    ```

  - Flink1.14.x

    ```shell
    mvn clean package -DskipTests -Dflink1.14 -Dscala-2.11 -am -amd
    ```

## 后记

- 这是一个由于第三方库（HBase HFile相关库）的依赖问题导致的Bug，因此需要先解决第三方的依赖问题，再解决Hudi的兼容性问题。