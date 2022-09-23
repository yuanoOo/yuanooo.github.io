---
title: 记一次Kylin Server JVM OOM事故排查复盘
tags:
  - 'Kylin'
  - 'JVM'
  - 'MAT'
  - 'Arthas'
categories:
  - [bigdata,Kylin]
date: 2022-09-23 19:35:27
updated: 2022-09-23 19:35:27
cover:
top_img:
description:
keywords:
---

## 问题

在使用Tableau连接Kylin进行多维分析的时候，偶现查询失败，连接超时的问题，由此开始排查事故出现的原因。

- 1、在Kylin的logs里面定位到有JVM OOM的情况，然后查看Kylin Server的JVM GC日志，发现在某个时间段会频繁的发生Full GC，Full GC可以持续十几分钟，同时GC后，老年代空间没有任何变化，这次Full GC无法回收一个对象，开始怀疑发生了内存泄漏。
- 2、生产中部署了三个Kylin Server节点，前面由Nginx进行反向代理，进行负载均衡。查看Nginx日志，发现只有其中一个节点有Timeout的错误日志，于是怀疑Nginx负载均衡配置有问题，大部分流量分到一个节点，导致OOM。但是查看nginx配置，发现没有任何问题，同时Count Nginx请求日志，发现流量也不大，因此和Nginx与大流量高负载可能没有关系。
- 3、到这里，只能利用MAT对JVM的Heap Dump文件*.hprof进行分析，文件有20G大，分析过程中一度导致服务器CPU狂飙至99%，顺利完成后，得到三个zip压缩文件，查看后，检测到内存泄漏，是由两个超大List大对象引起的。
- 4、查看这两个超大List对象的全类名，发现是Kylin hold在内存中的查询结果集，由于查询结果集太大，Kylin Server JVM装不下，直接导致OOM的发生。



> 正常情况下，查询Kylin的都应该是Group By语句，因此结果集应该很小，不会出现大对象，因此排查是哪一个查询语句查出来如此巨大的结果集。
>
> 根据Query id，查找日志，发现是Tableau发出的类似`select tmp.a from tmp;`的这种奇怪且没有意义的查询语句。但是Tableau是闭源的，完全搞不懂为什么会发出这种查询，在Tableau各种实验，也没有办法拖拽出这种查询SQL，但是确实又会时不时发出，导致Kylin Server OOM。



- 5、为了快速的解决问题，保证服务的SLA，因此决定利用Arthas直接线上不停机运行时修改Kylin的源码，为不是Group By的每一条SQL加上limit，保证不会有大的结果集导致OOM。

## 解决方法

> 利用Arthas attach到线上Kylin Server的JVM
>
> 1、利用`jad命令`将QueryUtil类进行反编译，并保存下来，然后用vim修改源码中添加limit的判断逻辑，为不是Group By的每一条SQL加上limit，修改完以后需要将类重新加载到JVM
>
> $ jad --source--only com.example.demo.DemoApplication > /data/DemoApplication.java
>
> 2、`SC命令` 查找QueryUtil类是哪个classLoader加载的
>
> $ sc -d *DemoApplication | grep classLoader
>
> classLoaderHash   20ad9418 #类加载器  编号   
>
> 3、`MC命令` 用指定的classloader将修改后类在内存中编译（MC：内存编译器）
>
> $ mc -c 20ad9418 /data/DemoApplication.java -d /data  
>
> Memory compiler output: /data/com/example/demo/DemoApplication.class
>
> 4、`redefine命令` 将编译后的类加载到JVM
>
> $ redefine /data/com/example/demo/DemoApplication.class   redefine success, size: 1

- 一顿操作猛如虎后，Kylin的源码已经在不停机、运行时完成了更改，最后问题解决，用户完全无感。
