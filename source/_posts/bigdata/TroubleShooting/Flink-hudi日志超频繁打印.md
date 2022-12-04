---
title: Flink-hudi日志超频繁打印
tags:
  - 'Troubleshooting'
categories:
  - [Troubleshooting]
top_img: 
date: 2022-12-04 17:57:25
updated: 2022-12-0 17:57:25
cover:
description:
keywords:
---



## 问题描述

将从Kafka读取CDC日志写入Hudi的Flink SQL作业部署到集群后，发现Flink Job Manager频繁打印以下日志，差不多1000次每秒，非常恐怖。Job Manager日志文件快速膨胀，占用大量磁盘空间，已经影响到集群稳定性。

```shell
2022-12-04 09:24:40,897 INFO  org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient [] - SASL encryption trust check: localHostTrusted = false, remoteHostTrusted = false
2022-12-04 09:24:40,899 INFO  org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient [] - SASL encryption trust check: localHostTrusted = false, remoteHostTrusted = false
2022-12-04 09:24:40,933 INFO  org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient [] - SASL encryption trust check: localHostTrusted = false, remoteHostTrusted = false
2022-12-04 09:24:40,935 INFO  org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient [] - SASL encryption trust check: localHostTrusted = false, remoteHostTrusted = false
```



## 问题排查

- 显然这不是正常现象，然后查看hudi源码，发现是日志是`org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient#checkTrustAndSend`这个方法打印的。

  ```java
    private IOStreamPair checkTrustAndSend(
        InetAddress addr, OutputStream underlyingOut, InputStream underlyingIn,
        DataEncryptionKeyFactory encryptionKeyFactory,
        Token<BlockTokenIdentifier> accessToken, DatanodeID datanodeId,
        SecretKey secretKey)
        throws IOException {
      boolean localTrusted = trustedChannelResolver.isTrusted();
      boolean remoteTrusted = trustedChannelResolver.isTrusted(addr);
      LOG.debug("SASL encryption trust check: localHostTrusted = {}, "
          + "remoteHostTrusted = {}", localTrusted, remoteTrusted);
      if (!localTrusted || !remoteTrusted) {
        // The encryption key factory only returns a key if encryption is enabled.
        DataEncryptionKey encryptionKey =
            encryptionKeyFactory.newDataEncryptionKey();
        return send(addr, underlyingOut, underlyingIn, encryptionKey, accessToken,
            datanodeId, secretKey);
      } else {
        LOG.debug(
            "SASL client skipping handshake on trusted connection for addr = {}, "
                + "datanodeId = {}", addr, datanodeId);
        return null;
      }
    }
  ```

- 源码显示打印的是debug日志，但是实际打印出来的日志显示是info级别，很是奇怪。看来是一个Bug。



### 线上利用Arthas分析问题

