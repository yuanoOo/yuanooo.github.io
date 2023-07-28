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



## Final

上述代码改动后，试运行一段时间后，特别是在多任务并发执行的场景下，会发生各种莫名奇妙的问题，经排查是因为连接池的问题，常常用于OLTP场景的连接池HikariCP，在OLAP ETL场景下表现的非常糟糕。

因此我们决定对DolphinScheduler HiveSQL Datasource进行重构，不在使用连接池，而是直接使用原生的`DriverManager`。经过一段时间的测试后，发现运行的非常稳定，再也没有出现过莫名奇妙的问题。

- 由于Spring自带的`org.springframework.jdbc.datasource.DriverManagerDataSource`，不支持设置超时时间`DriverManager.setLoginTimeout(300)`，因此我们Copy出来，自己实现了HiveDriverManagerDataSource，并在里面设置了超时时间。调大这个参数在连接Kyuubi时非常重要，保证了Kyuubi不会因为在启动Backend Engine时发生Timeout。

```java
/*
 * Copyright 2002-2020 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.dolphinscheduler.plugin.datasource.hive;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

import org.springframework.jdbc.datasource.AbstractDriverBasedDataSource;
import org.springframework.util.Assert;
import org.springframework.util.ClassUtils;

/**
 * Simple implementation of the standard JDBC {@link javax.sql.DataSource} interface,
 * configuring the plain old JDBC {@link java.sql.DriverManager} via bean properties, and
 * returning a new {@link java.sql.Connection} from every {@code getConnection} call.
 *
 * <p><b>NOTE: This class is not an actual connection pool; it does not actually
 * pool Connections.</b> It just serves as simple replacement for a full-blown
 * connection pool, implementing the same standard interface, but creating new
 * Connections on every call.
 *
 * <p>Useful for test or standalone environments outside of a Java EE container, either
 * as a DataSource bean in a corresponding ApplicationContext or in conjunction with
 * a simple JNDI environment. Pool-assuming {@code Connection.close()} calls will
 * simply close the Connection, so any DataSource-aware persistence code should work.
 *
 * <p><b>NOTE: Within special class loading environments such as OSGi, this class
 * is effectively superseded by {@link SimpleDriverDataSource} due to general class
 * loading issues with the JDBC DriverManager that be resolved through direct Driver
 * usage (which is exactly what SimpleDriverDataSource does).</b>
 *
 * <p>In a Java EE container, it is recommended to use a JNDI DataSource provided by
 * the container. Such a DataSource can be exposed as a DataSource bean in a Spring
 * ApplicationContext via {@link org.springframework.jndi.JndiObjectFactoryBean},
 * for seamless switching to and from a local DataSource bean like this class.
 * For tests, you can then either set up a mock JNDI environment through Spring's
 * {@link org.springframework.mock.jndi.SimpleNamingContextBuilder}, or switch the
 * bean definition to a local DataSource (which is simpler and thus recommended).
 *
 * <p>This {@code DriverManagerDataSource} class was originally designed alongside
 * <a href="https://commons.apache.org/proper/commons-dbcp">Apache Commons DBCP</a>
 * and <a href="https://sourceforge.net/projects/c3p0">C3P0</a>, featuring bean-style
 * {@code BasicDataSource}/{@code ComboPooledDataSource} classes with configuration
 * properties for local resource setups. For a modern JDBC connection pool, consider
 * <a href="https://github.com/brettwooldridge/HikariCP">HikariCP</a> instead,
 * exposing a corresponding {@code HikariDataSource} instance to the application.
 *
 * @author Juergen Hoeller
 * @since 14.03.2003
 * @see SimpleDriverDataSource
 */
public class HiveDriverManagerDataSource extends AbstractDriverBasedDataSource {

	/**
	 * Constructor for bean-style configuration.
	 */
	public HiveDriverManagerDataSource() {
	}

	/**
	 * Create a new DriverManagerDataSource with the given JDBC URL,
	 * not specifying a username or password for JDBC access.
	 * @param url the JDBC URL to use for accessing the DriverManager
	 * @see java.sql.DriverManager#getConnection(String)
	 */
	public HiveDriverManagerDataSource(String url) {
		setUrl(url);
	}

	/**
	 * Create a new DriverManagerDataSource with the given standard
	 * DriverManager parameters.
	 * @param url the JDBC URL to use for accessing the DriverManager
	 * @param username the JDBC username to use for accessing the DriverManager
	 * @param password the JDBC password to use for accessing the DriverManager
	 * @see java.sql.DriverManager#getConnection(String, String, String)
	 */
	public HiveDriverManagerDataSource(String url, String username, String password) {
		setUrl(url);
		setUsername(username);
		setPassword(password);
	}

	/**
	 * Create a new DriverManagerDataSource with the given JDBC URL,
	 * not specifying a username or password for JDBC access.
	 * @param url the JDBC URL to use for accessing the DriverManager
	 * @param conProps the JDBC connection properties
	 * @see java.sql.DriverManager#getConnection(String)
	 */
	public HiveDriverManagerDataSource(String url, Properties conProps) {
		setUrl(url);
		setConnectionProperties(conProps);
	}


	/**
	 * Set the JDBC driver class name. This driver will get initialized
	 * on startup, registering itself with the JDK's DriverManager.
	 * <p><b>NOTE: DriverManagerDataSource is primarily intended for accessing
	 * <i>pre-registered</i> JDBC drivers.</b> If you need to register a new driver,
	 * consider using {@link SimpleDriverDataSource} instead. Alternatively, consider
	 * initializing the JDBC driver yourself before instantiating this DataSource.
	 * The "driverClassName" property is mainly preserved for backwards compatibility,
	 * as well as for migrating between Commons DBCP and this DataSource.
	 * @see java.sql.DriverManager#registerDriver(java.sql.Driver)
	 * @see SimpleDriverDataSource
	 */
	public void setDriverClassName(String driverClassName) {
		Assert.hasText(driverClassName, "Property 'driverClassName' must not be empty");
		String driverClassNameToUse = driverClassName.trim();
		try {
			Class.forName(driverClassNameToUse, true, ClassUtils.getDefaultClassLoader());
		}
		catch (ClassNotFoundException ex) {
			throw new IllegalStateException("Could not load JDBC driver class [" + driverClassNameToUse + "]", ex);
		}
		if (logger.isDebugEnabled()) {
			logger.debug("Loaded JDBC driver: " + driverClassNameToUse);
		}
	}


	@Override
	protected Connection getConnectionFromDriver(Properties props) throws SQLException {
		String url = getUrl();
		Assert.state(url != null, "'url' not set");
		if (logger.isDebugEnabled()) {
			logger.debug("Creating new JDBC DriverManager Connection to [" + url + "]");
		}
		return getConnectionFromDriverManager(url, props);
	}

	/**
	 * Getting a Connection using the nasty static from DriverManager is extracted
	 * into a protected method to allow for easy unit testing.
	 * @see java.sql.DriverManager#getConnection(String, java.util.Properties)
	 */
	protected Connection getConnectionFromDriverManager(String url, Properties props) throws SQLException {
		DriverManager.setLoginTimeout(300);
		return DriverManager.getConnection(url, props);
	}

}

```

