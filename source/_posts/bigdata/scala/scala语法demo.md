---
title: Scala特殊语法指南
tags:
  - scala
categories:
  - - bigdata
    - scala
abbrlink: 5351
date: 2023-03-08 19:54:07
updated: 2022-03-08 19:54:07
top_img:
cover:
description:
keywords:
---

### 柯里化

在Scala中，定义了两组空括号`()()`的方法称为“柯里化方法”。这意味着该方法采用多个参数列表，每个参数列表都由一组空括号表示。

例如，考虑以下方法定义：

```
def add(a: Int)(b: Int): Int = a + b
```

在这种情况下，`add`是一个柯里化方法，它以单独的参数列表接受两个整数参数`a`和`b`。要调用此方法，您首先需要提供`a`的值，然后是`b`。这看起来像：

```
val result = add(1)(2) // result是3
```

柯里化方法在函数式编程中非常有用，可以允许部分函数应用，函数组合和其他高阶编程技术。

```scala
  /**
   * Execute a block of code that evaluates to Unit, stop SparkContext if there is any uncaught
   * exception
   *
   * NOTE: This method is to be called by the driver-side components to avoid stopping the
   * user-started JVM process completely; in contrast, tryOrExit is to be called in the
   * spark-started JVM process .
   */
  def tryOrStopSparkContext(sc: SparkContext)(block: => Unit): Unit = {
    try {
      block
    } catch {
      case e: ControlThrowable => throw e
      case t: Throwable =>
        val currentThreadName = Thread.currentThread().getName
        if (sc != null) {
          logError(s"uncaught error in thread $currentThreadName, stopping SparkContext", t)
          sc.stopInNewThread()
        }
        if (!NonFatal(t)) {
          logError(s"throw uncaught fatal error in thread $currentThreadName", t)
          throw t
        }
    }
  }
  
  // 调用柯里化方法
  private val dispatchThread = new Thread(s"spark-listener-group-$name") {
    setDaemon(true)
    override def run(): Unit = Utils.tryOrStopSparkContext(sc) {
      dispatch()
    }
  }
```



### 伴生对象（companion object）

在Scala中，每个类都可以有一个伴生对象（companion object）。伴生对象是一个单例对象，在同一源文件中定义，并且与类具有相同的名称。类和伴生对象之间可以互相访问对方的私有成员，从而允许我们将相关的方法和功能封装在一起。

通常情况下，伴生对象主要被用来定义那些不依赖于实例化对象而可以直接使用的静态成员和方法，可以将它们定义在伴生对象中。例如：

```scala
class MyClass(val name: String, val age: Int)

object MyClass {
  def createDefault(): MyClass = new MyClass("John Doe", 30)
}
```

在这个例子中，我们定义了一个名为`MyClass`的类，并在同一源文件中定义了一个名为`MyClass`的伴生对象。在伴生对象中，我们定义了一个名为`createDefault`的静态方法，它返回一个新创建的`MyClass`对象，该对象具有默认的名称“John Doe”和年龄30。

伴生对象的另一个用途是作为工厂方法的容器，使得我们可以将某些相关的工厂方法放在同一个伴生对象中以提高可读性和可维护性。伴生对象还可以帮助我们实现静态和动态方法的多态，从而在类使用时提供更大的灵活性。

值得一提的是，在Scala中没有静态成员或静态方法，伴生对象的成员和方法只是静态的外观，Scala实际上是将它们作为伴生类的私有成员实现的。
