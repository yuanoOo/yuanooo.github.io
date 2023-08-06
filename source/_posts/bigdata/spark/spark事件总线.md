---
title: Spark事件总线源码分析
tags:
  - spark
categories:
  - - bigdata
    - spark
abbrlink: 32133
date: 2023-03-08 19:54:07
updated: 2022-03-08 19:54:07
top_img:
cover:
description:
keywords:
---

## 前言

Spark中很多组件之间是靠事件消息实现通信的，之前分析了一下Spark中RPC机制，RPC和事件消息机制目的都是实现组件之间的通信，前者解决远程通信问题，而后者则是在本地较为高效的方式。Spark中大量采用事件监听这种方式，实现driver端的组件之间的通信。

![img](https://raw.githubusercontent.com/yuanoOo/learngit/master/jpg/spark-listenbus.png)

## ListenerBus

```scala
/**
 * An event bus which posts events to its listeners.
 */
private[spark] trait ListenerBus[L <: AnyRef, E] extends Logging {

  private[this] val listenersPlusTimers = new CopyOnWriteArrayList[(L, Option[Timer])]

  // Marked `private[spark]` for access in tests.
  private[spark] def listeners = listenersPlusTimers.asScala.map(_._1).asJava
  ...
}
```

ListenerBus trait是Spark内所有事件总线实现的基类，有两个泛型参数L和E。L代表监听器的类型，并且它可以是任意类型的。E则代表事件的类型。**接受事件并且将事件提交到对应事件的监听器**。

主要属性如下

- `listeners`, `listenersPlusTimers`：**维护了所有的监听器和对应的定时器**，数据结构为线程安全的`CopyOnWriteArrayList`适用于读多写少的业务场景，满足数据的最终一致性

主要方法如下

- `addListener()`, `removeListener()`：**从`listenersPlusTimers`中增加或者删除监听器和计时器**
- `postToAll()`：**遍历`listenersPlusTimers`并调用未实现的`doPostEvent()`方法发送事件**

每个实现类实现了`doPostEvent`方法，利用模式匹配将特定的事件投递到对应的监视器类型。



### SparkListenerBus

SparkListenerBus特征是Spark Core内部事件总线的基类，其代码如下。

```scala
// 监听器
private[spark] trait SparkListenerInterface {

  /**
   * Called when a stage completes successfully or fails, with information on the completed stage.
   */
  def onStageCompleted(stageCompleted: SparkListenerStageCompleted): Unit
  
  ...
}

// 事件
@DeveloperApi
@JsonTypeInfo(use = JsonTypeInfo.Id.CLASS, include = JsonTypeInfo.As.PROPERTY, property = "Event")
trait SparkListenerEvent {
  /* Whether output this event to the event log */
  protected[spark] def logEvent: Boolean = true
}
...
@DeveloperApi
case class SparkListenerStageCompleted(stageInfo: StageInfo) extends SparkListenerEvent
...

// 事件总线
private[spark] trait SparkListenerBus
extends ListenerBus[SparkListenerInterface, SparkListenerEvent] {

  protected override def doPostEvent(
    listener: SparkListenerInterface,
    event: SparkListenerEvent): Unit = {
    event match {
      case stageSubmitted: SparkListenerStageSubmitted =>
      listener.onStageSubmitted(stageSubmitted)
      ...
    }
  }
}
```

SparkListenerBus继承了ListenerBus，实现了doPostEvent()方法，对事件进行匹配，并调用监听器的处理方法。如果无法匹配到事件，则调用onOtherEvent()方法。

SparkListenerBus支持的监听器都是SparkListenerInterface的子类，事件则是SparkListenerEvent的子类。下面来了解一下。

### SparkListenerInterface与SparkListenerEvent特征

在SparkListenerInterface特征中，分别定义了处理每一个事件的处理方法，统一命名为“on+事件名称”，代码很简单，就不再贴出来了。

SparkListenerEvent是一个没有抽象方法的特征，类似于Java中的标记接口（marker interface），它唯一的用途就是标记具体的事件类。事件类统一命名为“SparkListener+事件名称”，并且都是Scala样例类。



## AsyncEventQueue

在SparkListenerBus的实现类AsyncEventQueue中，提供了异步事件队列机制，它也是SparkContext中的事件总线LiveListenerBus的基础。

实现原理是基于消息队列的异步通信，因此有以下优点：1、将Event发送者和Event listerner解耦。2、异步：Event发送者发送Event给消息队列后直接返回，无需等待listener处理后才返回，减少了Event发送者的阻塞，提高了性能。

```scala
/**
 * An asynchronous queue for events. All events posted to this queue will be delivered to the child
 * listeners in a separate thread.
 *
 * Delivery will only begin when the `start()` method is called. The `stop()` method should be
 * called when no more events need to be delivered.
 */
private class AsyncEventQueue(
    val name: String,
    conf: SparkConf,
    metrics: LiveListenerBusMetrics,
    bus: LiveListenerBus)
  extends SparkListenerBus
  with Logging {
  import AsyncEventQueue._

  private val eventQueue = new LinkedBlockingQueue[SparkListenerEvent](
    conf.get(LISTENER_BUS_EVENT_QUEUE_CAPACITY))

  private val eventCount = new AtomicLong()

  private val droppedEventsCounter = new AtomicLong(0L)

  @volatile private var lastReportTimestamp = 0L

  private val logDroppedEvent = new AtomicBoolean(false)

  private var sc: SparkContext = null

  private val started = new AtomicBoolean(false)
  private val stopped = new AtomicBoolean(false)

  private val droppedEvents = metrics.metricRegistry.counter(s"queue.$name.numDroppedEvents")
  private val processingTime = metrics.metricRegistry.timer(s"queue.$name.listenerProcessingTime")

  private val dispatchThread = new Thread(s"spark-listener-group-$name") {
    setDaemon(true)
    override def run(): Unit = Utils.tryOrStopSparkContext(sc) {
      dispatch()
    }
  }

  // ...
}
```

该类的构造参数有四个，分别是队列名、Spark配置项、LiveListenerBus的监控度量，以及LiveListenerBus本身。下面来看一下它的主要属性。

#### **eventQueue、eventCount属性**

eventQueue是一个存储SparkListenerEvent事件的阻塞队列LinkedBlockingQueue。它的大小是通过配置参数spark.scheduler.listenerbus.eventqueue.capacity来设置的，默认值10000。如果不设置阻塞队列的大小，那么默认值会是Integer.MAX_VALUE，有OOM的风险。

eventCount则是当前待处理事件的计数。因为事件从队列中弹出不代表已经处理完成，所以不能直接用队列的实际大小来表示。它是AtomicLong类型的，以保证修改的原子性。

#### **droppedEventsCounter、lastReportTimestamp、logDroppedEvent属性**

droppedEventsCounter是被丢弃事件的计数。当阻塞队列已满后，新产生的事件无法入队，就会被丢弃。日志中定期输出该计数器的值，用lastReportTimestamp记录下每次输出的时间戳，并且输出后都会将计数器重新置为0。

logDroppedEvent用于指示是否发生过了事件丢弃的情况。它与droppedEventsCounter一样也都是原子类型的。

#### **started、stopped属性**

这两个属性分别用来标记队列的启动与停止状态。

#### **dispatchThread属性**

dispatchThread是将队列中的事件分发到各监听器的守护线程，实际上调用了dispatch()方法。而Utils.tryOrStopSparkContext()方法的作用在于执行代码块时如果抛出异常，就另外起一个线程关闭SparkContext。

下面就来看看dispatch()方法的源码。

```scala
  private def dispatch(): Unit = LiveListenerBus.withinListenerThread.withValue(true) {
    var next: SparkListenerEvent = eventQueue.take()
    while (next != POISON_PILL) {
      val ctx = processingTime.time()
      try {
        super.postToAll(next)
      } finally {
        ctx.stop()
      }
      eventCount.decrementAndGet()
      next = eventQueue.take()
    }
    eventCount.decrementAndGet()
  }
```

可见，该方法循环地从事件队列中取出事件，并调用父类ListenerBus特征的postToAll()方法（文章#5已经讲过）将其投递给所有已注册的监听器，并减少计数器的值。“毒药丸”POISON_PILL是伴生对象中定义的一个特殊的空事件，在队列停止（即调用stop()方法）时会被放入，dispatcherThread取得它之后就会“中毒”退出循环。

有了处理事件的方法，还得有将事件放入队列的方法才完整。下面是入队的方法post()。

```scala
  def post(event: SparkListenerEvent): Unit = {
    if (stopped.get()) {
      return
    }

    eventCount.incrementAndGet()
    if (eventQueue.offer(event)) {
      return
    }

    eventCount.decrementAndGet()
    droppedEvents.inc()
    droppedEventsCounter.incrementAndGet()
    if (logDroppedEvent.compareAndSet(false, true)) {
      // Only log the following message once to avoid duplicated annoying logs.
      logError(s"Dropping event from queue $name. " +
        "This likely means one of the listeners is too slow and cannot keep up with " +
        "the rate at which tasks are being started by the scheduler.")
    }
    logTrace(s"Dropping event $event")

    val droppedEventsCount = droppedEventsCounter.get
    val droppedCountIncreased = droppedEventsCount - lastDroppedEventsCounter
    val lastReportTime = lastReportTimestamp.get
    val curTime = System.currentTimeMillis()
    // Don't log too frequently
    if (droppedCountIncreased > 0 && curTime - lastReportTime >= LOGGING_INTERVAL) {
      // There may be multiple threads trying to logging dropped events,
      // Use 'compareAndSet' to make sure only one thread can win.
      if (lastReportTimestamp.compareAndSet(lastReportTime, curTime)) {
        val previous = new java.util.Date(lastReportTime)
        lastDroppedEventsCounter = droppedEventsCount
        logWarning(s"Dropped $droppedCountIncreased events from $name since " +
          s"${if (lastReportTime == 0) "the application started" else s"$previous"}.")
      }
    }
  }
```

该方法首先检查队列是否已经停止。如果是运行状态，就试图将事件event入队。若offer()方法返回false，表示队列已满，将丢弃事件的计数器自增，并标记有事件被丢弃。最后，若当前的时间戳与上一次输出droppedEventsCounter值的间隔大于1分钟，就在日志里输出它的值。

理解了AsyncEventQueue的细节之后，我们就可以进一步来看LiveListenerBus的实现了。

## 异步事件总线LiveListenerBus

AsyncEventQueue已经继承了SparkListenerBus特征，LiveListenerBus内部用到了AsyncEventQueue作为核心。来看它的声明以及属性的定义。

```scala
private[spark] class LiveListenerBus(conf: SparkConf) {
  import LiveListenerBus._

  private var sparkContext: SparkContext = _

  private[spark] val metrics = new LiveListenerBusMetrics(conf)

  private val started = new AtomicBoolean(false)
  private val stopped = new AtomicBoolean(false)

  private val droppedEventsCounter = new AtomicLong(0L)

  @volatile private var lastReportTimestamp = 0L

  private val queues = new CopyOnWriteArrayList[AsyncEventQueue]()

  @volatile private[scheduler] var queuedEvents = new mutable.ListBuffer[SparkListenerEvent]()

  // ...
}
```

这里的属性与AsyncEventQueue大同小异，多出来的主要是queues与queuedEvents两个。

#### **queues属性**

queues维护一个AsyncEventQueue的列表，也就是说LiveListenerBus中会有多个事件队列。它采用CopyOnWriteArrayList来保证线程安全性。

#### **queuedEvents属性**

queuedEvents维护一个SparkListenerEvent的列表，它的用途是在LiveListenerBus启动成功之前，缓存可能已经收到的事件。在启动之后，这些缓存的事件会首先投递出去。

**LiveListenerBus作为一个事件总线，也必须提供监听器注册、事件投递等功能，这些都是在AsyncEventQueue基础之上实现的，下面来看一看。**

#### **addToQueue()方法**

```scala
  private[spark] def addToQueue(
      listener: SparkListenerInterface,
      queue: String): Unit = synchronized {
    if (stopped.get()) {
      throw new IllegalStateException("LiveListenerBus is stopped.")
    }

    queues.asScala.find(_.name == queue) match {
      case Some(queue) =>
        queue.addListener(listener)

      case None =>
        val newQueue = new AsyncEventQueue(queue, conf, metrics, this)
        newQueue.addListener(listener)
        if (started.get()) {
          newQueue.start(sparkContext)
        }
        queues.add(newQueue)
    }
  }
```

该方法将监听器listener注册到名为queue的队列中。它会在queues列表中寻找符合条件的队列，如果该队列已经存在，就调用父类ListenerBus的addListener()方法直接注册监听器。反之，就先创建一个AsyncEventQueue，注册监听器到新的队列中。

#### post()、postToQueues()方法

```scala
  def post(event: SparkListenerEvent): Unit = {
    if (stopped.get()) {
      return
    }
    metrics.numEventsPosted.inc()

    if (queuedEvents == null) {
      postToQueues(event)
      return
    }

    synchronized {
      if (!started.get()) {
        queuedEvents += event
        return
      }
    }

    postToQueues(event)
  }

  private def postToQueues(event: SparkListenerEvent): Unit = {
    val it = queues.iterator()
    while (it.hasNext()) {
      it.next().post(event)
    }
  }
```

post()方法会检查queuedEvents中有无缓存的事件，以及事件总线是否还没有启动。投递时会调用postToQueues()方法，将事件发送给所有队列，由AsyncEventQueue来完成投递到监听器的工作。

![img](https://raw.githubusercontent.com/yuanoOo/learngit/master/jpg/gfvstvfzym.jpeg)

