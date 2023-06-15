---
title: Spark SQL合并小文件
tags:
  - 'spark'
categories:
  - [bigdata,spark]
top_img: 
date: 2023-03-08 19:54:07
updated: 2022-03-08 19:54:07
cover:
description:
keywords:
---

## 前言

Hive 表中太多的小文件会影响数据的查询性能和效率，同时加大了 HDFS NameNode 的压力。



## 方法1：Base Spark SQL Partitioning Hints

```sql
SELECT /*+ COALESCE(3) */ * FROM t;

SELECT /*+ REPARTITION(3) */ * FROM t;

SELECT /*+ REPARTITION(c) */ * FROM t;

SELECT /*+ REPARTITION(3, c) */ * FROM t;

SELECT /*+ REPARTITION_BY_RANGE(c) */ * FROM t;

SELECT /*+ REPARTITION_BY_RANGE(3, c) */ * FROM t;

SELECT /*+ REBALANCE */ * FROM t;

SELECT /*+ REBALANCE(3) */ * FROM t;

SELECT /*+ REBALANCE(c) */ * FROM t;

SELECT /*+ REBALANCE(3, c) */ * FROM t;

-- multiple partitioning hints
EXPLAIN EXTENDED SELECT /*+ REPARTITION(100), COALESCE(500), REPARTITION_BY_RANGE(3, c) */ * FROM t;
== Parsed Logical Plan ==
'UnresolvedHint REPARTITION, [100]
+- 'UnresolvedHint COALESCE, [500]
   +- 'UnresolvedHint REPARTITION_BY_RANGE, [3, 'c]
      +- 'Project [*]
         +- 'UnresolvedRelation [t]

== Analyzed Logical Plan ==
name: string, c: int
Repartition 100, true
+- Repartition 500, false
   +- RepartitionByExpression [c#30 ASC NULLS FIRST], 3
      +- Project [name#29, c#30]
         +- SubqueryAlias spark_catalog.default.t
            +- Relation[name#29,c#30] parquet

== Optimized Logical Plan ==
Repartition 100, true
+- Relation[name#29,c#30] parquet

== Physical Plan ==
Exchange RoundRobinPartitioning(100), false, [id=#121]
+- *(1) ColumnarToRow
   +- FileScan parquet default.t[name#29,c#30] Batched: true, DataFilters: [], Format: Parquet,
      Location: CatalogFileIndex[file:/spark/spark-warehouse/t], PartitionFilters: [],
      PushedFilters: [], ReadSchema: struct<name:string>
```



### `/*+ COALESCE() */`  VS  `/*+ REPARTITION() */`

翻阅代码可以得到，RDD 的 repartition 就是调用的 coalesce 函数,只是shuffle 参数设置为了true，我们的目的是减少小文件，所以这块可以使用 `coalesce`。

> The repartition algorithm does a **full shuffle** of the data and creates equal sized partitions of data. coalesce combines existing partitions to avoid a **full shuffle**.

### `/*+ REPARTITION() */` VS `/*+ REBALANCE() */`

Spark 3.2+ 引入了 Rebalance 操作，借助于 Spark AQE 来平衡分区，进行小分区合并和倾斜分区拆分，避免分区数据过大或过小，能够很好地处理小文件问题。 Rebalance的目的是为了在AQE阶段,根据spark.sql.adaptive.advisoryPartitionSizeInBytes进行分区的重新分区，防止数据倾斜。再加上SPARK-35786,就可以根据hint进行重分区。

一般在reparition用到的地方都可以Rebalance来替换，而且Rebalance有更好的文件大小的控制能力，更多的信息可以查看对应的 [spark-jira](https://issues.apache.org/jira/browse/SPARK-35725?spm=a2c6h.12873639.article-detail.7.1e1e6422yF136F)。

### 总结

对于合并小文件的场景，REBALANCE > COALESCE > REPARTITION.



## 方法2：Base Kyuubi Spark SQL Extensions

Kyuubi 对于 Spark 3.2+ 的优化，是在写入前插入 Rebalance 操作，对于动态分区，则指定动态分区列进行 Rebalance 操作。不再需要 spark.sql.optimizer.insertRepartitionNum 和spark.sql.optimizer.dynamicPartitionInsertionRepartitionNum 配置。与使用`/*+ REBALANCE() */` hint等效。

```yaml
# 配置Kyuubi Spark SQL Extensions
spark.sql.extensions=org.apache.kyuubi.sql.KyuubiSparkSQLExtension

# 开启RepartitionBeforeWrite优化（默认开启）
spark.sql.optimizer.insertRepartitionBeforeWrite.enabled=true

# 配置AQE 
spark.sql.adaptive.enabled=true 
spark.sql.adaptive.advisoryPartitionSizeInBytes=512m 
spark.sql.adaptive.coalescePartitions.minPartitionmum=1 
```

