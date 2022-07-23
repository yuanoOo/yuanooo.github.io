---
title: 初识Doris
tags:
  - 'Doris'
categories:
  - [bigdata,Doris]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2022-07-23 06:19:04
updated: 2022-07-23 06:19:04
cover:
description:
keywords:
---

>- MPP（ Massively Parallel Processing - 大规模并行处理）Based数据库。
>- Doris 采用 MySQL 协议进行通信，用户可通过 MySQL Client 或者 MySQL JDBC 连接到 Doris 集群。



## 建表语句

- Range Partition

  ```sql
  CREATE TABLE IF NOT EXISTS example_db.expamle_range_tbl
  (
   `user_id` LARGEINT NOT NULL COMMENT "用户 id",
   `date` DATE NOT NULL COMMENT "数据灌入日期时间",
   `timestamp` DATETIME NOT NULL COMMENT "数据灌入的时间戳",
   `city` VARCHAR(20) COMMENT "用户所在城市",
   `age` SMALLINT COMMENT "用户年龄",
   `sex` TINYINT COMMENT "用户性别",
   `last_visit_date` DATETIME REPLACE DEFAULT "1970-01-01 
  00:00:00" COMMENT "用户最后一次访问时间",
   `cost` BIGINT SUM DEFAULT "0" COMMENT "用户总消费",
   `max_dwell_time` INT MAX DEFAULT "0" COMMENT "用户最大停留时间",
   `min_dwell_time` INT MIN DEFAULT "99999" COMMENT "用户最小停留时间"
  )
  ENGINE=olap
  AGGREGATE KEY(`user_id`, `date`, `timestamp`, `city`, `age`, `sex`)
  PARTITION BY RANGE(`date`)
  (
   PARTITION `p201701` VALUES LESS THAN ("2017-02-01"),
   PARTITION `p201702` VALUES LESS THAN ("2017-03-01"),
   PARTITION `p201703` VALUES LESS THAN ("2017-04-01")
  )
  DISTRIBUTED BY HASH(`user_id`) BUCKETS 16
  PROPERTIES
  (
   "replication_num" = "3",
   "storage_medium" = "SSD",
   "storage_cooldown_time" = "2018-01-01 12:00:00"
  );
  
  ```

- List Partition

  ```sql
  CREATE TABLE IF NOT EXISTS example_db.expamle_list_tbl
  (
   `user_id` LARGEINT NOT NULL COMMENT "用户 id",
   `date` DATE NOT NULL COMMENT "数据灌入日期时间",
   `timestamp` DATETIME NOT NULL COMMENT "数据灌入的时间戳",
   `city` VARCHAR(20) COMMENT "用户所在城市",
   `age` SMALLINT COMMENT "用户年龄",
   `sex` TINYINT COMMENT "用户性别",
   `last_visit_date` DATETIME REPLACE DEFAULT "1970-01-01 
  00:00:00" COMMENT "用户最后一次访问时间",
   `cost` BIGINT SUM DEFAULT "0" COMMENT "用户总消费",
   `max_dwell_time` INT MAX DEFAULT "0" COMMENT "用户最大停留时间",
   `min_dwell_time` INT MIN DEFAULT "99999" COMMENT "用户最小停留时
  间"
  )
  ENGINE=olap
  AGGREGATE KEY(`user_id`, `date`, `timestamp`, `city`, `age`, `sex`)
  PARTITION BY LIST(`city`)
  (
   PARTITION `p_cn` VALUES IN ("Beijing", "Shanghai", "Hong Kong"),
   PARTITION `p_usa` VALUES IN ("New York", "San Francisco"),
   PARTITION `p_jp` VALUES IN ("Tokyo")
  )
  DISTRIBUTED BY HASH(`user_id`) BUCKETS 16
  PROPERTIES
  (
   "replication_num" = "3",
   "storage_medium" = "SSD",
   "storage_cooldown_time" = "2018-01-01 12:00:00"
  );
  ```

  

## 数据模型

Doris 的数据模型主要分为 3 类：Aggregate、Uniq、Duplicate

### Aggregate 模型

表中的列按照是否设置了 AggregationType，分为 Key（维度列）和 Value（指标列）。没有设置 AggregationType 的称为 Key，设置了 AggregationType 的称为 Value。
当我们导入数据时，对于 Key 列相同的行会聚合成一行，而 Value 列会按照设置的AggregationType 进行聚合。AggregationType 目前有以下四种聚合方式：

