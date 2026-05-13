# ThreadPoolExecutor 源码讨论记录

## 一、整体架构认知

### 三层关系

```
ThreadPoolExecutor（线程池/公司管理层）
    │
    ├── HashSet<Worker> workers（员工花名册）
    │
    └── Worker（工头/资源句柄）
            │
            ├── Thread thread（底层 OS 线程的引用）
            ├── Runnable firstTask（初始任务）
            └── AQS state（忙/闲锁状态）
```

**核心结论**：线程池不直接拥有 Thread，而是通过 Worker 间接持有。Worker 是"资源句柄"而非"领域对象"。

---

## 二、Worker 与 Thread 的双向引用

### 为什么有双向引用？

这是 Java `Thread` API 的强制约束，不是线程池的主动设计。

```
Worker 对象                          Thread 对象
├─ thread ────────────────────────►  ├─ target ───────────────────────► Worker
│   （"我能控制这个线程"）            │    （Thread 启动后执行 target.run()）
└─ ...                               └─ ...
```

### 两个指针的语义完全不同

| 指针方向 | 字段 | 语义 |
|---------|------|------|
| Worker → Thread | `Worker.thread` | **控制句柄**。线程池通过它中断线程、判断存活状态 |
| Thread → Worker | `Thread.target` | **回调入口**。线程启动后执行 target.run() |

### 构造时发生了什么？

```java
Worker(Runnable firstTask) {
    this.firstTask = firstTask;
    this.thread = getThreadFactory().newThread(this);  // this 就是 Worker
}
```

`new Thread(this)` 最终调用 `Thread.target = this`，形成了双向绑定。

---

## 三、线程启动后的完整调用链

```
主线程                              新线程（Worker.thread）
    │                                      │
    │① w.thread.start() ─────────────────►│
    │   （请求 JVM 创建 OS 线程）           │
    │                                      │
    │                                      │② Thread.run()
    │                                      │   if (target != null)
    │                                      │      target.run()
    │                                      │
    │                                      │③ Worker.run()
    │                                      │   runWorker(this)
    │                                      │
    │                                      │④ runWorker(Worker w)
    │                                      │   while (task = getTask())
    │                                      │       task.run()
```

**关键认知**：
- `thread.start()` 不是普通方法调用，而是向 JVM 请求创建新 OS 线程
- 新线程启动后**自动**执行 `Thread.run()`，进而回调 `Worker.run()`
- 这不是"Worker 通知线程池"，而是线程池预设了全部剧本

---

## 四、为什么 runWorker 放在 ThreadPoolExecutor 里？

### 职责分离

| 类 | 职责 |
|---|------|
| Worker | **资源句柄**：持有 Thread 引用、维护 AQS 锁状态 |
| ThreadPoolExecutor | **工作协议**：定义任务循环、管理队列、维护线程计数 |

### 如果写在 Worker 里会怎样？

```java
// 灾难设计
class Worker implements Runnable {
    public void run() {
        Runnable task = threadPool.workQueue.take();  // 破坏封装！
        threadPool.ctl.compareAndSet(...);            // 操作线程池私有状态
        threadPool.processWorkerExit(this);           // 反向耦合
    }
}
```

Worker 会膨胀成 God Class，且每个 Worker 实例都重复一份相同逻辑。

---

## 五、为什么 runWorker 用 Thread.currentThread() 而非 w.thread？

| 写法 | 问题 |
|-----|------|
| `w.thread` | "Worker 里存着的线程引用"，理论上可能被篡改（反射等极端情况） |
| `Thread.currentThread()` | "此时此刻正在执行这行代码的真实线程"，JVM 本地方法，绝对可靠 |

这是**防御性编程**：在并发场景下，对"当前执行线程"的引用永远从 JVM 直接获取，不从对象缓存字段获取。

---

## 六、poll vs take 的设计意义

```java
Runnable r = timed ?
    workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) :
    workQueue.take();
```

| 方法 | 行为 | 适用场景 |
|-----|------|---------|
| `take()` | 永久阻塞等待 | **核心线程**（常驻不销毁） |
| `poll(keepAliveTime)` | 超时返回 null | **非核心线程**（空闲超时被回收） |

```java
boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;
```

**这是线程池动态伸缩的核心**：核心线程用 `take()` 永久存活，非核心线程用 `poll()` 超时后退出。

---

## 七、核心线程 / 最大线程的本质

| 参数 | 控制目标 |
|-----|---------|
| `corePoolSize` | `workers` 集合的常驻最小大小 |
| `maximumPoolSize` | `workers` 集合允许的最大大小 |

线程池通过控制 `HashSet<Worker>` 的大小来间接控制线程数量，每个 Worker 绑定一个 Thread。

---

## 八、为什么这个设计看起来"拧巴"？

### OOP 经典假设 vs 并发编程现实

| OOP 假设 | 并发现实 |
|---------|---------|
| 对象之间同步发消息 | 控制流分叉，无法直接调用另一个线程 |
| 清晰的上下层依赖 | 线程启动后自治，只能回调 |
| 封装私有状态 | 并发需要共享队列、计数器 |

