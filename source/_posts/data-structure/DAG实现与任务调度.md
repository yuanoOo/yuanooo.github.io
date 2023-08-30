---
title: DAG实现与任务调度
tags:
  - DAG
categories:
  - - data-structure
abbrlink: 55672
date: 2023-08-30 18:45:16
updated: 2023-08-30 18:45:16
top_img:
cover:
description:
keywords:
---

## 前言

在任务调度场景中，常常通过DAG将多个任务编排成一个复杂的Job，进而满足复杂的任务调度应用场景。特别是在大数据领域，这类调度系统是必须的，比如Azkaba、DolphinScheduler、AirFlow...。而这些系统正是通过DAG进行任务编排的，那么下面让我们试着简单的实现一个DAG调度程序。



## Code

#### 1、抽象出一个任务执行接口

```java
public interface Executor {
    boolean execute();
}
```



#### 2、简单实现一个示例Task，需实现Executor接口。

```java
public class Task implements Executor{
    private Long id;
    private String name;
    private int state;
    public Task(Long id, String name, int state) {
        this.id = id;
        this.name = name;
        this.state = state;
    }
    public boolean execute() {
        System.out.println("Task id: [" + id + "], " + "task name: [" + name +"] is running");
        state = 1;
        return true;
    }
    public boolean hasExecuted() {
        return state == 1;
    }

    public Long getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public int getState() {
        return state;
    }
}

```



#### 3、实现DAG数据结构

这个类使用了邻接表来表示有向无环图。

tasks是顶点集合，也就是任务集合。

map是任务依赖关系集合。key是一个任务，value是它的前置任务集合。

一个任务执行的前提是它在map中没有以它作为key的entry，或者是它的前置任务集合中的任务都是已执行的状态。

```java
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;


/**
 * 这个类使用了邻接表来表示有向无环图。
 *
 * tasks是顶点集合，也就是任务集合。
 *
 * map是任务依赖关系集合。key是一个任务，value是它的前置任务集合。
 *
 * 一个任务执行的前提是它在map中没有以它作为key的entry，或者是它的前置任务集合中的任务都是已执行的状态。
 */
public class Digraph {
    private Set<Task> tasks;
    private Map<Task, Set<Task>> map;
    public Digraph() {
        this.tasks = new HashSet<Task>();
        this.map = new HashMap<Task, Set<Task>>();
    }
    public void addEdge(Task task, Task prev) {
        if (!tasks.contains(task) || !tasks.contains(prev)) {
            throw new IllegalArgumentException();
        }
        Set<Task> prevs = map.get(task);
        if (prevs == null) {
            prevs = new HashSet<Task>();
            map.put(task, prevs);
        }
        if (prevs.contains(prev)) {
            throw new IllegalArgumentException();
        }
        prevs.add(prev);
    }
    public void addTask(Task task) {
        if (tasks.contains(task)) {
            throw new IllegalArgumentException();
        }
        tasks.add(task);
    }
    public void remove(Task task) {
        if (!tasks.contains(task)) {
            return;
        }
        if (map.containsKey(task)) {
            map.remove(task);
        }
        for (Set<Task> set : map.values()) {
            if (set.contains(task)) {
                set.remove(task);
            }
        }
    }
    public Set<Task> getTasks() {
        return tasks;
    }
    public void setTasks(Set<Task> tasks) {
        this.tasks = tasks;
    }
    public Map<Task, Set<Task>> getMap() {
        return map;
    }
    public void setMap(Map<Task, Set<Task>> map) {
        this.map = map;
    }
}
```



#### 4、实现调度器：提交DAG进行调度执行

调度器的实现比较简单，就是遍历任务集合，找出待执行的任务集合，放到一个List中，再串行执行（若考虑性能，可优化为并行执行）。

若List为空，说明所有任务都已执行，则这一次任务调度结束。

```java
package cn.jxau.yuan.dag;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 调度器的实现比较简单，就是遍历任务集合，找出待执行的任务集合，放到一个List中，再串行执行
 * （若考虑性能，可优化为并行执行）。
 *
 * 若List为空，说明所有任务都已执行，则这一次任务调度结束。
 *
 * 一个任务执行的前提是它在map中没有以它作为key的entry，或者是它的前置任务集合中的任务都是已执行的状态。
 */
public class Scheduler {
    public void schedule(Digraph digraph) {
        while (true) {
            List<Task> todo = new ArrayList<Task>();
            System.out.println();
            for (Task task : digraph.getTasks()) {
                if (!task.hasExecuted()) {
                    Set<Task> prevs = digraph.getMap().get(task);
                    if (prevs != null && !prevs.isEmpty()) {
                        // 或者是它的前置任务集合中的任务都是已执行的状态
                        boolean toAdd = true;
                        for (Task task1 : prevs) {
                            if (!task1.hasExecuted()) {
                                toAdd = false;
                                break;
                            }
                        }
                        if (toAdd) {
                            todo.add(task);
                            String log = String.format("%s需要被执行，因为其前置任务[%s]都已经执行成功！！！\n",
                                    task.getName(), prevs.stream().map(Task::getName).collect(Collectors.toList()));
                            System.out.printf(log);
                        }
                    } else {
                        // 一个任务执行的前提是它在map中没有以它作为key的entry
                        todo.add(task);
                        String log = String.format("%s需要被执行，因为他是DAG开始执行的起点\n", task.getName());
                        System.out.printf(log);
                    }
                }
            }
            if (!todo.isEmpty()) {
                System.out.println("这些任务将被并行执行： " + todo.stream().map(Task::getName).collect(Collectors.toList()));
                // 这里可以优化为并行执行
                for (Task task : todo) {
                    if (!task.execute()) {
                        throw new RuntimeException();
                    }
                }
            } else {
                break;
            }
        }
    }

    public static void main(String[] args) {
        Digraph digraph = new Digraph();
        Task task1 = new Task(1L, "task1", 0);
        Task task2 = new Task(2L, "task2", 0);
        Task task3 = new Task(3L, "task3", 0);
        Task task4 = new Task(4L, "task4", 0);
        Task task5 = new Task(5L, "task5", 0);
        Task task6 = new Task(6L, "task6", 0);
        digraph.addTask(task1);
        digraph.addTask(task2);
        digraph.addTask(task3);
        digraph.addTask(task4);
        digraph.addTask(task5);
        digraph.addTask(task6);
        digraph.addEdge(task1, task2);
        digraph.addEdge(task1, task5);
        digraph.addEdge(task6, task2);
        digraph.addEdge(task2, task3);
        digraph.addEdge(task2, task4);
        Scheduler scheduler = new Scheduler();
        scheduler.schedule(digraph);
    }
}
```



## IDEA运行结果

Demo中的任务编排，如下图所示：

![/img/dag1.png]()

```shell
task3需要被执行，因为他是DAG开始执行的起点
task4需要被执行，因为他是DAG开始执行的起点
task5需要被执行，因为他是DAG开始执行的起点
这些任务将被并行执行： [task3, task4, task5]
Task id: [3], task name: [task3] is running
Task id: [4], task name: [task4] is running
Task id: [5], task name: [task5] is running

task2需要被执行，因为其前置任务[[task3, task4]]都已经执行成功！！！
这些任务将被并行执行： [task2]
Task id: [2], task name: [task2] is running

task6需要被执行，因为其前置任务[[task2]]都已经执行成功！！！
task1需要被执行，因为其前置任务[[task2, task5]]都已经执行成功！！！
这些任务将被并行执行： [task6, task1]
Task id: [6], task name: [task6] is running
Task id: [1], task name: [task1] is running


Process finished with exit code 0
```

