---
title: Paimon-Flink-Sink源码分析
tags:
  - paimon
categories:
  - - bigdata
    - paimon
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
abbrlink: 27532
date: 2023-05-24 17:57:25
updated: 2022-05-24 17:57:25
cover:
description:
keywords:
---

## 前言

Paimon在Flink下面的层次结构，大概为：Catalog -> Database -> Table -> Record。因此看Paimon如何在Flink中实现Read、Write等操作，先从Catalog开始。



## Catalog

Paimon在Flink中实现Catalog的源码位于`org.apache.paimon.flink.FlinkCatalog`，该类实现了`org.apache.flink.table.catalog.Catalog`接口。该接口中定义了一系列方法，包括listTables、listViews等方法，而paimon一一实现了这些接口。

在Flink中自定义Catalog，还需要实现`org.apache.flink.table.factories.CatalogFactory`工厂接口，paimon中对应的为`org.apache.paimon.flink.FlinkCatalogFactory`类。该工厂类当然是用来创建Catalog了。

最后还需要将Catalog工厂实现类，添加到将此实现类添加到 `META_INF/services/org.apache.flink.table.factories.Factory` 中。用于SPI。



## Table

在paimon实现的FlinkCatalog类中，`org.apache.paimon.flink.FlinkCatalog#getFactory`方法，用于提供写入和读取Paimon的具体实现。

```java
    @Override
    public Optional<Factory> getFactory() {
        return Optional.of(new FlinkTableFactory(catalog.lockFactory().orElse(null)));
    }
```

在Paimon中，这个方法返回的是`org.apache.paimon.flink.FlinkTableFactory`。该工厂类实现了`org.apache.flink.table.factories.DynamicTableSourceFactory`，`org.apache.flink.table.factories.DynamicTableSinkFactory`接口。分别用来实现读取和写入Paimon表的逻辑。而写入Paimon表的实现类为`org.apache.paimon.flink.sink.FlinkTableSink`。该类主要实现了`org.apache.flink.table.connector.sink.DynamicTableSink`接口。

```java
/**
 * Sink of a dynamic table to an external storage system.
 *
 * <p>Dynamic tables are the core concept of Flink's Table & SQL API for processing both bounded and
 * unbounded data in a unified fashion. By definition, a dynamic table can change over time.
 *
 * <p>When writing a dynamic table, the content can always be considered as a changelog (finite or
 * infinite) for which all changes are written out continuously until the changelog is exhausted.
 * The given {@link ChangelogMode} indicates the set of changes that the sink accepts during
 * runtime.
 *
 * <p>For regular batch scenarios, the sink can solely accept insert-only rows and write out bounded
 * streams.
 *
 * <p>For regular streaming scenarios, the sink can solely accept insert-only rows and can write out
 * unbounded streams.
 *
 * <p>For change data capture (CDC) scenarios, the sink can write out bounded or unbounded streams
 * with insert, update, and delete rows. See also {@link RowKind}.
 *
 * <p>Instances of {@link DynamicTableSink} can be seen as factories that eventually produce
 * concrete runtime implementation for writing the actual data.
 *
 * <p>Depending on the optionally declared abilities, the planner might apply changes to an instance
 * and thus mutate the produced runtime implementation.
 *
 * <p>A {@link DynamicTableSink} can implement the following abilities:
 *
 * <ul>
 *   <li>{@link SupportsPartitioning}
 *   <li>{@link SupportsOverwrite}
 *   <li>{@link SupportsWritingMetadata}
 * </ul>
 *
 * <p>In the last step, the planner will call {@link #getSinkRuntimeProvider(Context)} for obtaining
 * a provider of runtime implementation.
 */
@PublicEvolving
public interface DynamicTableSink {

    /**
     * Returns the set of changes that the sink accepts during runtime.
     *
     * <p>The planner can make suggestions but the sink has the final decision what it requires. If
     * the planner does not support this mode, it will throw an error. For example, the sink can
     * return that it only supports {@link ChangelogMode#insertOnly()}.
     *
     * @param requestedMode expected set of changes by the current plan
     */
    ChangelogMode getChangelogMode(ChangelogMode requestedMode);

    /**
     * Returns a provider of runtime implementation for writing the data.
     *
     * <p>There might exist different interfaces for runtime implementation which is why {@link
     * SinkRuntimeProvider} serves as the base interface. Concrete {@link SinkRuntimeProvider}
     * interfaces might be located in other Flink modules.
     *
     * <p>Independent of the provider interface, the table runtime expects that a sink
     * implementation accepts internal data structures (see {@link RowData} for more information).
     *
     * <p>The given {@link Context} offers utilities by the planner for creating runtime
     * implementation with minimal dependencies to internal data structures.
     *
     * <p>{@link SinkProvider} is the recommended core interface. {@code SinkFunctionProvider} in
     * {@code flink-table-api-java-bridge} and {@link OutputFormatProvider} are available for
     * backwards compatibility.
     *
     * @see SinkProvider
     */
    SinkRuntimeProvider getSinkRuntimeProvider(Context context);

    /**
     * Creates a copy of this instance during planning. The copy should be a deep copy of all
     * mutable members.
     */
    DynamicTableSink copy();

    /** Returns a string that summarizes this sink for printing to a console or log. */
    String asSummaryString();

}

```

