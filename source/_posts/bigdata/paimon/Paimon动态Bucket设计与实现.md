---
title: Paimon动态Bucket设计与实现
tags:
  - 'paimon'
categories:
  - [bigdata,paimon]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2023-06-21 17:57:25
updated: 2023-06-21 17:57:25
cover:
description:
keywords:
---

## 前言

Paimon Dynamic Bucket是Paimon-0.5引入的新特性，现在Paimon可以动态的创建Bucket进行扩容，旨在进一步简化了创建Paimon表的过程，用户无需关心需要创建多少个Bucket。通过`dynamic-bucket.target-row-num`配置指定每个桶存储多少条记录，默认是2_000_000L。

为了实现这个特性，Paimon需要利用文件记录所有Record与其Bucket的映射关系。在paimon中，使用Record的主键的hashcode代表一个Record，而hashcode是Int类型，减少了内存占用。使用主键的hashcode代表一个Record还有一个好处就是，使用int就可以覆盖所有的Record，即使`dynamic-bucket.target-row-num`是Long类型，避免了空间无限膨胀的问题。这是因为即使hash冲突，并不影响正确性。

通过不断检查映射文件中key的行数，当大于`dynamic-bucket.target-row-num`时，创建新的bucket进行扩容。

## 设计与实现

实现集中在paimon-core/src/main/java/org/apache/paimon/index包中。



#### 入口类

`org.apache.paimon.index.HashBucketAssigner#HashBucketAssigner`是实现的入口类，被
`org.apache.paimon.flink.sink.HashBucketAssignerOperator#initializeState`方法调用，找到了入口类，接下来就是一步步阅读源码，理清逻辑了。

```java
    @Override
    public void initializeState(StateInitializationContext context) throws Exception {
        super.initializeState(context);

        // Each job can only have one user name and this name must be consistent across restarts.
        // We cannot use job id as commit user name here because user may change job id by creating
        // a savepoint, stop the job and then resume from savepoint.
        String commitUser =
                StateUtils.getSingleValueFromState(
                        context, "commit_user_state", String.class, initialCommitUser);
        
        // 初始化bucket分配器，因此HashBucketAssigner是入口类
        this.assigner =
                new HashBucketAssigner(
                        table.snapshotManager(),
                        commitUser,
                        table.store().newIndexFileHandler(),
                        getRuntimeContext().getNumberOfParallelSubtasks(),
                        getRuntimeContext().getIndexOfThisSubtask(),
                        table.coreOptions().dynamicBucketTargetRowNum());
        this.extractor = extractorFunction.apply(table.schema());
    }
    
        @Override
    public void processElement(StreamRecord<T> streamRecord) throws Exception {
        T value = streamRecord.getValue();
        
        // 通过调用assign方法，获取每一个record对应的bucket
        int bucket =
                assigner.assign(
                        extractor.partition(value), extractor.trimmedPrimaryKey(value).hashCode());
        output.collect(new StreamRecord<>(new Tuple2<>(value, bucket)));
    }
```

```java
    public HashBucketAssigner(
            SnapshotManager snapshotManager,
            String commitUser,
            IndexFileHandler indexFileHandler,
            int numAssigners,
            int assignId,
            long targetBucketRowNumber) {
        this.snapshotManager = snapshotManager;
        this.commitUser = commitUser;
        this.indexFileHandler = indexFileHandler;
        this.numAssigners = numAssigners;
        this.assignId = assignId; // getRuntimeContext().getIndexOfThisSubtask()
        this.targetBucketRowNumber = targetBucketRowNumber;
        this.partitionIndex = new HashMap<>();
    }

    /** Assign a bucket for key hash of a record. */
    public int assign(BinaryRow partition, int hash) {
        // hash: Record主键的hashcode，唯一确认一个Record
        int recordAssignId = computeAssignId(hash);
        // 可能是因为，Flink DAG前面已经通过主键的hashcode % channels了，所以一定相等
        checkArgument(
                recordAssignId == assignId,
                "This is a bug, record assign id %s should equal to assign id %s.",
                recordAssignId,
                assignId);
        
        // PartitionIndex: Bucket Index Per Partition.
        // 为每一个partition计算对应的Bucket Index
        PartitionIndex index = partitionIndex.computeIfAbsent(partition, this::loadIndex);
        return index.assign(hash, (bucket) -> computeAssignId(bucket) == assignId);
    }

    private int computeAssignId(int hash) {
        // numAssigners: getRuntimeContext().getNumberOfParallelSubtasks()
        return Math.abs(hash % numAssigners);
    }
```

```java
    org.apache.paimon.index.PartitionIndex#assign
	public int assign(int hash, IntPredicate bucketFilterFunc) {
        accessed = true;

        // 1. is it a key that has appeared before
        // 注意：当发生Hash冲突的时候，两个不同的parimary key，会有相同的hashcode
        // 但是我们无法知道是否发生了冲突，本来需要bucketInformation.put(bucket, number + 1)，加1
        // 因此会导致设置的dynamic-bucket.target-row-num bucket中的条数不准确。
        // 只要hash冲突不严重，无伤大雅
        if (hash2Bucket.containsKey(hash)) {
            return hash2Bucket.get(hash);
        }

        // 2. find bucket from existing buckets
        for (Integer bucket : bucketInformation.keySet()) {
            if (bucketFilterFunc.test(bucket)) {
                // it is my bucket
                Long number = bucketInformation.get(bucket);
                if (number < targetBucketRowNumber) {
                    bucketInformation.put(bucket, number + 1);
                    hash2Bucket.put(hash, bucket.shortValue());
                    return bucket;
                }
            }
        }

        // 3. create a new bucket
        for (int i = 0; i < Short.MAX_VALUE; i++) {
            if (bucketFilterFunc.test(i) && !bucketInformation.containsKey(i)) {
                hash2Bucket.put(hash, (short) i);
                bucketInformation.put(i, 1L);
                return i;
            }
        }

        @SuppressWarnings("OptionalGetWithoutIsPresent")
        int maxBucket =
                bucketInformation.keySet().stream().mapToInt(Integer::intValue).max().getAsInt();
        throw new RuntimeException(
                String.format(
                        "To more bucket %s, you should increase target bucket row number %s.",
                        maxBucket, targetBucketRowNumber));
    }
```