### 控制流确实不是 DAG

```
ThreadPoolExecutor ──creates──► Worker ──creates──► Thread
     ▲                                               │
     │                                               │ callback
     │                                               ▼
     └──────────── runWorker(Worker) ◄────────── Worker.run()
```

**原因**：Java `Thread` API 是 1995 年的设计，`ThreadPoolExecutor` 是在这个古老 API 上搭建的并发框架。Worker 实现 `Runnable` 是 Thread 构造函数的强制要求。

---

## 九、内部类访问外部类字段

Worker 作为非静态内部类，编译器会隐式注入 `ThreadPoolExecutor.this` 引用，因此可以直接访问外部类的 `workQueue`、`ctl` 等私有字段。

---

## 十、CAS 循环示例

```java
private void decrementWorkerCount() {
    do {} while (! compareAndDecrementWorkerCount(ctl.get()));
}

private boolean compareAndDecrementWorkerCount(int expect) {
    return ctl.compareAndSet(expect, expect - 1);
}
```

CAS 失败后，外层 `do-while` 循环重新 `ctl.get()` 读取最新值，再次尝试直到成功。

---

## 十一、更好的线程池设计？

### ForkJoinPool（同语言）

| | ThreadPoolExecutor | ForkJoinPool |
|--|-------------------|--------------|
| 队列 | 一个全局 BlockingQueue | 每个线程一个本地队列 + 共享提交队列 |
| 负载均衡 | 无 | 工作窃取（Work-Stealing） |
| 控制流 | Thread→Worker→ThreadPoolExecutor（环状） | Thread→自己的 WorkQueue（更线性） |

ForkJoinPool 更适合计算密集型、可分解任务（Java 8 Stream.parallel() 底层用它）。

### 其他语言

- **Go goroutine**：用户完全不感知线程，调度器完全隐藏
- **Java 21 Virtual Threads**：`Executors.newVirtualThreadPerTaskExecutor()`，底层用 ForkJoinPool，用户无感知

---

## 十二、美团 DynamicTp

底层就是 Java 原生 `ThreadPoolExecutor`，没有重新发明线程池，而是做**工程增强**：

- 动态调整 `corePoolSize`、`maximumPoolSize`
- 自定义 `VariableLinkedBlockingQueue` 支持调整队列容量
- 装饰 Runnable/Callable 添加监控埋点

解决的是"线程池参数改起来麻烦、出问题难发现"的运维痛点，不是设计美学问题。

---

## 十三、核心比喻总结

**不要把 Worker 当"工人"，要当"智能工牌"**：

- 线程池（工厂控制室）写好全部操作手册
- Worker（智能工牌）被插入机器人（Thread）
- 控制室按下电源（thread.start()）
- 机器人启动后读取工牌指令，执行控制室手册（runWorker）
- 工牌只是身份标识和状态记录，不是执行者

**Worker 和 Thread 不是"拥有"关系，而是两个独立对象通过各自指针互相引用，各自履行不同协议。**

---

## 附录：当时的思考轨迹（后续回忆用）

> 以下记录了讨论过程中我自己的猜想和最终被纠正的过程，方便后续回顾时了解当时是怎么想的。

### 猜想 1：Worker 是主动通知者

**当时的想法**：
> "线程池才是并发执行任务的对象，Worker 只是在绑定的线程启动时告诉线程池：'你可以在我这个 Worker 绑定的线程里拉取并执行任务了'。"

**问题**：因果顺序完全反了。

**纠正**：
Worker **不是**主动通知者，它是**被动的资源句柄**。线程池调用 `w.thread.start()` 时，就已经预设了全部剧本：
1. Thread 启动后会回调 `Worker.run()`（因为构造时把 Worker 设为了 `target`）
2. `Worker.run()` 会调用 `runWorker(this)`
3. `runWorker` 进入工作循环，从 `workQueue` 取任务执行

线程池不需要 Worker "告诉"它该干什么，任务队列就在线程池手里。Worker 只是剧本里的一个角色，不是导演。

### 猜想 2：核心线程/最大线程是"绑定的线程中执行任务"的上限

**当时的想法**：
> "核心线程/最大线程其实就是记录的线程池最多可以在多少绑定的线程中执行任务。"

**纠正**：
这个理解**基本正确**，但需要更精确：
- `corePoolSize` = `workers` 集合的**常驻最小**大小（即使空闲也保留）
- `maximumPoolSize` = `workers` 集合的**允许最大**大小

线程池通过控制 `HashSet<Worker>` 的大小来间接控制线程数量，每个 Worker 绑定一个 Thread。

### 关键认知转变

从 "Worker 通知线程池" 转变为 "线程池写好剧本，Worker 和 Thread 只是按剧本表演的演员"。

**形象比喻**：
- 线程池 = 工厂控制室（写好全部操作手册）
- Worker = 智能工牌（身份标识 + 状态记录）
- Thread = 机器人（执行载体）

控制室按下电源（`thread.start()`），机器人启动后读取工牌指令，执行控制室手册（`runWorker`）。工牌只是媒介，不是执行者。