- 修改`org.apache.dolphinscheduler.plugin.datasource.hive.HiveDataSourceClient`源码，使用`HiveDriverManagerDataSource`作为数据源。

```java
/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.dolphinscheduler.plugin.datasource.hive;

import com.google.common.util.concurrent.ThreadFactoryBuilder;
import org.apache.commons.lang3.StringUtils;
import org.apache.dolphinscheduler.common.constants.Constants;
import org.apache.dolphinscheduler.common.utils.PropertyUtils;
import org.apache.dolphinscheduler.plugin.datasource.api.client.CommonDataSourceClient;
import org.apache.dolphinscheduler.plugin.datasource.api.utils.DataSourceUtils;
import org.apache.dolphinscheduler.plugin.datasource.api.utils.PasswordUtils;
import org.apache.dolphinscheduler.plugin.datasource.hive.utils.CommonUtil;
import org.apache.dolphinscheduler.spi.datasource.BaseConnectionParam;
import org.apache.dolphinscheduler.spi.enums.DbType;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.security.UserGroupInformation;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import sun.security.krb5.Config;

import java.io.IOException;
import java.lang.reflect.Field;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import static org.apache.dolphinscheduler.plugin.task.api.TaskConstants.*;

public class HiveDataSourceClient extends CommonDataSourceClient {

    private static final Logger logger = LoggerFactory.getLogger(HiveDataSourceClient.class);

    private ScheduledExecutorService kerberosRenewalService;

    private Configuration hadoopConf;
    private UserGroupInformation ugi;
    private boolean retryGetConnection = true;

    private static final String HIKARI_CONN_TIMEOUT = "connectionTimeout";

    private static final String HIKARI_MAXIMUM_POOL_SIZE = "hiveOneSessionEnable";
    private HiveDriverManagerDataSource driverManagerDataSource;


    public HiveDataSourceClient(BaseConnectionParam baseConnectionParam, DbType dbType) {
        super(baseConnectionParam, dbType);
    }

    @Override
    protected void preInit() {
        logger.info("PreInit in {}", getClass().getName());
        this.kerberosRenewalService = Executors.newSingleThreadScheduledExecutor(
                new ThreadFactoryBuilder().setNameFormat("Hive-Kerberos-Renewal-Thread-").setDaemon(true).build());
    }

    @Override
    protected void initClient(BaseConnectionParam baseConnectionParam, DbType dbType) {
        this.driverManagerDataSource =
                new HiveDriverManagerDataSource(DataSourceUtils.getJdbcUrl(DbType.HIVE, baseConnectionParam),
                        baseConnectionParam.getUser(), PasswordUtils.decodePassword(baseConnectionParam.getPassword()));
        driverManagerDataSource.setDriverClassName(baseConnectionParam.getDriverClassName());

        this.jdbcTemplate = new JdbcTemplate(driverManagerDataSource);
        logger.info("Init {} success.", getClass().getName());
    }

    @Override
    protected void checkEnv(BaseConnectionParam baseConnectionParam) {
        super.checkEnv(baseConnectionParam);
        checkKerberosEnv();
    }

    private void checkKerberosEnv() {
        String krb5File = PropertyUtils.getString(JAVA_SECURITY_KRB5_CONF_PATH);
        Boolean kerberosStartupState = PropertyUtils.getBoolean(HADOOP_SECURITY_AUTHENTICATION_STARTUP_STATE, false);
        if (kerberosStartupState && StringUtils.isNotBlank(krb5File)) {
            System.setProperty(JAVA_SECURITY_KRB5_CONF, krb5File);
            try {
                Config.refresh();
                Class<?> kerberosName = Class.forName("org.apache.hadoop.security.authentication.util.KerberosName");
                Field field = kerberosName.getDeclaredField("defaultRealm");
                field.setAccessible(true);
                field.set(null, Config.getInstance().getDefaultRealm());
            } catch (Exception e) {
                throw new RuntimeException("Update Kerberos environment failed.", e);
            }
        }
    }

    private UserGroupInformation createUserGroupInformation(String username) {
        String krb5File = PropertyUtils.getString(Constants.JAVA_SECURITY_KRB5_CONF_PATH);
        String keytab = PropertyUtils.getString(Constants.LOGIN_USER_KEY_TAB_PATH);
        String principal = PropertyUtils.getString(Constants.LOGIN_USER_KEY_TAB_USERNAME);

        try {
            UserGroupInformation ugi = CommonUtil.createUGI(getHadoopConf(), principal, keytab, krb5File, username);
            try {
                Field isKeytabField = ugi.getClass().getDeclaredField("isKeytab");
                isKeytabField.setAccessible(true);
                isKeytabField.set(ugi, true);
            } catch (NoSuchFieldException | IllegalAccessException e) {
                logger.warn(e.getMessage());
            }

            kerberosRenewalService.scheduleWithFixedDelay(() -> {
                try {
                    ugi.checkTGTAndReloginFromKeytab();
                } catch (IOException e) {
                    logger.error("Check TGT and Renewal from Keytab error", e);
                }
            }, 5, 5, TimeUnit.MINUTES);
            return ugi;
        } catch (IOException e) {
            throw new RuntimeException("createUserGroupInformation fail. ", e);
        }
    }

    protected Configuration createHadoopConf() {
        Configuration hadoopConf = new Configuration();
        hadoopConf.setBoolean("ipc.client.fallback-to-simple-auth-allowed", true);
        return hadoopConf;
    }

    protected Configuration getHadoopConf() {
        return this.hadoopConf;
    }

    @Override
    public Connection getConnection() {
        try {
            return driverManagerDataSource.getConnection();
        } catch (SQLException e) {
            boolean kerberosStartupState = PropertyUtils.getBoolean(HADOOP_SECURITY_AUTHENTICATION_STARTUP_STATE, false);
            if (retryGetConnection && kerberosStartupState) {
                retryGetConnection = false;
                createUserGroupInformation(baseConnectionParam.getUser());
                Connection connection = getConnection();
                retryGetConnection = true;
                return connection;
            }
            logger.error("get oneSessionDataSource Connection fail SQLException: {}", e.getMessage(), e);
            return null;
        }
    }

    @Override
    public void close() {
        try {
            super.close();
        } finally {
            kerberosRenewalService.shutdown();
            this.ugi = null;
        }
        logger.info("Closed Hive datasource client.");

    }
}

```



## 附件

其他DolphinScheduler SQL DataSource和数据库连接池相关的PR，或许去掉数据库连接池是一个更好的选择！

https://github.com/apache/dolphinscheduler/pull/14305

https://github.com/apache/dolphinscheduler/pull/14190