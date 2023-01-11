---
title: 开源项目BugFix合集
tags:
  - 'BugFix'
  - 'PR'
categories:
  - [bigdata,BugFix]
date: 2022-11-29 19:35:27
updated: 2022-11-29 19:35:27
cover:
top_img:
description:
keywords:
---

### 修复dolphinscheduler2.0.5中http-alert plugin丢失告警信息的Bug 

- http-alert告警插件仅仅发送用户预定义好的post body信息，丢失最重要Task运行告警信息。这是一个非常简单的Bug：https://github.com/apache/dolphinscheduler/commit/6021c228a1261a45ba8d02606f7132cd0a9b4c25

- git clone dolphinscheduler项目，然后切到2.0.5-release分支，执行`mvn -U clean package -Prelease -Dmaven.test.skip=true`进行编译打包。打包成功后，将生成的`dolphinscheduler\dolphinscheduler-alert\dolphinscheduler-alert-plugins\dolphinscheduler-alert-http\target\dolphinscheduler-alert-http-2.0.6-SNAPSHOT.jar`替换掉原来的jar包。

- 启停 Alert 

  ```shell
  sh ./bin/dolphinscheduler-daemon.sh start alert-server
  sh ./bin/dolphinscheduler-daemon.sh stop alert-server
  ```


### 修复Hadoop3.2.1中Logger Level错误提升的Bug

- [Flink-Hudi日志超频繁打印问题](https://poxiao.tk/2022/12/bigdata/TroubleShooting/Flink-hudi%E6%97%A5%E5%BF%97%E8%B6%85%E9%A2%91%E7%B9%81%E6%89%93%E5%8D%B0/)
- 修复流程：1、反编译相关Class文件。2、修改源码，并重新进行编译。3、打包回jar包。4、对jar包进行替换，重启相关服务。
- https://issues.apache.org/jira/browse/HDFS-14759

### 修复Kylin4.0.x中push-down query由于查询计划导致的不正常查询延时

- 发现kylin4.0.x中的push-down query对于明细查询`select * from table limit 10`非常慢，往往好耗时几分钟，这非常不正常。通过排查发现，在这类非常简单的明细查询的查询计划中，竟然有shuffle过程，简直离谱。
