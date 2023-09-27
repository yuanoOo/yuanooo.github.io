---
title: 利用RuntimeReplaceable实现Spark Native function
tags:
  - spark
categories:
  - - bigdata
    - spark
abbrlink: 7631
date: 2023-09-27 15:55:27
updated: 2023-09-27 15:55:27
cover:
top_img:
description:
keywords:
---

## 关于Spark Native Function

在Spark中实现自定义函数，有多种方式：

- 1、实现Hive UDF，Spark是兼容Hive UDF的，简单易用，支持纯SQL环境，因此这可能是使用最为广泛的。
- 2、实现Spark-SQL UDF，需要嵌入到代码中，因此也主要用在代码中，目前还不支持纯SQL环境。
- 3、通过拓展SparkSessionExtensions，基本等价于Spark Built-in内置函数，可以充分利用Spark catalyst优化器和Codegen，从而带来可观的性能提升，这里称之为Spark Native Function。但是这种方式也是实现最为困难的，需要对SQL解析器、优化器等有一定的理解。同时网上关于这种方式的资料几乎没有，Spark官方文档中也是根本没有提及这种方式，足以说明这种方式较高的门槛。

## 应用场景：RuntimeReplaceable

Spark已经内置足够多的UDF，已经可以满足绝大部分的应用场景。

剩下的不能满足的应用场景中，其中很大一部分可以通过组合这些内置的函数，来满足。因此也就带来一个问题，就是有时候应用场景非常复杂，需要组合几十种函数，而Spark-SQL也不支持存储过程，最后导致SQL非常长，难以理解阅读，从而难以维护。

而通过实现`RuntimeReplaceable`类型Spark Native Function，可以完美的解决我们的问题。`RuntimeReplaceable`是通过用我们自定义的函数Express替换掉抽象语法树中的函数Express，主要用于兼容不同数据库系统函数别名，也正好满足我们的应用场景。



## 上代码

在这个例子中，我们实现了一个`str_pivot` Spark Native Function，该函数解决的应用场景如下：

> 有这样一个用逗号分隔的字符串`c1,c2,c3`包含三个元素c1、c2、c3，这三个元素通过排列组合，顺序不同也是一种组合，共有16中组合，例如：c1，c1c2，c2c1，c1c2c3等等。
>
> 给出另一个字符串`c2c1`，判断这个字符串是不是其中一个排列组合。这就是`str_pivot`函数要实现的。
>
> 我们可以通过下面这个算法实现：
>
> `size(array_union(array('1', '2', '3'), array('2','1'))) = size(array('1', '2', '3'))`

### driver

```scala
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.execution.CodegenMode

/**
 * org.apache.spark.sql.catalyst.analysis.FunctionRegistry
 *
 * org.apache.spark.sql.catalyst.expressions.Length
 *
 * -- CodeGen
 * org.apache.spark.sql.catalyst.expressions.UnaryMathExpression
 */
object StringPiovtFunctionDriver {
  val sql = "select str_pivot('1,2,3,4', '1,2')"
  val sql_udf = "select str_pivot_udf('1,2,3,4', '1,2')"

  def main(args: Array[String]): Unit = {
    val spark = SparkSession
      .builder()
      .master("local[1]")
      .appName("SparkNativeFunctionInject")
      .withExtensions(new FunctionSparkExtension)
      .getOrCreate()
	
    // UDF方式实现，对比执行计划等
    spark.udf.register("str_pivot_udf",
      (left: String, right: String) => {
        left.split(",").union(right.split(",")).toSet.size == left.split(",").length
      }
    )

    spark.sql(sql).show()
    spark.sql(sql).explain(true)
    spark.sql(sql).explain(CodegenMode.name)

    spark.sql(sql_udf).show()
    spark.sql(sql_udf).explain(true)
    spark.sql(sql_udf).explain(CodegenMode.name)

  }
}

```

### 拓展SparkSessionExtensions，injectFunction

```scala
import org.apache.spark.sql.catalyst.FunctionIdentifier
import org.apache.spark.sql.catalyst.analysis.FunctionRegistry.FunctionBuilder
import org.apache.spark.sql.catalyst.expressions.{Expression, ExpressionInfo}
import org.apache.spark.sql.{MLBStrPivot, SparkSessionExtensions, StringLength, StringPivot}

class FunctionSparkExtension extends (SparkSessionExtensions => Unit){
  override def apply(extensions: SparkSessionExtensions): Unit = {
    extensions.injectFunction(
      (new FunctionIdentifier("str_pivot"),
        new ExpressionInfo(classOf[MLBStrPivot].getName,
          "str_pivot"),
        (children: Seq[Expression]) => new MLBStrPivot(children.head, children(1))))
  }
}
```

### Function Implement

```scala
// left is fully string
case class MLBStrPivot(left: Expression, right: Expression, child: Expression) extends RuntimeReplaceable {

  //size(array_union(array('1', '2', '3'), array('2','1'))) = size(array('1', '2', '3'))
  def this(left: Expression, right: Expression) = {
    this(left, right,  
    EqualTo
      (
        Size(ArrayUnion(StringSplit(left, Literal(","), Literal(-1)), StringSplit(right, Literal(","), Literal(-1))), false),
        Size(StringSplit(left, Literal(","), Literal(-1)))
      )
    )
  }

  override def flatArguments: Iterator[Any] = Iterator(left, right)
  override def exprsReplaced: Seq[Expression] = Seq(left, right)
  // 用上面实现的Express进行替换	
  override protected def withNewChildInternal(newChild: Expression): MLBStrPivot = copy(child = newChild)
}
```