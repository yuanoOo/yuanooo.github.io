---
title: 初识paimon && Spark Catalog
tags:
  - 'paimon'
categories:
  - [bigdata,paimon]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2023-04-08 17:57:25
updated: 2022-04-08 17:57:25
cover:
description:
keywords:
---

## 前言

由于公司的业务场景涉及海量的数据更新和删除，因此一直对擅长处理海量数据更新的数据湖格式Apache paimon感兴趣。虽然Hudi对数据更新支持的也不错，但是经过测试，无论是吞吐量还是资源消耗都不能令人满意。究其根本像hudi、iceberg等数据湖格式在处理数据更新上都是通过简单粗暴的合并文件实现的，存在较大的写放大问题。

在了解到Apache paimon是通过LSM实现海量数据更新后，可以预见的到海量数据更新对paimon不会存在问题，因为像使用LSM技术的kudu、doris、hbase等存储引擎都是非常成熟且久经考验的。经过测试Apache paimon的吞吐量是hudi MOR表的3-5倍，同时资源占用(IO和CPU和内存)也大幅下降。

## PR on Paimon

- 修复Date类型作为分区值的格式化问题，由于可能会造成与老版本(Flink Table Store)的兼容性问题，暂时无法进行合并。但是对于我们来说没有兼容性问题，因此在我们的内部版本中使用。https://github.com/apache/incubator-paimon/pull/853

## Spark on Paimon

由于Apache Paimon的前身是Flink Table Store，显然Paimon和Flink一起使用是最佳方案，但批处理主要还是依靠Spark来实现，因此测试Spark on Paimon将是重点工作。



### Spark SQL join hive表和paimon表

其中paimon表只用作ods层，实时写入cdc数据，dwd层还是用hive表，并且统一格式为parquet，因为spark对parquet格式支持的更好。paimon表当前的默认存储格式为orc，因此创建paimon表的时候，需要指定format='parquet'。

```sql
select 
    * 
from  paimon.default.my_table paimon join spark_catalog.default.user_orc hive
on
    paimon.user_id = hive.tid;
```

### spark paimon catalog

paimon和hudi在实现spark catalog上有所不同，如下所示：

```shell
# hudi
spark-sql --packages org.apache.hudi:hudi-spark3.2-bundle_2.12:0.13.0 \
--conf 'spark.serializer=org.apache.spark.serializer.KryoSerializer' \
--conf 'spark.sql.extensions=org.apache.spark.sql.hudi.HoodieSparkSessionExtension' \
--conf 'spark.sql.catalog.spark_catalog=org.apache.spark.sql.hudi.catalog.HoodieCatalog'

# paimon
spark-sql ... \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=/tmp \
    --conf spark.sql.catalog.paimon.metastore=hive \
    --conf spark.sql.catalog.paimon.uri=thrift://localhost:9083
```

可以发现hudi的catalog名称就是spark默认的spark_catalog，其默认元数据为hive metastore。而paimon实现的catalog名称为paimon，因此需要先执行`use paimon.default;`切换到paimon catalog下，才能访问paimon表。之后执行`use spark_catalog;`访问hive表。或加上catalog前缀，`paimon.default.my_table`和`spark_catalog.default.user_orc`,以同时跨catalog访问表。



## Flink on Paimon最佳实践

- 使用Flink `STATEMENT SET`,重用数据源，减少资源消耗。

  ```sql
  set 'table.optimizer.source.report-statistics-enabled' = 'true';
  set 'table.optimizer.reuse-source-enabled' = 'true';
  
  EXECUTE STATEMENT SET
  BEGIN
      insert into paimon_table_1 select name,age,city from kafka_source_1;
      insert into paimon_table_2 select name,age,city from kafka_source_1;
  END;
  ```

- Batch-Read的延迟和checkpoint间隔时间强相关，默认配置下，批读的延迟等于CK的间隔时间。

  > 1、当配置`scan.mode = compacted-full`时，只会读取压缩完成的快照，可以提高读性能，但是延迟也增大了。同时配置`full-compaction.delta-commits = 5`后，假如CK间隔为3min，则延迟为5 * 3 + 5 * ck的持续时间，平均延迟差不多就是15分钟。
  >
  > 2、默认情况下scan.mode读取最新的快照，批读的延迟等于CK的间隔时间。
  >
  > 3、full compaction非常消耗资源，影响写入性能，同时造成CK持续时间过长，影响了作业稳定性，也增加了数据延迟。我们可以在流作业中不配置，而是用Dedicated Compaction Job进行压缩，或者将`full-compaction.delta-commits = 120`尽量调大，减少性能影响。

- 单独设置bucket-key，而不是主键，可以增加除了主键外的一些索引列，提高性能。

- 虽然Paimon默认`file-format`为ORC格式，但是实践好像Parquet格式更稳定。

  