---
title: Kyuubi-从入门到跑路
tags:
  - 'Kyuubi'
categories:
  - [bigdata,Kyuubi]
date: 2022-10-30 16:24:47
updated: 2022-10-30 16:24:47
cover:
top_img:
description:
keywords:
---

> Kyuubi 将 Spark ThriftServer 的使用扩展为基于统一接口的多租户模型，并依靠多租户的概念与集群管理器交互，最终获得资源共享/隔离和数据安全的能力。Kyuubi Server 和 Engine 的松耦合架构大大提高了服务本身的并发性和服务稳定性。

## What-Kyuubi是什么

Apache Kyuubi (Incubating)，一个分布式和多租户网关，用于在 Lakehouse 上提供 Serverless SQL。

> 简单的来说Kyuubi就是一个SQL网关，用来将用户需要执行的SQL交给对应的计算引擎执行，如Spark、Flink等。作为一个优秀的网关，Kyuubi理所当然的实现了负载均衡、HA、多租户等功能。
>
> 正是这些功能，保证了Spark SQL可以真正的在企业内可用、好运、稳定的运行。

![image.png](https://cdn.nlark.com/yuque/0/2022/png/2500465/1667120616678-362b15b3-89ac-4b49-961f-71d1b0eeda4e.png)

## Why-为什么需要Kyuubi

- 当然是Spark Thrift Server不好用，甚至可以说在生产上不可用（不支持HA和多租户），Spark SQL无法大展拳脚，因此诞生了Kyuubi。

## How

 ### How: Kyuubi on Spark最佳实践

- spark-defaults.conf配置

```yaml
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Default system properties included when running spark-submit.
# This is useful for setting default environmental settings.

# Example:
# spark.master                     spark://master:7077
# spark.eventLog.enabled           true
# spark.eventLog.dir               hdfs://namenode:8021/directory
# spark.serializer                 org.apache.spark.serializer.KryoSerializer
# spark.driver.memory              5g
# spark.executor.extraJavaOptions  -XX:+PrintGCDetails -Dkey=value -Dnumbers="one two three"


## Spark on Yarn config
spark.master=yarn
spark.submit.deployMode=cluster
spark.executor.cores=1
spark.yarn.am.memory=512m
spark.driver.memory=1g
spark.driver.memoryOverheadFactor=0.10
spark.executor.memory=1g
spark.executor.memoryOverheadFactor=0.10

## Spark DRA config
spark.dynamicAllocation.enabled=true
# false if perfer shuffle tracking than ESS
spark.shuffle.service.enabled=true
# 理想情况下，三者的大小关系应为minExecutors<= initialExecutors< maxExecutors
spark.dynamicAllocation.initialExecutors=10
spark.dynamicAllocation.minExecutors=10
spark.dynamicAllocation.maxExecutors=500
# adjust spark.dynamicAllocation.executorAllocationRatio a bit lower to reduce the number of executors w.r.t. full parallelism.
spark.dynamicAllocation.executorAllocationRatio=0.5
# If one executor reached the maximum idle timeout, it will be removed.
spark.dynamicAllocation.executorIdleTimeout=60s
spark.dynamicAllocation.cachedExecutorIdleTimeout=30min
# true if perfer shuffle tracking than ESS
spark.dynamicAllocation.shuffleTracking.enabled=false
spark.dynamicAllocation.shuffleTracking.timeout=30min
# 如果 DRA 发现有待处理的任务积压超过超时，将请求新的执行程序，由以下配置控制。
spark.dynamicAllocation.schedulerBacklogTimeout=1s
spark.dynamicAllocation.sustainedSchedulerBacklogTimeout=1s
spark.cleaner.periodicGC.interval=5min


## Spark ESS config: DRA依赖于ESS，不过在Spark3后可以启用shuffleTracking后也可以启用DRA
#  spark.shuffle.service.enabled=true   开启Spark ESS，前面已配置
spark.shuffle.service.port=7337
spark.shuffle.useOldFetchProtocol=true


## Spark AQE config
spark.sql.adaptive.enabled=true
spark.sql.adaptive.forceApply=false
spark.sql.adaptive.logLevel=info
# 如果我们用HDFS读写数据，匹配HDFS的块大小应该是最好的选择，即128MB或256MB。
spark.sql.adaptive.advisoryPartitionSizeInBytes=256m
spark.sql.adaptive.coalescePartitions.enabled=true
spark.sql.adaptive.coalescePartitions.minPartitionNum=1
# 它代表合并之前的洗牌分区的初始数量。最好明确设置它而不是回退到spark.sql.shuffle.partitions.
spark.sql.adaptive.coalescePartitions.initialPartitionNum=8192
spark.sql.adaptive.fetchShuffleBlocksInBatch=true
spark.sql.adaptive.localShuffleReader.enabled=true
spark.sql.adaptive.skewJoin.enabled=true
spark.sql.adaptive.skewJoin.skewedPartitionFactor=5
spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes=400m
spark.sql.adaptive.nonEmptyPartitionRatioForBroadcastJoin=0.2
spark.sql.adaptive.optimizer.excludedRules
spark.sql.autoBroadcastJoinThreshold=-1


## Spark Doc: Tuning Guide
spark.serializer=org.apache.spark.serializer.KryoSerializer
spark.yarn.jars=hdfs://hadoop122:9000/spark-yarn/jars/*.jar
# TODO-Push-based shuffle overview待启用
```

## Extension

### 基于MySQL自定义认证

```scala
package cn.jxau

import org.apache.kyuubi.service.authentication.PasswdAuthenticationProvider

import java.sql.{Connection, DriverManager}
import javax.security.sasl.AuthenticationException

class SimpleAuthenticationProvider extends PasswdAuthenticationProvider {

  override def authenticate(user: String, password: String): Unit = {

    val pwd: String = ConnectionFactory().authById(user)

    if (pwd.equals(""))
      throw new AuthenticationException(s"auth fail, no user")
    else if (!pwd.equals(password))
      throw new AuthenticationException(s"auth fail, pwd wrong")
  }

}

case class ConnectionFactory() {

  val database = "test"
  val table = "tb_score"

  // 访问本地MySQL服务器，通过3306端口访问mysql数据库
  val url = s"jdbc:mysql://172.29.130.156:3306/$database?useUnicode=true&characterEncoding=utf-8&useSSL=false"
  //驱动名称
  val driver = "com.mysql.cj.jdbc.Driver"

  //用户名
  val username = "root"
  //密码
  val password = "1234"
  //初始化数据连接
  var connection: Connection = _

  def authById(id: String): String ={
    var pwd = ""

    try {
      //注册Driver
      Class.forName(driver)
      //得到连接
      connection = DriverManager.getConnection(url, username, password)
      val statement = connection.createStatement

      //执行查询语句，并返回结果
      val rs = statement.executeQuery(s"SELECT subject FROM $table WHERE userid = $id")

      //打印返回结果
      while (rs.next) {
        pwd = rs.getString("subject")
      }

      pwd match {
        case "" => ""
        case _ => pwd
      }

    } catch {
      case exception: Exception => {
        exception.printStackTrace()
        throw exception
      }
    }finally {
      if (connection != null){
        connection.close()
      }
    }
  }

  def apply(): ConnectionFactory = ConnectionFactory()

}
```