> 将动态表汇入外部存储系统。
> 动态表是 Flink 的 Table & SQL API 的核心概念，用于以统一的方式处理有界和无界数据。根据定义，动态表可以随时间变化。
> 在编写动态表时，内容始终可以被视为一个 changelog（有限或无限），所有更改都被连续写出，直到 changelog 耗尽。给定的ChangelogMode指示接收器在运行时接受的更改集。
> 对于常规批处理方案，接收器只能接受仅插入行并写出有界流。
> 对于常规流场景，接收器只能接受仅插入行，并且可以写出无界流。
> 对于变更数据捕获 (CDC) 场景，接收器可以写出带有插入、更新和删除行的有界或无界流。另请参阅RowKind 。
> DynamicTableSink的实例可以被视为最终生成用于写入实际数据的具体运行时实现的工厂。
> 根据可选声明的能力，规划器可能会将更改应用于实例，从而改变生成的运行时实现。
> DynamicTableSink可以实现以下功能：
> SupportsPartitioning
> SupportsOverwrite
> SupportsWritingMetadata
> 在最后一步中，规划器将调用getSinkRuntimeProvider(DynamicTableSink.Context)来获取运行时实现的提供者。



## Write

### 构建Paimon Sink Flink DAG源码流程

入口类以及对应的入口方法为：org.apache.paimon.flink.sink.FlinkSinkBuilder#build，
进入这个方法中看看，发现会先对DataStream进行，按照分桶进行分区转换

```java
org.apache.paimon.flink.sink.FlinkSinkBuilder#build

public DataStreamSink<?> build() {
    BucketingStreamPartitioner<RowData> partitioner =
            new BucketingStreamPartitioner<>(
                    new RowDataChannelComputer(table.schema(), logSinkFunction != null));
    PartitionTransformation<RowData> partitioned =
            new PartitionTransformation<>(input.getTransformation(), partitioner);
    if (parallelism != null) {
        partitioned.setParallelism(parallelism);
    }

    StreamExecutionEnvironment env = input.getExecutionEnvironment();
    // 构建Flink paimon sink DAG类
    FileStoreSink sink =
            new FileStoreSink(table, lockFactory, overwritePartition, logSinkFunction);
    return commitUser != null && sinkProvider != null
            ? sink.sinkFrom(new DataStream<>(env, partitioned), commitUser, sinkProvider)
            : sink.sinkFrom(new DataStream<>(env, partitioned));
}
```

- 1、createWriteOperator：实际进行写入Record的算子, org.apache.paimon.flink.sink.RowDataStoreWriteOperator
  org.apache.paimon.flink.AbstractFlinkTableFactory#buildPaimonTable

- 2、CommitterOperator：CK时进行snapshot commit的地方，保证数据可见性。
```java
org.apache.paimon.flink.sink.FlinkSink#sinkFrom(org.apache.flink.streaming.api.datastream.DataStream<T>, java.lang.String, org.apache.paimon.flink.sink.StoreSinkWrite.Provider);

public DataStreamSink<?> sinkFrom(
  DataStream<T> input, String commitUser, StoreSinkWrite.Provider sinkProvider) {
  StreamExecutionEnvironment env = input.getExecutionEnvironment();
  ReadableConfig conf = StreamExecutionEnvironmentUtils.getConfiguration(env);
  CheckpointConfig checkpointConfig = env.getCheckpointConfig();

  boolean isStreaming =
    conf.get(ExecutionOptions.RUNTIME_MODE) == RuntimeExecutionMode.STREAMING;
  boolean streamingCheckpointEnabled =
    isStreaming && checkpointConfig.isCheckpointingEnabled();
  if (streamingCheckpointEnabled) {
    assertCheckpointConfiguration(env);
  }

  CommittableTypeInfo typeInfo = new CommittableTypeInfo();
  SingleOutputStreamOperator<Committable> written =
    input.transform(
      WRITER_NAME + " -> " + table.name(),
      typeInfo,
      // 1、createWriteOperator：实际进行写入Record的算子
      createWriteOperator(sinkProvider, isStreaming, commitUser))
      .setParallelism(input.getParallelism());

  SingleOutputStreamOperator<?> committed =
    written.transform(
      GLOBAL_COMMITTER_NAME + " -> " + table.name(),
      typeInfo,
      // 2、CommitterOperator：CK时进行snapshot commit的地方，保证数据可见性。
      new CommitterOperator(
        streamingCheckpointEnabled,
        commitUser,
        createCommitterFactory(streamingCheckpointEnabled),
        createCommittableStateManager()))
      .setParallelism(1)
      .setMaxParallelism(1);
  return committed.addSink(new DiscardingSink<>()).name("end").setParallelism(1);
}
```