- ➢ SUM：求和，多行的 Value 进行累加。
- ➢ REPLACE：替代，下一批数据中的 Value 会替换之前导入过的行中的 Value。
     REPLACE_IF_NOT_NULL ：当遇到 null 值则不更新。
- ➢ MAX：保留最大值。
- ➢ MIN：保留最小值。

数据的聚合，在 Doris 中有如下三个阶段发生：
- （1）每一批次数据导入的 ETL 阶段。该阶段会在每一批次导入的数据内部进行聚合。
- （2）底层 BE 进行数据 Compaction 的阶段。该阶段，BE 会对已导入的不同批次的数据进行进一步的聚合。
- （3）数据查询阶段。在数据查询时，对于查询涉及到的数据，会进行对应的聚合。

数据在不同时间，可能聚合的程度不一致。比如一批数据刚导入时，可能还未与之前已存在的数据进行聚合。但是对于用户而言，用户只能查询到聚合后的数据。即不同的聚合程度对于用户查询而言是透明的。用户需始终认为数据以最终的完成的聚合程度存在，而不应假设某些聚合还未发生。（可参阅聚合模型的局限性一节获得更多详情。）

### Uniq 模型

在某些多维分析场景下，用户更关注的是如何保证 Key 的唯一性，即如何获得 Primary  Key 唯一性约束。因此，我们引入了 Uniq 的数据模型。该模型本质上是聚合模型的一个特 例，也是一种简化的表结构表示方式。

Uniq 模型完全可以用聚合模型中的 REPLACE 方式替代。其内部的实现方式和数据存 储方式也完全一样。

### Duplicate 模型

在某些多维分析场景下，数据既没有主键，也没有聚合需求。Duplicate 数据模型可以 满足这类需求。数据完全按照导入文件中的数据进行存储，不会有任何聚合。即使两行数据 完全相同，也都会保留。 而在建表语句中指定的 `DUPLICATE KEY`，只是用来指明底层数 据按照那些列进行排序。

### 数据模型的选择建议

因为数据模型在建表时就已经确定，且无法修改。所以，选择一个合适的数据模型非常 重要。 

（1）Aggregate 模型可以通过预聚合，极大地降低聚合查询时所需扫描的数据量和查询 的计算量，非常适合有固定模式的报表类查询场景。但是该模型对 count(*) 查询很不友好。 **同时因为固定了 Value 列上的聚合方式，在进行其他类型的聚合查询时，需要考虑语意正确 性。**

（2）Uniq 模型针对需要唯一主键约束的场景，可以保证主键唯一性约束。**但是无法利 用 ROLLUP 等预聚合带来的查询优势（因为本质是 REPLACE，没有 SUM 这种聚合方式）。** 

（3）Duplicate 适合任意维度的 Ad-hoc 查询。虽然同样无法利用预聚合的特性，但是不 受聚合模型的约束，可以发挥列存模型的优势（只读取相关列，而不需要读取所有 Key 列）

## Rollup

ROLLUP 在多维分析中是“上卷”的意思，即将数据按某种指定的粒度进行进一步聚 合。

### 基本概念

在 Doris 中，我们将用户通过建表语句创建出来的表称为 Base 表（Base Table）。Base  表中保存着按用户建表语句指定的方式存储的基础数据。 

在 Base 表之上，我们可以创建任意多个 ROLLUP 表。这些 ROLLUP 的数据是基于 Base  表产生的，并且在物理上是独立存储的。 ROLLUP 表的基本作用，在于在 Base 表的基础上，获得更粗粒度的聚合数据

###  Duplicate 模型中的 ROLLUP

因为 Duplicate 模型没有聚合的语意。所以该模型中的 ROLLUP，已经失去了“上卷” 这一层含义。而仅仅是作为调整列顺序，以命中前缀索引的作用。下面详细介绍前缀索引， 以及如何使用 ROLLUP 改变前缀索引，以获得更好的查询效率。

#### 前缀索引

不同于传统的数据库设计，Doris 不支持在任意列上创建索引。Doris 这类 MPP 架构的 OLAP 数据库，通常都是通过提高并发，来处理大量数据的。 

本质上，Doris 的数据存储在类似 SSTable（Sorted String Table）的数据结构中。该结构 是一种有序的数据结构，可以按照指定的列进行排序存储。在这种数据结构上，以排序列作 为条件进行查找，会非常的高效。 

