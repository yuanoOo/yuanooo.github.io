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

由于公司的业务场景涉及海量的数据更新和删除，因此一直对擅长处理海量数据更新的数据湖格式Apache paimon感兴趣。虽然Hudi对数据更新支持的也不错，但是经过测试，无论是吞吐量还是资源消耗都不能令人满意。究其根本像hudi、iceberg等数据湖格式在处理数据更新上都是通过合并文件实现的，或多或少都存在一定的写放大的问题。

在了解到Apache paimon是通过LSM实现海量数据更新后，可以预见的到海量数据更新对paimon不会存在问题，因为像使用LSM技术的kudu、doris、hbase等存储引擎都是非常成熟且久经考验的。经过测试Apache paimon的吞吐量是hudi MOR表的3-5倍，同时资源占用(IO和CPU和内存)也大幅下降。



## Spark on Paimon

由于Apache Paimon的前身是Flink Table Store，显然Paimon和Flink一起使用是最佳方案，但是公司批处理主要还是依靠Spark来实现，因此测试Spark on Paimon将是重点工作。



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