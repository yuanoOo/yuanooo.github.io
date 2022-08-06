---
title: 测试Flink Doris Connector
tags:
  - 'Doris'
categories:
  - [bigdata,Doris]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2022-08-06 17:57:25
updated: 2022-08-06 17:57:25
cover:
description:
keywords:
---

> 利用Flink Doris Connector将Kafka中的数据实时导入到Doris
>
> 该Connector支持Flink SQL和DataStream API
>
> **注意：**
>
> 1. 修改和删除只支持在 Unique Key 模型上
> 2. 目前的删除是支持 Flink CDC 的方式接入数据实现自动删除，如果是其他数据接入的方式删除需要自己实现。Flink CDC 的数据删除使用方式参照本文档最后一节



### Maven

```xml
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-java</artifactId>
    <version>${flink.version}</version>
    <scope>provided</scope>
</dependency>
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-streaming-java_${scala.version}</artifactId>
    <version>${flink.version}</version>
    <scope>provided</scope>
</dependency>
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-clients_${scala.version}</artifactId>
    <version>${flink.version}</version>
    <scope>provided</scope>
</dependency>
<!-- flink table -->
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-table-planner_${scala.version}</artifactId>
    <version>${flink.version}</version>
    <scope>provided</scope>
</dependency>

<!-- flink-doris-connector -->
<dependency>
  <groupId>org.apache.doris</groupId>
  <artifactId>flink-doris-connector-1.14_2.12</artifactId>
  <version>1.1.0</version>
</dependency>  
```



### 参数配置

Flink Doris Connector Sink 的内部实现是通过 `Stream Load` 服务向 Doris 写入数据, 同时也支持 `Stream Load` 请求参数的配置设置，具体参数可参考[这里](https://doris.apache.org/zh-CN/docs/data-operate/import/import-way/stream-load-manual)，配置方法如下：

- SQL 使用 `WITH` 参数 `sink.properties.` 配置
- DataStream 使用方法`DorisExecutionOptions.builder().setStreamLoadProp(Properties)`配置



### 示例

```scala
package cn.jxau.yuan


import cn.jxau.yuan.common.Config
import org.apache.doris.flink.cfg.{DorisExecutionOptions, DorisOptions, DorisReadOptions}
import org.apache.doris.flink.sink.DorisSink
import org.apache.doris.flink.sink.writer.SimpleStringSerializer
import org.apache.flink.api.common.eventtime.WatermarkStrategy
import org.apache.flink.api.common.serialization.SimpleStringSchema
import org.apache.flink.connector.kafka.source.KafkaSource
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer
import org.apache.flink.streaming.api.environment.CheckpointConfig
import org.apache.flink.streaming.api.scala._

import java.util.Properties


object KafkaConnectTest {

  def main(args: Array[String]): Unit = {
    val env: StreamExecutionEnvironment = StreamExecutionEnvironment.getExecutionEnvironment
    env.enableCheckpointing(10000)
    env.getCheckpointConfig.setExternalizedCheckpointCleanup(CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION)


    val kafkaSource: KafkaSource[String] = KafkaSource.builder[String]
      .setBootstrapServers(Config.broker)
      .setTopics("input-topic")
      .setGroupId("my-group")
      .setStartingOffsets(OffsetsInitializer.earliest)
      .setValueOnlyDeserializer(new SimpleStringSchema)
      .build

    env.fromSource(kafkaSource, WatermarkStrategy.noWatermarks[String](), "Kafka Source")
      .sinkTo(buildDorisSink())

    env.execute()
  }

  def buildDorisSink(): DorisSink[String]  = {
    //sink config
    val builder: DorisSink.Builder[String] = DorisSink.builder();
    val dorisBuilder: DorisOptions.Builder = DorisOptions.builder();
    dorisBuilder.setFenodes("127.0.0.1:8030")
      .setTableIdentifier("db.table")
      .setUsername("root")
      .setPassword("password");


    val pro: Properties = new Properties();
    //json data format
    pro.setProperty("format", "json");
    pro.setProperty("read_json_by_line", "true");


    val executionOptions: DorisExecutionOptions  = DorisExecutionOptions.builder()
      .setLabelPrefix("label-doris") //streamload label prefix,
      .setStreamLoadProp(pro)
      .build()

    builder.setDorisReadOptions(DorisReadOptions.builder().build())
      .setDorisExecutionOptions(executionOptions)
      .setSerializer(new SimpleStringSerializer()) //serialize according to string
      .setDorisOptions(dorisBuilder.build())
      .build()
  }
}

```

