---
title: thrift-从入门到放弃
tags:
  - 'thrift'
categories:
  - [RPC,thrift]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2022-08-31 21:07:13
updated: 2022-08-31 21:07:13
cover:
description:
keywords:
---

## Thrift-Java-Maven使用指北

- 1、下载安装Thrift，配置Thrift环境变量

- 2、Maven中引入libthrift依赖

  ```xml
  <dependency>
     <groupId>org.apache.thrift</groupId>
     <artifactId>libthrift</artifactId>
     <version>0.14.1</version>
  </dependency>
  ```

- 3、引入Maven插件maven-thrift-plugin

  ```xml
  <build>
        <plugins>
           <plugin>
              <groupId>org.apache.thrift.tools</groupId>
              <artifactId>maven-thrift-plugin</artifactId>
              <version>0.1.11</version>
              <configuration>
                 <!--指定Thrift编译文件的目录和位置，设定环境变量便可不用指定-->
                 <thriftExecutable>./thrift/thrift.exe</thriftExecutable>
                 <!--指定待编译的  IDL文件目录，默认为src/main/thrift-->
                 <thriftSourceRoot>src/main/resources/thrift</thriftSourceRoot>
                 <!--在0.1.10版本后的plugin需要添加的参数-->
                 <generator>java</generator> 
                 <!--指定编译输出目录-->
                 <outputDirectory>src/main/java</outputDirectory>
              </configuration>
           </plugin>
        </plugins>
     </build>
  ```

  >  然后通过执行plugin 的compile指令即可将文件直接编译转化为java类，注意有些版本需要添加<generator>java</generator>，否则可能会报错：[ERROR] thrift failed error: [FAILURE:generation:1] Error: unknown option java:hashcode。
  >
  > 
  >
  > 同时，如果我们像上面一样指定了编译输出目录为项目目录，会覆盖原有目录下的文件，所以可以保持默认配置，输出至target目录下，然后复制到我们想要的package下。

## FQA

- 执行mvn clean install编译失败

  > [ERROR] thrift failed error: [FAILURE:generation:1] Error: unknown option java:hashcode
  >
  > [ERROR] Failed to execute goal org.apache.thrift.tools:maven-thrift-plugin:0.1.11:compile (thrift-sources) on project HelloService: thrift did n
  > ot exit cleanly. Review output for more information. -> [Help 1]

  Maven插件maven-thrift-plugin配置中添加`<generator>java</generator>`

  ```xml
  		<plugin>
              <groupId>org.apache.thrift.tools</groupId>
              <artifactId>maven-thrift-plugin</artifactId>
              <version>0.1.11</version>
              <configuration>
                 <!--指定Thrift编译文件的目录和位置，设定环境变量便可不用指定-->
                 <thriftExecutable>./thrift/thrift.exe</thriftExecutable>
                 <!--指定待编译的  IDL文件目录，默认为src/main/thrift-->
                 <thriftSourceRoot>src/main/resources/thrift</thriftSourceRoot>
                 <!--在0.1.10版本后的plugin需要添加的参数-->
                 <generator>java</generator> 
                 <!--指定编译输出目录-->
                 <outputDirectory>src/main/java</outputDirectory>
              </configuration>
           </plugin>
  ```

  

- Thrift生成的java文件，无法被import引用，原因是Thrift生成的java文件路径不对

  >1、<outputDirectory></outputDirectory>配置为<outputDirectory>src/main/java</outputDirectory>
  >
  >2、将生成的目录在IDEA中指定为源文件目录：
  >
  >![img](https://cdn.nlark.com/yuque/0/2022/png/2500465/1661953198633-ec36aeea-e0ef-4398-beaa-cbefdef85f3d.png)