在 Aggregate、Uniq 和 Duplicate 三种数据模型中。底层的数据存储，是按照各自建表 语句中，AGGREGATE KEY、UNIQ KEY 和 DUPLICATE KEY 中指定的列进行排序存储 的。而**前缀索引，即在排序的基础上，实现的一种根据给定前缀列，快速查询数据的索引方 式。**

#### ROLLUP 调整前缀索引

因为建表时已经指定了列顺序，所以一个表只有一种前缀索引。这对于使用其他不能命 中前缀索引的列作为条件进行的查询来说，效率上可能无法满足需求。因此，我们可以通过 创建 ROLLUP 来人为的调整列顺序。举例说明。

### ROLLUP 的几点说明

⚫ ROLLUP 最根本的作用是提高某些查询的查询效率（无论是通过聚合来减少数据 量，还是修改列顺序以匹配前缀索引）。因此 ROLLUP 的含义已经超出了“上卷” 的范围。这也是为什么在源代码中，将其命名为 Materialized Index（物化索引）的 原因。

⚫ ROLLUP 是附属于 Base 表的，可以看做是 Base 表的一种辅助数据结构。用户可以 在 Base 表的基础上，创建或删除 ROLLUP，但是不能在查询中显式的指定查询某 ROLLUP。是否命中 ROLLUP 完全由 Doris 系统自动决定。 

⚫ ROLLUP 的数据是独立物理存储的。因此，创建的 ROLLUP 越多，占用的磁盘空 间也就越大。同时对导入速度也会有影响（导入的 ETL 阶段会自动产生所有 ROLLUP 的数据），但是不会降低查询效率（只会更好）。 

⚫ ROLLUP 的数据更新与 Base 表是完全同步的。用户无需关心这个问题。

⚫ ROLLUP 中列的聚合方式，与 Base 表完全相同。在创建 ROLLUP 无需指定，也不 能修改。 

⚫ 查询能否命中 ROLLUP 的一个必要条件（非充分条件）是，查询所涉及的所有列 （包括 select list 和 where 中的查询条件列等）都存在于该 ROLLUP 的列中。否 则，查询只能命中 Base 表。 

⚫ 某些类型的查询（如 count(*)）在任何条件下，都无法命中 ROLLUP。具体参见接 下来的聚合模型的局限性一节。

⚫ 可以通过 EXPLAIN your_sql; 命令获得查询执行计划，在执行计划中，查看是否命 中 ROLLUP。

⚫ 可以通过 DESC tbl_name ALL; 语句显示 Base 表和所有已创建完成的 ROLLUP。



## 物化视图

物化视图就是包含了查询结果的数据库对象，可能是对远程数据的本地 copy，也可能 是一个表或多表 join 后结果的行或列的子集，也可能是聚合后的结果。说白了，就是预先存 储查询结果的一种数据库对象。

在 Doris 中的物化视图，就是查询结果预先存储起来的特殊的表。 

物化视图的出现主要是为了满足用户，既能对原始明细数据的任意维度分析，也能快速 的对固定维度进行分析查询。

### 优势

⚫ 对于那些经常重复的使用相同的子查询结果的查询性能大幅提升。 

⚫ Doris 自动维护物化视图的数据，无论是新的导入，还是删除操作都能保证 base 表 和物化视图表的数据一致性。无需任何额外的人工维护成本。 

⚫ 查询时，会自动匹配到最优物化视图，并直接从物化视图中读取数据。 自动维护物化视图的数据会造成一些维护开销，会在后面的物化视图的局限性中展开说 明。

### 物化视图 VS Rollup

在没有物化视图功能之前，用户一般都是使用 Rollup 功能通过预聚合方式提升查询效 率的。但是 Rollup 具有一定的局限性，他不能基于明细模型做预聚合。 

物化视图则在覆盖了 Rollup 的功能的同时，还能支持更丰富的聚合函数。所以物化视 图其实是 Rollup 的一个超集。 

也就是说，之前 ALTER TABLE ADD ROLLUP 语法支持的功能现在均可以通过 CREATE MATERIALIZED VIEW 实现。

### 物化视图原理

Doris 系统提供了一整套对物化视图的 DDL 语法，包括创建，查看，删除。DDL 的语 法和 PostgreSQL, Oracle 都是一致的。但是 Doris 目前创建物化视图只能在单表操作，不支 持 join。
