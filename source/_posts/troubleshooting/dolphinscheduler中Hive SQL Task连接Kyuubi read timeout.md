---
title: 修复dolphinscheduler Hive SQL数据源连接Kyuubi偶现Read timed out错误
tags:
  - 'Troubleshooting'
  - 'dolphinscheduler'
categories:
  - [Troubleshooting]
top_img: 
date: 2023-06-14 17:57:25
updated: 2023-06-14 17:57:25
cover:
description:
keywords:
---

## 前言

dolphinscheduler中利用Hive SQL数据源连接Kyuubi偶现Read timed out错误，错误日志如下：

```text
[ERROR] 2023-06-08 17:39:06.166 +0800 - Task execute failed, due to meet an exception
org.apache.dolphinscheduler.plugin.task.api.TaskException: Execute sql task failed
	at org.apache.dolphinscheduler.plugin.task.sql.SqlTask.handle(SqlTask.java:168)
	at org.apache.dolphinscheduler.server.worker.runner.DefaultWorkerDelayTaskExecuteRunnable.executeTask(DefaultWorkerDelayTaskExecuteRunnable.java:49)
	at org.apache.dolphinscheduler.server.worker.runner.WorkerTaskExecuteRunnable.run(WorkerTaskExecuteRunnable.java:174)
	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
	at com.google.common.util.concurrent.TrustedListenableFutureTask$TrustedFutureInterruptibleTask.runInterruptibly(TrustedListenableFutureTask.java:131)
	at com.google.common.util.concurrent.InterruptibleTask.run(InterruptibleTask.java:74)
	at com.google.common.util.concurrent.TrustedListenableFutureTask.run(TrustedListenableFutureTask.java:82)
	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
	at java.lang.Thread.run(Thread.java:748)
Caused by: java.sql.SQLException: org.apache.thrift.transport.TTransportException: java.net.SocketTimeoutException: Read timed out
	at org.apache.hive.jdbc.HiveStatement.runAsyncOnServer(HiveStatement.java:323)
	at org.apache.hive.jdbc.HiveStatement.execute(HiveStatement.java:253)
	at org.apache.hive.jdbc.HiveStatement.executeUpdate(HiveStatement.java:490)
	at org.apache.hive.jdbc.HivePreparedStatement.executeUpdate(HivePreparedStatement.java:122)
	at com.zaxxer.hikari.pool.ProxyPreparedStatement.executeUpdate(ProxyPreparedStatement.java:61)
	at com.zaxxer.hikari.pool.HikariProxyPreparedStatement.executeUpdate(HikariProxyPreparedStatement.java)
	at org.apache.dolphinscheduler.plugin.task.sql.SqlTask.executeUpdate(SqlTask.java:312)
	at org.apache.dolphinscheduler.plugin.task.sql.SqlTask.executeFuncAndSql(SqlTask.java:210)
	at org.apache.dolphinscheduler.plugin.task.sql.SqlTask.handle(SqlTask.java:161)
	... 9 common frames omitted
Caused by: org.apache.thrift.transport.TTransportException: java.net.SocketTimeoutException: Read timed out
	at org.apache.thrift.transport.TIOStreamTransport.read(TIOStreamTransport.java:129)
	at org.apache.thrift.transport.TTransport.readAll(TTransport.java:86)
	at org.apache.thrift.transport.TSaslTransport.readLength(TSaslTransport.java:376)
	at org.apache.thrift.transport.TSaslTransport.readFrame(TSaslTransport.java:453)
	at org.apache.thrift.transport.TSaslTransport.read(TSaslTransport.java:435)
	at org.apache.thrift.transport.TSaslClientTransport.read(TSaslClientTransport.java:37)
	at org.apache.thrift.transport.TTransport.readAll(TTransport.java:86)
	at org.apache.thrift.protocol.TBinaryProtocol.readAll(TBinaryProtocol.java:429)
	at org.apache.thrift.protocol.TBinaryProtocol.readI32(TBinaryProtocol.java:318)
	at org.apache.thrift.protocol.TBinaryProtocol.readMessageBegin(TBinaryProtocol.java:219)
	at org.apache.thrift.TServiceClient.receiveBase(TServiceClient.java:77)
	at org.apache.hive.service.rpc.thrift.TCLIService$Client.recv_ExecuteStatement(TCLIService.java:237)
	at org.apache.hive.service.rpc.thrift.TCLIService$Client.ExecuteStatement(TCLIService.java:224)
	at sun.reflect.GeneratedMethodAccessor220.invoke(Unknown Source)
	at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.lang.reflect.Method.invoke(Method.java:498)
	at org.apache.hive.jdbc.HiveConnection$SynchronizedHandler.invoke(HiveConnection.java:1524)
	at com.sun.proxy.$Proxy183.ExecuteStatement(Unknown Source)
	at org.apache.hive.jdbc.HiveStatement.runAsyncOnServer(HiveStatement.java:312)
	... 17 common frames omitted
Caused by: java.net.SocketTimeoutException: Read timed out
	at java.net.SocketInputStream.socketRead0(Native Method)
	at java.net.SocketInputStream.socketRead(SocketInputStream.java:116)
	at java.net.SocketInputStream.read(SocketInputStream.java:171)
	at java.net.SocketInputStream.read(SocketInputStream.java:141)
	at java.io.BufferedInputStream.fill(BufferedInputStream.java:246)
	at java.io.BufferedInputStream.read1(BufferedInputStream.java:286)
	at java.io.BufferedInputStream.read(BufferedInputStream.java:345)
	at org.apache.thrift.transport.TIOStreamTransport.read(TIOStreamTransport.java:127)
	... 35 common frames omitted
```

