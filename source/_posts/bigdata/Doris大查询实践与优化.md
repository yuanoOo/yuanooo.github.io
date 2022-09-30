---
title: 基于Doris的数据中台的实践与优化
tags:
  - 'Doris'
  - '数据中台'
categories:
  - [bigdata,Doris]
date: 2022-09-30 15:42:16
updated: 2022-09-30 15:42:16
cover:
top_img:
description:
keywords:
---

## 前言

> 随着数据量不断膨胀，基于Oracle的ETL和BI报表可视化业务越来越慢，难以保证数据服务的SLA，为了减少整个大数据平台的复杂度，决定开始调研-'以 Apache Doris 为核心建设一站式数据中台'。
>
> 展望：
>
> 1、所有业务数据通过Flink实时导入到Doris
>
> 2、ETL全部在Doris中完成 
>
> 3、ETL后，基于Doris的ad-hoc能力，可以直接作为ADS层对外提供服务。

## 遇到的问题

- 由于业务非常复杂，ETL过程也非常繁琐，往往涉及数十张表的Join，这非常考验Doris的查询优化器。同时ETL SQL中常常需要开窗排序，非常容易造成内存溢出，导致ETL SQL无法完成。以应对大查询，做了以下参数方面的优化。

  >SET enable_profile = true; 
  >
  >SET query_timeout = 30000;
  >
  >SET enable_spilling = true;
  >
  >SET exec_mem_limit = 10 * 1024 * 1024 * 1024;
  >
  >SET parallel_fragment_exec_instance_num = 8;
  >
  >SET enable_cost_based_join_reorder = true;
