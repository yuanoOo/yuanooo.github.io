---
title: 优化Flink ogg-json format
tags:
  - 'Flink'
categories:
  - [bigdata,Flink]
top_img: '/img/bg/banner.gif'
date: 2023-08-08 20:23:04
updated: 2023-08-08 20:23:04
cover:
description:
keywords:
---

## 前言

最近发现从kafka同步到Paimon中的数据不正确。具体表现为，明明数据库中某条记录已经Update了，但是Paimon中的同一条记录没有同步更新。经过一系列的排查发现，是由于公司ogg json格式不统一，导致Flink ogg-json format解析失败，同时因为配置了`ogg-json.ignore-parse-errors = true`，最终导致整条ogg更新Record被丢弃，没有发送到下流的Paimon。



## 代码记录

`org.apache.flink.formats.json.ogg.OggJsonDeserializationSchema#deserialize(byte[], org.apache.flink.util.Collector<org.apache.flink.table.data.RowData>)`

```java
    @Override
    public void deserialize(byte[] message, Collector<RowData> out) throws IOException {
        if (message == null || message.length == 0) {
            // skip tombstone messages
            return;
        }
        try {
            final JsonNode root = jsonDeserializer.deserializeToJsonNode(message);
            GenericRowData row = (GenericRowData) jsonDeserializer.convertToRowData(root);

            GenericRowData before = (GenericRowData) row.getField(0);
            GenericRowData after = (GenericRowData) row.getField(1);
            String op = row.getField(2).toString();
            if (OP_CREATE.equals(op)) {
                after.setRowKind(RowKind.INSERT);
                emitRow(row, after, out);
            } else if (OP_UPDATE.equals(op)) {
                if (before == null) {
                    throw new IllegalStateException(
                            String.format(REPLICA_IDENTITY_EXCEPTION, "UPDATE"));
                }

                // for case: "before":{}
                if (!root.get("before").isEmpty()) {
                    before.setRowKind(RowKind.UPDATE_BEFORE);
                    emitRow(row, before, out);
                }

                after.setRowKind(RowKind.UPDATE_AFTER);
                emitRow(row, after, out);
            } else if (OP_DELETE.equals(op)) {
                if (before == null) {
                    throw new IllegalStateException(
                            String.format(REPLICA_IDENTITY_EXCEPTION, "DELETE"));
                }
                before.setRowKind(RowKind.DELETE);
                emitRow(row, before, out);
            } else {
                if (!ignoreParseErrors) {
                    throw new IOException(
                            format(
                                    "Unknown \"op_type\" value \"%s\". The Ogg JSON message is '%s'",
                                    op, new String(message)));
                }
            }
        } catch (Throwable t) {
            // a big try catch to protect the processing.
            if (!ignoreParseErrors) {
                throw new IOException(
                        format("Corrupt Ogg JSON message '%s'.", new String(message)), t);
            }
        }
    }
```



## PR

https://github.com/apache/flink/pull/23102
