---
title: 通过Flink-SQL，将Kafka中的Oracle-CDC-Log同步到Doris
tags:
  - Flink
categories:
  - - bigdata
    - Flink
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
abbrlink: 38552
date: 2022-08-14 23:14:56
updated: 2022-08-14 23:14:56
cover:
description:
keywords:
---

## 前言
- Oracle的binlog日志已经由DBA通过OGG同步到Kafka中了，因此用不到Flink CDC
- 同步到Kafka中的JSON样式
  ```json
  {
  "before": {
    "id": 111,
    "name": "scooter",
    "description": "Big 2-wheel scooter",
    "weight": 5.18
  },
  "after": {
    "id": 111,
    "name": "scooter",
    "description": "Big 2-wheel scooter",
    "weight": 5.15
  },
  "op_type": "U",
  "op_ts": "2020-05-13 15:40:06.000000",
  "current_ts": "2020-05-13 15:40:07.000000",
  "primary_keys": [
    "id"
  ],
  "pos": "00000000000000000000143",
  "table": "PRODUCTS"
  }
  ```

## Flink SQL
> 需要下载以下Jar包，放在{flink_home}/lib/下
> flink-sql-connector-kafka_2.12-1.14.5.jar
> flink-json-1.15.1.jar
> flink-doris-connector-1.14_2.12-1.1.0.jar

- 开启CheckPoint：`SET 'execution.checkpointing.interval' = '10min';`

- 创建Kafka数据源表，设置`'format' = 'ogg-json'`，只有`org.apache.flink.flink-json-1.15.1`中以上才支持ogg-json fromat
```sql
CREATE TABLE topic_products (
  id INT,
  name STRING,
  description STRING,
  weight DECIMAL(10, 2)
) WITH (
  'connector' = 'kafka',
  'topic' = 'products_ogg_1',
  'properties.bootstrap.servers' = '172.30.160.5:9092',
  'properties.group.id' = 'testGroup',
  'format' = 'ogg-json',
  'scan.startup.mode' = 'earliest-offset',
  'ogg-json.ignore-parse-errors' = 'true'
);
```

- 创建Doris-Sink表
```sql
CREATE TABLE doris_sink (
id INT,
name STRING,
description STRING,
weight DECIMAL(10, 2)
)
WITH (
  'connector' = 'doris',
  'fenodes' = '172.30.160.5:8030',
  'table.identifier' = 'test.product',
  'username' = 'root',
  'password' = '',
  'sink.properties.format' = 'json',
  'sink.properties.read_json_by_line' = 'true',
  'sink.enable-delete' = 'true',
  'sink.label-prefix' = 'doris_label'
);
```

- 执行`INSERT into doris_sink select * from topic_products;`语句，写入Doris

## Code Repo

> 1. **bin/sql-client.sh embedded -i init_file -f file -s yarn-session** 
> 2. Execute SQL Files 

```sql
-- Define available catalogs

CREATE CATALOG MyCatalog
  WITH (
    'type' = 'hive'
  );

USE CATALOG MyCatalog;

-- Define available database

CREATE DATABASE MyDatabase;

USE MyDatabase;

-- Define TABLE

CREATE TABLE MyTable(
  MyField1 INT,
  MyField2 STRING
) WITH (
  'connector' = 'filesystem',
  'path' = '/path/to/something',
  'format' = 'csv'
);

-- Define VIEW

CREATE VIEW MyCustomView AS SELECT MyField2 FROM MyTable;

-- Define user-defined functions here.

CREATE FUNCTION foo.bar.AggregateUDF AS myUDF;

-- Properties that change the fundamental execution behavior of a table program.

SET 'execution.runtime-mode' = 'streaming'; -- execution mode either 'batch' or 'streaming'
SET 'sql-client.execution.result-mode' = 'table'; -- available values: 'table', 'changelog' and 'tableau'
SET 'sql-client.execution.max-table-result.rows' = '10000'; -- optional: maximum number of maintained rows
SET 'parallelism.default' = '1'; -- optional: Flink's parallelism (1 by default)
SET 'pipeline.auto-watermark-interval' = '200'; --optional: interval for periodic watermarks
SET 'pipeline.max-parallelism' = '10'; -- optional: Flink's maximum parallelism
SET 'table.exec.state.ttl' = '1000'; -- optional: table program's idle state time
SET 'restart-strategy' = 'fixed-delay';

-- Configuration options for adjusting and tuning table programs.

SET 'table.optimizer.join-reorder-enabled' = 'true';
SET 'table.exec.spill-compression.enabled' = 'true';
SET 'table.exec.spill-compression.block-size' = '128kb';
```



```sql
CREATE TEMPORARY TABLE users (
  user_id BIGINT,
  user_name STRING,
  user_level STRING,
  region STRING,
  PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
  'connector' = 'upsert-kafka',
  'topic' = 'users',
  'properties.bootstrap.servers' = '...',
  'key.format' = 'csv',
  'value.format' = 'avro'
);

-- set sync mode
SET 'table.dml-sync' = 'true';

-- set the job name
SET 'pipeline.name' = 'SqlJob';

-- set the queue that the job submit to
SET 'yarn.application.queue' = 'root';

-- set the job parallelism
SET 'parallelism.default' = '100';

-- restore from the specific savepoint path
SET 'execution.savepoint.path' = '/tmp/flink-savepoints/savepoint-cca7bc-bb1e257f0dab';

INSERT INTO pageviews_enriched
SELECT *
FROM pageviews AS p
LEFT JOIN users FOR SYSTEM_TIME AS OF p.proctime AS u
ON p.user_id = u.user_id;
```

