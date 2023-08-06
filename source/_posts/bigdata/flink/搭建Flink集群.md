---
title: Flink Cluster With YARN
tags:
  - Flink
categories:
  - - bigdata
    - Flink
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
abbrlink: 44798
date: 2022-08-08 19:54:07
updated: 2022-08-08 19:54:07
cover:
description:
keywords:
---

>在YARN部署模式中，有三种部署方式：
>
>- in Application Mode
>- in Session Mode
>- in a Per-Job Mode (deprecated)

# YARN模式

独立（Standalone）模式由 Flink 自身提供资源，无需其他框架，这种方式降低了和其他第三方资源框架的耦合性，独立性非常强。但我们知道，Flink 是大数据计算框架，不是资源调度框架，这并不是它的强项；所以还是应该让专业的框架做专业的事，和其他资源调度框架集成更靠谱。而在目前大数据生态中，国内应用最为广泛的资源管理平台就是 YARN 了。所以接下来我们就将学习，在强大的 YARN 平台上 Flink 是如何集成部署的。

整体来说，YARN 上部署的过程是：客户端把 Flink 应用提交给 Yarn 的ResourceManager, Yarn 的 ResourceManager 会向 Yarn 的 NodeManager 申请容器。在这些容器上，Flink 会部署JobManager 和 TaskManager 的实例，从而启动集群。Flink 会根据运行在 JobManger 上的作业所需要的 Slot 数量动态分配TaskManager 资源。

 ![image.png](https://cdn.nlark.com/yuque/0/2022/png/2500465/1659960821751-9ec31d52-d839-445c-8aa4-e6f9af4d2ca8.png)

## 相关准备和配置

在 Flink1.8.0 之前的版本，想要以 YARN 模式部署 Flink 任务时，需要 Flink 是有 Hadoop 支持的。从 Flink 1.8 版本开始，不再提供基于 Hadoop 编译的安装包，若需要Hadoop 的环境支持，需要自行在官网下载 Hadoop 相关版本的组件flink-shaded-hadoop-2-uber-2.7.5-10.0.jar， 并将该组件上传至 Flink 的 lib 目录下。在 Flink 1.11.0 版本之后，增加了很多重要新特性，其中就包括增加了对Hadoop3.0.0 以及更高版本Hadoop 的支持，不再提供“flink-shaded-hadoop-*” jar 包，而是通过配置环境变量完成与 YARN 集群的对接。

在将 Flink 任务部署至 YARN 集群之前，需要确认集群是否安装有Hadoop，保证 Hadoop

版本至少在 2.2 以上，并且集群中安装有 HDFS 服务。具体配置步骤如下：

（1）下载并解压安装包，并将解压后的安装包重命名为flink-1.13.0-yarn，本节的相关操作都将默认在此安装路径下执行。

（2）配置环境变量，增加环境变量配置如下：

```sh
$ sudo vim /etc/profile.d/my_env.sh 
HADOOP_HOME=/opt/module/hadoop-2.7.5
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export HADOOP_CLASSPATH=`hadoop classpath`
```
这里必须保证设置了环境变量HADOOP_CLASSPATH。

（3）启动Hadoop 集群，包括 HDFS 和 YARN
（4）进入 conf 目录，修改 flink-conf.yaml 文件，修改以下配置，若在提交命令中不特定指明，这些配置将作为默认配置。
```
$ cd /opt/module/flink-1.13.0-yarn/conf/
$ vim flink-conf.yaml 
jobmanager.memory.process.size: 1600m 
taskmanager.memory.process.size: 1728m 
taskmanager.numberOfTaskSlots: 8
parallelism.default: 1
```

## 应用模式部署

应用模式同样非常简单，与单作业模式类似，直接执行 flink run-application 命令即可。

（1)执行命令提交作业。

```sh
$ bin/flink run-application -t yarn-application -c com.atguigu.wc.StreamWordCount
FlinkTutorial-1.0-SNAPSHOT.jar
```

（2）在命令行中查看或取消作业。

```shell
$./bin/flink list -t yarn-application -Dyarn.application.id=application_XXXX_YY
$./bin/flink cancel	-t	yarn-application -Dyarn.application.id=application_XXXX_YY <jobId>
```

（3） 也可以通过yarn.provided.lib.dirs 配置选项指定位置，将 jar 上传到远程。

```sh
$ ./bin/flink run-application -t yarn-application -Dyarn.provided.lib.dirs="hdfs://myhdfs/my-remote-flink-dist-dir" 
hdfs://myhdfs/jars/my-application.jar
```


这种方式下 jar 可以预先上传到 HDFS，而不需要单独发送到集群，这就使得作业提交更加轻量了。

## 高可用

YARN 模式的高可用和独立模式（Standalone）的高可用原理不一样。

Standalone 模式中, 同时启动多个 JobManager, 一个为“领导者”（leader），其他为“后备”（standby）, 当 leader 挂了, 其他的才会有一个成为 leader。

而 YARN 的高可用是只启动一个 Jobmanager, 当这个 Jobmanager 挂了之后, YARN 会再次启动一个, 所以其实是利用的 YARN 的重试次数来实现的高可用。

（1） 在 yarn-site.xml 中配置。

```xml
<property>
<name>yarn.resourcemanager.am.max-attempts</name>
<value>4</value>
<description>
The maximum number of application master execution attempts.
</description>
</property>
```

注意: 配置完不要忘记分发, 和重启 YARN。

（2） 在 flink-conf.yaml 中配置。

```yaml
yarn.application-attempts: 3 
high-availability: zookeeper
high-availability.storageDir: hdfs://hadoop102:9820/flink/yarn/ha 
high-availability.zookeeper.quorum: hadoop102:2181,hadoop103:2181,hadoop104:2181
high-availability.zookeeper.path.root: /flink-yarn
```

（3） 启动 yarn-session。

（4） 杀死 JobManager, 查看复活情况。

注意: yarn-site.xml 中配置的是 JobManager 重启次数的上限, flink-conf.xml 中的次数应该小于这个值。
