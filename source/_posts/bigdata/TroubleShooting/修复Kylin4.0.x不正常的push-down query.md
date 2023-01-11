---
title: 修复Kylin4.0.x不正常的push-down query查询耗时
tags:
  - 'Troubleshooting'
  - 'Kylin'
categories:
  - [Troubleshooting, Kylin]
top_img: 
date: 2023-01-11 17:57:25
updated: 2023-01-12 17:57:25
cover:
description:
keywords:
---

## 问题描述

> 发现kylin4.0.x中的push-down query对于简单的明细查询`select * from table limit 10`非常慢，本来应该秒级响应，却往往耗时几分钟，并且查询的数据集越大，耗时越长,这非常不正常。BI工具往往会执行明细查询，进行数据展示，不正常的查询时长，往往造成BI工具超时，返回错误信息，这对用户体验非常不友好
>
> 通过排查发现，在这类非常简单的明细查询的查询计划中，竟然有shuffle过程，简直离谱。
>
> 线上定位问题代码当然离不开Arthas了，然后仔细阅读Kylin源码，找到问题代码所在！！！

## 修改源码

- Kylin执行push-down query的主要逻辑集中在`org.apache.kylin.query.pushdown.SparkSqlClient`中，代码质量简直不忍直视，出现这个问题的主要原因就是代码质量太低。

- 在`org.apache.kylin.query.pushdown.SparkSqlClient#DFToList`中，不必要的Spark DataFrame类型转换transform是这个问题的主要原因。

- 修改后的代码如下`org.apache.kylin.query.pushdown.SparkSqlClient#DFToList`：

  ```scala
  private def dfToList(ss: SparkSession, sql: String, df: DataFrame): Pair[JList[JList[String]], JList[StructField]] = {
  	val jobGroup = Thread.currentThread.getName
  	ss.sparkContext.setJobGroup(jobGroup,
  		"Pushdown Query Id: " + QueryContextFacade.current().getQueryId, interruptOnCancel = true)
  	try {
  		val rowList = df.collect().map(_.toSeq.map(String.valueOf).asJava).toSeq.asJava
  		val fieldList = df.schema.map(field => SparkTypeUtil.convertSparkFieldToJavaField(field)).asJava
  		val (scanRows, scanFiles, metadataTime, scanTime, scanBytes) = QueryMetricUtils.collectScanMetrics(df.queryExecution.executedPlan)
  		QueryContextFacade.current().addAndGetScannedRows(scanRows.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetScanFiles(scanFiles.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetScannedBytes(scanBytes.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetMetadataTime(metadataTime.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetScanTime(scanTime.asScala.map(Long2long(_)).sum)
  		Pair.newPair(rowList, fieldList)
  	} catch {
  		case e: Throwable =>
  			if (e.isInstanceOf[InterruptedException]) {
  				ss.sparkContext.cancelJobGroup(jobGroup)
  				logger.info("Query timeout ", e)
  				Thread.currentThread.interrupt()
  				throw new KylinTimeoutException("Query timeout after: " + KylinConfig.getInstanceFromEnv.getQueryTimeoutSeconds + "s")
  			}
  			else {
               throw e   
              }
  	} finally {
  		HadoopUtil.setCurrentConfiguration(_)
  	}
  }
  ```

- 修改前的代码`org.apache.kylin.query.pushdown.SparkSqlClient#DFToList`：

  ```scala
  private def DFToList(ss: SparkSession, sql: String, df: DataFrame): Pair[JList[JList[String]], JList[StructField]] = {
  	val jobGroup = Thread.currentThread.getName
  	ss.sparkContext.setJobGroup(jobGroup,
  		"Pushdown Query Id: " + QueryContextFacade.current().getQueryId, interruptOnCancel = true)
  	try {
  		val temporarySchema = df.schema.fields.zipWithIndex.map {
  			case (_, index) => s"temporary_$index"
  		}
  		val tempDF = df.toDF(temporarySchema: _*)
  		val columns = tempDF.schema.map(tp => col(s"`${tp.name}`").cast(StringType))
  		val frame = tempDF.select(columns: _*)
  		val rowList = frame.collect().map(_.toSeq.map(_.asInstanceOf[String]).asJava).toSeq.asJava
  		val fieldList = df.schema.map(field => SparkTypeUtil.convertSparkFieldToJavaField(field)).asJava
  		val (scanRows, scanFiles, metadataTime, scanTime, scanBytes) = QueryMetricUtils.collectScanMetrics(frame.queryExecution.executedPlan)
  		QueryContextFacade.current().addAndGetScannedRows(scanRows.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetScanFiles(scanFiles.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetScannedBytes(scanBytes.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetMetadataTime(metadataTime.asScala.map(Long2long(_)).sum)
  		QueryContextFacade.current().addAndGetScanTime(scanTime.asScala.map(Long2long(_)).sum)
  		Pair.newPair(rowList, fieldList)
  	} catch {
  		case e: Throwable =>
  			if (e.isInstanceOf[InterruptedException]) {
  				ss.sparkContext.cancelJobGroup(jobGroup)
  				logger.info("Query timeout ", e)
  				Thread.currentThread.interrupt()
  				throw new KylinTimeoutException("Query timeout after: " + KylinConfig.getInstanceFromEnv.getQueryTimeoutSeconds + "s")
  			}
  			else throw e
  	} finally {
  		HadoopUtil.setCurrentConfiguration(null)
  	}
  }
  ```

## 修复

- 1、`mvn clean package -DskipTests -pl kylin-spark-project/kylin-spark-query`重新编译此模块。
- 2、用重新编译生成的jar包对线上相应的jar包进行替换。
- 3、重启Kylin，问题解决！