-  1、createWriteOperator
```scala
private StoreSinkWrite.Provider createWriteProvider(CheckpointConfig checkpointConfig) {
    boolean waitCompaction;

    if (table.coreOptions().writeOnly()) {
        // 如果配置为writeOnly()，则不进行在线压缩
        waitCompaction = false;
    } else {
        Options options = table.coreOptions().toConfiguration();
        ChangelogProducer changelogProducer = table.coreOptions().changelogProducer();
        // 当ChangelogProducer为LOOKUP时，则等待压缩
        waitCompaction =
                changelogProducer == ChangelogProducer.LOOKUP
                        && options.get(CHANGELOG_PRODUCER_LOOKUP_WAIT);
        
        // 决定FULL_COMPACTION的压缩间隔
        int deltaCommits = -1;
        if (options.contains(FULL_COMPACTION_DELTA_COMMITS)) {
            deltaCommits = options.get(FULL_COMPACTION_DELTA_COMMITS);
        } else if (options.contains(CHANGELOG_PRODUCER_FULL_COMPACTION_TRIGGER_INTERVAL)) {
            long fullCompactionThresholdMs =
                    options.get(CHANGELOG_PRODUCER_FULL_COMPACTION_TRIGGER_INTERVAL).toMillis();
            deltaCommits =
                    (int)
                            (fullCompactionThresholdMs
                                    / checkpointConfig.getCheckpointInterval());
        }
        
        // Generate changelog files with each full compaction
        // 当进行FULL_COMPACTION的时候，需要生成changelog files
        if (changelogProducer == ChangelogProducer.FULL_COMPACTION || deltaCommits >= 0) {
            int finalDeltaCommits = Math.max(deltaCommits, 1);
            return (table, commitUser, state, ioManager) ->
                    new GlobalFullCompactionSinkWrite(
                            table,
                            commitUser,
                            state,
                            ioManager,
                            isOverwrite,
                            waitCompaction,
                            finalDeltaCommits);
        }
    }

    return (table, commitUser, state, ioManager) ->
            new StoreSinkWriteImpl(
                    table, commitUser, state, ioManager, isOverwrite, waitCompaction);
}
```

### Paimon Flink CK流程
我们知道Flink paimon写入主要涉及两个算子：

1、org.apache.paimon.flink.sink.RowDataStoreWriteOperator
这个算子实现了`org.apache.flink.streaming.api.operators.StreamOperator#prepareSnapshotPreBarrier`方法，这个方法会在算子接受到driver的checkpoint请求后被调用。在prepareSnapshotPreBarrier方法中会调用`org.apache.paimon.flink.sink.PrepareCommitOperator#emitCommittables`方法，emitCommittables方法的作用是向后面的commit算子发送committable信息。

然而这个emitCommittables方法，又会调用prepareCommit方法，最终会调用`org.apache.paimon.mergetree.MergeTreeWriter#prepareCommit`
**因此Flink每次进行checkpoint的时候，Paimon都会强制进行Memory Flush，完成数据的落盘，保证数据写入到文件系统，完成写入事务，保证一致性。**

```java
org.apache.paimon.flink.sink.PrepareCommitOperator#prepareSnapshotPreBarrier

@Override
public void prepareSnapshotPreBarrier(long checkpointId) throws Exception {
  if (!endOfInput) {
    emitCommittables(false, checkpointId);
  }
  // no records are expected to emit after endOfInput
}

@Override
public void endInput() throws Exception {
  endOfInput = true;
  emitCommittables(true, Long.MAX_VALUE);
}

private void emitCommittables(boolean doCompaction, long checkpointId) throws IOException {
  prepareCommit(doCompaction, checkpointId)
    .forEach(committable -> output.collect(new StreamRecord<>(committable)));
}

protected abstract List<Committable> prepareCommit(boolean doCompaction, long checkpointId) throws IOException;
```
2、CommitterOperator
这个算子实现了`org.apache.flink.api.common.state.CheckpointListener#notifyCheckpointComplete`方法，该方法会在FLink CK完成后被调用，paimon-flink-sink在这个方法中会进行snapshot快照的提交，主要就是将本次快照生成的snapshot、manifest文件写入到文件系统。

