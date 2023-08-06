---
title: 初入Flink Table && SQL
tags:
  - Flink
categories:
  - - bigdata
    - Flink
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
abbrlink: 46784
date: 2022-08-13 17:55:05
updated: 2022-08-13 17:55:05
cover:
description:
keywords:
---

# QuickStart

- Table API 和 SQL 需要引入的依赖有两个：planner 和 bridge。

  ```xml
      <dependency>
          <groupId>org.apache.flink</groupId>
          <artifactId>flink-table-api-scala-bridge_${scala.version}</artifactId>
          <version>${flink.version}</version>
      </dependency>
      <dependency>
          <groupId>org.apache.flink</groupId>
          <artifactId>flink-table-planner_${scala.version}</artifactId>
          <version>${flink.version}</version>
      </dependency>
  ```

- > 老版本planner已经被废除，只剩下blink
  >
  > The old planner has been removed in Flink 1.14. Please upgrade your table program to use the default planner (previously called the 'blink' planner).

# Flink CDC SQL Demo

- 1、下载Flink，下载`flink-sql-connector-mysql-cdc-2.3-SNAPSHOT.jar`依赖包，并将它们放到目录 `{flink_home}/lib/` 下.

- 2、在 MySQL 数据库中准备数据，创建数据库和表 `products`，`orders`，并插入数据

  ```sql
  -- MySQL
  CREATE DATABASE mydb;
  USE mydb;
  CREATE TABLE products (
    id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(512)
  );
  ALTER TABLE products AUTO_INCREMENT = 101;
  
  INSERT INTO products
  VALUES (default,"scooter","Small 2-wheel scooter"),
         (default,"car battery","12V car battery"),
         (default,"12-pack drill bits","12-pack of drill bits with sizes ranging from #40 to #3"),
         (default,"hammer","12oz carpenter's hammer"),
         (default,"hammer","14oz carpenter's hammer"),
         (default,"hammer","16oz carpenter's hammer"),
         (default,"rocks","box of assorted rocks"),
         (default,"jacket","water resistent black wind breaker"),
         (default,"spare tire","24 inch spare tire");
  
  CREATE TABLE orders (
    order_id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY,
    order_date DATETIME NOT NULL,
    customer_name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 5) NOT NULL,
    product_id INTEGER NOT NULL,
    order_status BOOLEAN NOT NULL -- Whether order has been placed
  ) AUTO_INCREMENT = 10001;
  
  INSERT INTO orders
  VALUES (default, '2020-07-30 10:08:22', 'Jark', 50.50, 102, false),
         (default, '2020-07-30 10:11:09', 'Sally', 15.00, 105, false),
         (default, '2020-07-30 12:00:30', 'Edward', 25.25, 106, false);
  ```

- 3、启动 Flink 集群和 Flink SQL CLI

  > ./bin/start-cluster.sh
  > ./bin/sql-client.sh

- 4、在 Flink SQL CLI 中使用 Flink DDL 创建表

  >首先，开启 checkpoint，每隔3秒做一次 checkpoint
  >
  >```
  >-- Flink SQL                   
  >Flink SQL> SET execution.checkpointing.interval = 3s;
  >```
  >
  >然后, 对于数据库中的表 `products`, `orders`, `shipments`， 使用 Flink SQL CLI 创建对应的表，用于同步这些底层数据库表的数据
  >
  >```sql
  >-- Flink SQL
  >Flink SQL> CREATE TABLE products (
  >    id INT,
  >    name STRING,
  >    description STRING,
  >    PRIMARY KEY (id) NOT ENFORCED
  >  ) WITH (
  >    'connector' = 'mysql-cdc',
  >    'hostname' = 'localhost',
  >    'port' = '3306',
  >    'username' = 'root',
  >    'password' = '1234',
  >    'database-name' = 'mydb',
  >    'table-name' = 'products'
  >  );
  >
  >Flink SQL> CREATE TABLE orders (
  >   order_id INT,
  >   order_date TIMESTAMP(0),
  >   customer_name STRING,
  >   price DECIMAL(10, 5),
  >   product_id INT,
  >   order_status BOOLEAN,
  >   PRIMARY KEY (order_id) NOT ENFORCED
  > ) WITH (
  >   'connector' = 'mysql-cdc',
  >   'hostname' = 'localhost',
  >   'port' = '3306',
  >   'username' = 'root',
  >   'password' = '1234',
  >   'database-name' = 'mydb',
  >   'table-name' = 'orders'
  > );
  >```



# SQL Client

- CLI 为维护和可视化结果提供**三种模式**。

- **表格模式**（table mode）在内存中实体化结果，并将结果用规则的分页表格可视化展示出来。执行如下命令启用：

  ```text
  SET 'sql-client.execution.result-mode' = 'table';
  ```

  **变更日志模式**（changelog mode）不会实体化和可视化结果，而是由插入（`+`）和撤销（`-`）组成的持续查询产生结果流。

  ```text
  SET 'sql-client.execution.result-mode' = 'changelog';
  ```

  **Tableau模式**（tableau mode）更接近传统的数据库，会将执行的结果以制表的形式直接打在屏幕之上。具体显示的内容会取决于作业 执行模式的不同(`execution.type`)：

  ```text
  SET 'sql-client.execution.result-mode' = 'tableau';
  ```



# MySQL开启binlog

- 找到my.cnf文件

  > mysql --help | grep 'Default options' -A 1

```yaml
#第一种方式:
#开启binlog日志
log_bin=ON
#binlog日志的基本文件名
log_bin_basename=/var/lib/mysql/mysql-bin
#binlog文件的索引文件，管理所有binlog文件
log_bin_index=/var/lib/mysql/mysql-bin.index
#配置serverid
server-id=1

#第二种方式:
#此一行等同于上面log_bin三行
log-bin=/var/lib/mysql/mysql-bin
#配置serverid
server-id=1

# Demo
server-id=1
log-bin=mysql-bin
binlog_format=row
binlog-do-db=mydb
```



# Code Repo

- ```scala
      // 从命令参数中读取hostname和port
      val paramTool: ParameterTool = ParameterTool.fromArgs(args)
      val hostname: String = paramTool.get("host")
      val port: Int = paramTool.getInt("port")
  ```
