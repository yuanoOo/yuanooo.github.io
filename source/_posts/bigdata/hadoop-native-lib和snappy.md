---
title: 配置hadoop native lib和snappy压缩遇到的问题
tags:
  - ''
categories:
  - []
date: 2022-10-16 18:48:59
updated: 2022-10-16 18:48:59
cover:
top_img:
description:
keywords:
---



- `Unable to load native-hadoop library``

  `2022-10-16 18:04:07.991 WARN org.apache.hadoop.util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable`

添加环境变量：`export LD_LIBRARY_PATH=$HADOOP_HOME/lib/native`

- 执行hadoop本地库检查` hadoop checknative -a`报错:`ERROR snappy.SnappyCompressor: failed to load SnappyCompressor`

  安装snappy本地库，执行：`sudo apt install libsnappy-dev`