经过一系列的问题排查，发现这个Bug在如下场景下稳定复现：当Kyuubi需要为这个连接启动新的Backend Engine的时候。即当Kyuubi的某个用户连接被释放，或者share level为connection级别时，会触发这个Bug。本质还是连接超时导致的。于是翻阅DolphinScheduler源码，发现DolphinScheduler的Hive SQL数据源SQL Task连接HiveServer是用的Hikari数据库连接池。而这个Bug就是由于Hikari数据库连接池不正确的配置的引起的。

本质就是Kyuubi向Yarn申请启动Backend Engine太耗时了，导致Hikari数据库连接池默认的超时配置不适用于Kyuubi，而其他的数据库基本不会有这类问题。

吐槽一下：DolphinScheduler SQL Task的数据库连接池是不支持配置文件配置的，只能通过修改源码修改配置，然后编译打包重新部署。这一块的代码需要重构了...

```java
// 防止建立连接超时
dataSource.setConnectionTimeout(300_000L);

// 连接池不保留空闲连接，以尽快释放掉所有连接，保证Spark Kyuubi yarn app可以被快速的释放掉，节省资源
// ,同时保证了usercache大量的shuffle中间数据可以被及时清理掉。
dataSource.setMinimumIdle(0);
dataSource.setIdleTimeout(60_000L);

// 保证用户有充足的连接使用
dataSource.setMaximumPoolSize(50);
```



### 上代码

这里只修改了Hive SQL DataSource数据库连接池的配置，同时也支持了通过JDBC URL参数调整Hikari数据库连接池参数，这下调整参数方便多了。也可以修改为对所有种类的SQL DataSource生效...



```java
    org.apache.dolphinscheduler.plugin.datasource.hive.HiveDataSourceClient#initClient
        
    @Override
    protected void initClient(BaseConnectionParam baseConnectionParam, DbType dbType) {
        logger.info("Create Configuration for hive configuration.");
        this.hadoopConf = createHadoopConf();
        logger.info("Create Configuration success.");

        logger.info("Create UserGroupInformation.");
        this.ugi = createUserGroupInformation(baseConnectionParam.getUser());
        logger.info("Create ugi success.");

        this.dataSource = JDBCDataSourceProvider.createOneSessionJdbcDataSource(baseConnectionParam, dbType);

        this.dataSource.setConnectionTimeout(300_000L);

        // no save idle connection to clean usercache(shuffle) file qucikly
        dataSource.setMinimumIdle(0);
        dataSource.setMaximumPoolSize(50);

        String baseConnParamOther = baseConnectionParam.getOther();
        if (JSONUtils.checkJsonValid(baseConnParamOther)) {
            Map<String, String> paramMap = JSONUtils.toMap(baseConnParamOther);
            if (paramMap.containsKey(HIKARI_CONN_TIMEOUT)){
                String connectionTimeout = paramMap.get(HIKARI_CONN_TIMEOUT);
                if (StringUtils.isNumeric(connectionTimeout)){
                    this.dataSource.setConnectionTimeout(Long.parseLong(connectionTimeout));
                }
            }

            // now support config HIKARI_MAXIMUM_POOL_SIZE by ConnectionParam
            if (paramMap.containsKey(HIKARI_MAXIMUM_POOL_SIZE)){
                String maximumPoolSize = paramMap.get(HIKARI_MAXIMUM_POOL_SIZE);
                if (StringUtils.isNotBlank(maximumPoolSize)
                        && StringUtils.isNumeric(maximumPoolSize)){

                    int poolSize = Integer.parseInt(maximumPoolSize);
                    if (poolSize > 0) {
                        dataSource.setMaximumPoolSize(poolSize);
                    }
                }
            }
        }

        // for quick release Kyuubi connection to reduce yarn resource usage
        // reset DriverManager#setLoginTimeout to
        dataSource.setIdleTimeout(60_000L);
        try {
            dataSource.setLoginTimeout(300);
        } catch (SQLException e) {
            logger.info("set LoginTimeout fail for hive datasource");
        }

        this.jdbcTemplate = new JdbcTemplate(dataSource);
        logger.info("Init {} success.", getClass().getName());
    }
```



## 附件

其他DolphinScheduler SQL DataSource和数据库连接池相关的PR，或许去掉数据库连接池是一个更好的选择！

https://github.com/apache/dolphinscheduler/pull/14305

https://github.com/apache/dolphinscheduler/pull/14190