- 1、利用trace命令看看`org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient#checkTrustAndSend`这个方法里面的执行情况：

  ```shell
  [arthas@1302]$ trace org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient checkTrustAndSend -n 2
  Press Q or Ctrl+C to abort.
  Affect(class count: 1 , method count: 2) cost in 203 ms, listenerId: 6
  `---ts=2022-12-04 10:25:01;thread_name=pool-20-thread-1;id=bf;is_daemon=false;priority=5;TCCL=sun.misc.Launcher$AppClassLoader@5cad8086
      `---[1.121797ms] org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient:checkTrustAndSend()
          `---[0.93434ms] org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient:checkTrustAndSend() #227
              `---[0.839963ms] org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient:checkTrustAndSend()
                  +---[0.092959ms] org.apache.hadoop.hdfs.protocol.datatransfer.TrustedChannelResolver:isTrusted() #237
                  +---[0.012338ms] org.apache.hadoop.hdfs.protocol.datatransfer.TrustedChannelResolver:isTrusted() #238
                  +---[0.023832ms] org.slf4j.Logger:info() #239
                  +---[0.021391ms] org.apache.hadoop.hdfs.protocol.datatransfer.sasl.DataEncryptionKeyFactory:newDataEncryptionKey() #244
                  `---[0.045789ms] org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient:send() #245
  ```

  发现调用的竟然是`org.slf4j.Logger:info()`方法和源码中的LOG.debug()方法根本不符，很是奇怪。

- 2、利用stack命令看看`org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient#checkTrustAndSend`方法的调用链路。

  ```shell
  [arthas@1302]$ stack org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient checkTrustAndSend -n 2
  ts=2022-12-04 09:48:33;thread_name=pool-20-thread-1;id=bf;is_daemon=false;priority=5;TCCL=sun.misc.Launcher$AppClassLoader@5cad8086
      @org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient.checkTrustAndSend()
          at org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient.peerSend(SaslDataTransferClient.java:170)
          at org.apache.hadoop.hdfs.DFSUtilClient.peerFromSocketAndKey(DFSUtilClient.java:730)
          at org.apache.hadoop.hdfs.DFSClient.newConnectedPeer(DFSClient.java:2942)
          at org.apache.hadoop.hdfs.client.impl.BlockReaderFactory.nextTcpPeer(BlockReaderFactory.java:822)
          at org.apache.hadoop.hdfs.client.impl.BlockReaderFactory.getRemoteBlockReaderFromTcp(BlockReaderFactory.java:747)
          at org.apache.hadoop.hdfs.client.impl.BlockReaderFactory.build(BlockReaderFactory.java:380)
          at org.apache.hadoop.hdfs.DFSInputStream.getBlockReader(DFSInputStream.java:644)
          at org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(DFSInputStream.java:575)
          at org.apache.hadoop.hdfs.DFSInputStream.readWithStrategy(DFSInputStream.java:757)
          at org.apache.hadoop.hdfs.DFSInputStream.read(DFSInputStream.java:829)
          at org.apache.hadoop.hdfs.DFSInputStream.read(DFSInputStream.java:681)
          at java.io.FilterInputStream.read(FilterInputStream.java:83)
          at java.io.DataInputStream.readInt(DataInputStream.java:387)
          at org.apache.hudi.common.table.log.HoodieLogFileReader.readVersion(HoodieLogFileReader.java:361)
          at org.apache.hudi.common.table.log.HoodieLogFileReader.readBlock(HoodieLogFileReader.java:171)
          at org.apache.hudi.common.table.log.HoodieLogFileReader.next(HoodieLogFileReader.java:388)
          at org.apache.hudi.common.table.log.HoodieLogFileReader.next(HoodieLogFileReader.java:68)
          at org.apache.hudi.common.table.timeline.HoodieArchivedTimeline.loadInstants(HoodieArchivedTimeline.java:255)
          at org.apache.hudi.common.table.timeline.HoodieArchivedTimeline.<init>(HoodieArchivedTimeline.java:109)
          at org.apache.hudi.common.table.HoodieTableMetaClient.getArchivedTimeline(HoodieTableMetaClient.java:392)
          at org.apache.hudi.sync.common.HoodieSyncClient.getDroppedPartitionsSince(HoodieSyncClient.java:91)
          at org.apache.hudi.hive.HiveSyncTool.syncHoodieTable(HiveSyncTool.java:231)
          at org.apache.hudi.hive.HiveSyncTool.doSync(HiveSyncTool.java:158)
          at org.apache.hudi.hive.HiveSyncTool.syncHoodieTable(HiveSyncTool.java:142)
          at org.apache.hudi.sink.StreamWriteOperatorCoordinator.doSyncHive(StreamWriteOperatorCoordinator.java:335)
          at org.apache.hudi.sink.utils.NonThrownExecutor.lambda$wrapAction$0(NonThrownExecutor.java:130)
          at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
          at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
          at java.lang.Thread.run(Thread.java:748)
  ```

  发现是Flink Hive Sync模块在频繁的调用这个方法。

- 3、利用arthas的logger info命令查看`org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient#checkTrustAndSend`这个类的logger信息。

  ```shell
  logger -n org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient
  
  name                        org.apache.hadoop
  class                       org.apache.logging.log4j.core.config.LoggerConfig
  classLoader                 sun.misc.Launcher$AppClassLoader@5cad8086
  classLoaderHash             5cad8086
  level                       INFO
  config                      org.apache.logging.log4j.core.config.properties.PropertiesConfiguration@1448eed2
  additivity                  true
  codeSource                  file:/data/hadoop/nm-local-dir/usercache/hadoop/appcache/application_1666403512407_0148/filecache/13/flink-doris-connector-1.14_2.11-1.1.0.jar
  ```

- 4、暂时通过arthas将`org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient#checkTrustAndSend`这个类的logger级别由INFO提升到WARN。这样INFO级别的日志就不会再打印。问题暂时得到解决。

  ```shell
  logger --name org.apache.hadoop --level WARN
  ```

  

