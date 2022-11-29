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

  

  