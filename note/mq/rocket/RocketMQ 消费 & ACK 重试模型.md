---
tags:
  - mq/rocketmq
  - spring
  - consumer
created: 2026-07-16
updated: 2026-07-17
scope: RocketMQ 4.x DefaultMQPushConsumer / rocketmq-spring PushConsumer 内部长轮询模型
---

# RocketMQ 消费线程模型、ProcessQueue、ACK 与重试

> 范围说明：本文主要总结 **RocketMQ 4.x / `DefaultMQPushConsumer` / `rocketmq-spring-boot-starter` 常见模型**。这里说的“poll / pull”指 `PushConsumer` 内部通过客户端长轮询从 Broker 拉取消息；不是 Broker 真正直接 push 到业务代码。RocketMQ 5.x `SimpleConsumer` 的显式 `receive + ack` 模型不在本文重点。

## 0. 一句话总览

RocketMQ PushConsumer 的实际链路如下图：

![RocketMQ topic, MessageQueue, consumer instance and thread relation](rocketmq-topic-mq-consumer-thread.svg)

---

## 1. Topic -> MessageQueue -> 消费者实例 -> 消费线程

### 1.1 关系结论

在 `DefaultMQPushConsumer` 模型下：

| 层级 | 关系 / 职责 | 关键点 |
|---|---|---|
| Topic | 包含多个 `MessageQueue` | Topic 是业务维度，真正参与消费分配的是 `MessageQueue` |
| Consumer Group | 包含多个消费者实例 | 同一个 Group 内共同分摊 Topic 的队列 |
| MessageQueue | 在同一个 Consumer Group 内被分配给某个消费者实例 | 是负载均衡的基本单位 |
| 消费者实例 | 内部维护 `ProcessQueue`、`PullRequest`、消费线程池 | 一个 Spring Boot 进程中通常对应一个或多个 RocketMQ Consumer 实例 |
| 消费线程 | 负责执行 Listener / `onMessage` | 不与 `MessageQueue` 一一绑定，而是消费线程池共享执行 |

也就是：

```text
MessageQueue 是负载均衡单位
消费线程是单个消费者实例内部的执行资源
```

不要理解成：

```text
一个 MessageQueue = 一个消费线程
```

更准确是：

```text
多个 MessageQueue -> 一个 Consumer 实例
一个 Consumer 实例 -> 一个共享 consumeExecutor 线程池
```

### 1.2 Concurrently：并发消费

并发消费模式下的模型如下：

![RocketMQ concurrently consume model](rocketmq-concurrent-consume-model.svg)

特点：

- 单个 `MessageQueue` 内部的消息也可能被多个线程并发处理；
- 不保证业务 key 的严格顺序；
- 吞吐主要受 `MessageQueue` 数量、消费者实例数、消费线程池大小、业务耗时共同影响；
- retry topic 的消息和正常 topic 的消息共享同一个消费线程池。

### 1.3 Orderly：顺序消费

顺序消费模式下：

```text
同一个 MessageQueue 内的消息按顺序推进
失败消息会暂停当前队列一段时间
后续消息不能越过失败消息继续消费
```

所以顺序消费的有效并发更接近：

```text
当前消费者实例分配到的 MessageQueue 数量
```

而不是简单等于：

```text
consumeThreadNumber
```

### 1.4 文档与源码依据

官方文档要点：

- Consumer Group 内的消费者会对 Topic 下的队列做负载均衡；4.x `DefaultPushConsumer` 主要是 queue-based load balancing。  
  来源：[RocketMQ Consumer Load Balancing](https://rocketmq.apache.org/docs/featureBehavior/08consumerloadbalance/)
- PushConsumer 内部封装消息获取、处理、状态提交；业务通过 Listener 返回消费结果。  
  来源：[RocketMQ Consumer Types](https://rocketmq.apache.org/docs/featureBehavior/06consumertype/)
- 顺序消息要求相同消息组 / 队列内按顺序处理，失败会影响后续消息推进。  
  来源：[RocketMQ FIFO Message](https://rocketmq.apache.org/docs/featureBehavior/03fifomessage/)

源码重点：`RebalanceImpl` 遍历订阅 Topic，并按 Topic 做队列分配。

```java
for (Map.Entry<String, SubscriptionData> entry : subTable.entrySet()) {
    final String topic = entry.getKey();
    rebalanceByTopic(topic, isOrder);
}
```

来源：[RebalanceImpl.java L232-L247](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/RebalanceImpl.java#L232-L247)

新增队列时会创建 `ProcessQueue` 和 `PullRequest`：

```java
ProcessQueue pq = createProcessQueue();
PullRequest pullRequest = new PullRequest();
pullRequest.setMessageQueue(mq);
pullRequest.setProcessQueue(pq);
```

来源：[RebalanceImpl.java L474-L490](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/RebalanceImpl.java#L474-L490)

---

## 2. SDK 中维护 ProcessQueue 的机制

![RocketMQ ProcessQueue mechanism](rocketmq-processqueue-mechanism.svg)

### 2.1 ProcessQueue 是什么

`ProcessQueue` 是 **Consumer 客户端本地内存里，对某个 MessageQueue 的消费快照 / 本地暂存区 / 进度计算对象**。

它不是：

```text
Broker 上的 MessageQueue
Java 线程池队列
Spring 队列
```

它更像：

```text
当前 Consumer 实例已拉取、待消费 / 消费中 / 待结果处理消息的本地视图
```

### 2.2 维度：不是每个 Topic 一个，而是每个被分配到的 MessageQueue 一个

关系是：

```text
MessageQueue(topic, brokerName, queueId) -> ProcessQueue
```

例如当前进程分到：

```text
order-topic Q0
order-topic Q1
%RETRY%order-group Q0
```

那么本地可能有：

```text
processQueueTable
├── order-topic/Q0        -> ProcessQueue
├── order-topic/Q1        -> ProcessQueue
└── %RETRY%order-group/Q0 -> ProcessQueue
```

源码重点：`RebalanceImpl` 维护的是 `MessageQueue -> ProcessQueue` 映射。

```java
ConcurrentMap<MessageQueue, ProcessQueue> processQueueTable
```

来源：[RebalanceImpl.java L51-L51](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/RebalanceImpl.java#L51-L51)

### 2.3 ProcessQueue 内部核心结构

`ProcessQueue` 主要按 `queueOffset` 保存消息：

```java
msgTreeMap.put(msg.getQueueOffset(), msg);
```

来源：[ProcessQueue.java L129-L140](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ProcessQueue.java#L129-L140)

所以它是一个按队列 offset 排序的本地缓存。它还维护这些关键字段：

| 字段 | 含义 | 主要用途 |
|---|---|---|
| `msgCount` | 当前 `ProcessQueue` 中缓存的消息数量 | 本地积压统计、拉取流控 |
| `msgSize` | 当前缓存消息体的总大小 | 本地内存占用统计、拉取流控 |
| `queueOffsetMax` | 当前本地缓存中过的最大队列 offset | `removeMessage` 后计算可提交 offset；队列进度判断 |
| `lastPullTimestamp` | 最近一次从 Broker 拉取该队列消息的时间 | 判断拉取是否停滞 / 过期 |
| `lastConsumeTimestamp` | 最近一次消费该队列消息的时间 | 判断消费是否停滞 / 过期 |
| `locked` | 顺序消费时当前队列是否被本消费者锁定 | Orderly 模式下保证队列内顺序消费 |
| `dropped` | 当前 `ProcessQueue` 是否已被 Rebalance 丢弃 | 避免已失效队列继续提交消费结果 / offset |

这些字段会参与消费进度计算、顺序消费锁判断、拉取流控等。

### 2.4 消息进入 ProcessQueue 的流程

并发消费拉取到消息后，大致流程如下图：

![RocketMQ ProcessQueue enter flow](rocketmq-processqueue-enter-flow.svg)

源码重点：

```java
processQueue.putMessage(pullResult.getMsgFoundList());
consumeMessageService.submitConsumeRequest(...);
```

来源：[DefaultMQPushConsumerImpl.java L366-L374](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/DefaultMQPushConsumerImpl.java#L366-L374)

### 2.5 消息从 ProcessQueue 移除与 offset 计算

消费结果处理后，会调用：

```java
processQueue.removeMessage(consumeRequest.getMsgs());
offsetStore.updateOffset(messageQueue, offset, true);
```

来源：[ConsumeMessageConcurrentlyService.java L306-L309](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ConsumeMessageConcurrentlyService.java#L306-L309)

`removeMessage` 的核心语义：

```text
移除已经完成结果处理的消息
如果还有未完成消息，返回最小未完成 offset
如果没有剩余消息，返回 queueOffsetMax + 1
```

源码重点：

```java
if (!msgTreeMap.isEmpty()) {
    result = msgTreeMap.firstKey();
}
```

来源：[ProcessQueue.java L187-L214](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ProcessQueue.java#L187-L214)

因此 offset 推进不是简单“拉到哪就提交到哪”，而是：

```text
提交到当前 MessageQueue 中最小未完成 offset
```

### 2.6 ProcessQueue 与本地流控

如果本地缓存太多，SDK 会延迟继续 pull。典型指标包括 `ProcessQueue.msgCount`、`ProcessQueue.msgSize`、`ProcessQueue.getMaxSpan()`。整体流程如下：

![RocketMQ ProcessQueue flow control](rocketmq-processqueue-flow-control.svg)

源码依据：`DefaultMQPushConsumerImpl.pullMessage()` 会读取 `ProcessQueue` 的消息数量、大小、offset span 做 flow control。  
来源：[DefaultMQPushConsumerImpl.java L269-L301](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/DefaultMQPushConsumerImpl.java#L269-L301)

---

## 3. SDK 中 ACK、重试与批量消费

![RocketMQ ACK, retry and batch consume](rocketmq-ack-retry-batch.svg)

## 3.1 PushConsumer 的 ACK 语义

在 `rocketmq-spring` 普通 Listener 中没有显式 `ack()`：

```java
public interface RocketMQListener<T> {
    void onMessage(T message);
}
```

来源：[RocketMQListener.java L20-L22](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/core/RocketMQListener.java#L20-L22)

Spring Adapter 的语义是：

```text
onMessage 正常返回 -> CONSUME_SUCCESS
onMessage 抛异常 -> RECONSUME_LATER
```

源码重点：

```java
container.handleMessage(messageExt);
return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
```

来源：[DefaultRocketMQListenerContainer.java L468-L484](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/support/DefaultRocketMQListenerContainer.java#L468-L484)

失败时：

```java
context.setDelayLevelWhenNextConsume(delayLevelWhenNextConsume);
return ConsumeConcurrentlyStatus.RECONSUME_LATER;
```

来源：[DefaultRocketMQListenerContainer.java L468-L484](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/support/DefaultRocketMQListenerContainer.java#L468-L484)

所以 ACK 本质不是删除消息，而是：

```text
Consumer Group + MessageQueue 维度的消费进度推进
```

官方文档要点：RocketMQ 通过 consumer offset 管理消费进度，消息不会因为某个消费者成功处理就立刻物理删除。  
来源：[RocketMQ Consumer Progress](https://rocketmq.apache.org/docs/featureBehavior/09consumerprogress/)

---

## 3.2 Concurrently：并发消费下的 ACK 与 retry

### 成功路径

![RocketMQ concurrently ACK success flow](rocketmq-concurrent-ack-success-flow.svg)

源码重点：

```java
long offset = processQueue.removeMessage(msgs);
offsetStore.updateOffset(messageQueue, offset, true);
```

来源：[ConsumeMessageConcurrentlyService.java L306-L309](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ConsumeMessageConcurrentlyService.java#L306-L309)

### 失败路径

![RocketMQ concurrently retry failure flow](rocketmq-concurrent-retry-failure-flow.svg)

源码重点：

```java
case RECONSUME_LATER:
    ackIndex = -1;
```

来源：[ConsumeMessageConcurrentlyService.java L252-L264](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ConsumeMessageConcurrentlyService.java#L252-L264)

随后失败消息会执行：

```java
sendMessageBack(msg, context);
```

来源：[ConsumeMessageConcurrentlyService.java L280-L290](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ConsumeMessageConcurrentlyService.java#L280-L290)

官方文档要点：PushConsumer 消费失败后，消息进入 `WaitingRetry`，达到重试间隔后重新变为可消费；超过最大重试次数进入 DLQ。  
来源：[RocketMQ Consumption Retry](https://rocketmq.apache.org/docs/featureBehavior/10consumerretrypolicy/)

### retry topic 如何被消费

并发消费失败后，消息会进入：

```text
%RETRY%consumerGroup
```

Consumer 启动时会自动订阅这个 retry topic：

```java
final String retryTopic = MixAll.getRetryTopic(consumerGroup);
subscriptionInner.put(retryTopic, subscriptionData);
```

来源：[DefaultMQPushConsumerImpl.java L1228-L1235](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/DefaultMQPushConsumerImpl.java#L1228-L1235)

`MixAll.getRetryTopic(group)` 的语义是：

```text
%RETRY% + consumerGroup
```

来源：[MixAll.java L179-L181](https://github.com/apache/rocketmq/blob/develop/common/src/main/java/org/apache/rocketmq/common/MixAll.java#L179-L181)

因此 Consumer 实际订阅的是：

```text
业务 Topic
retry Topic: %RETRY%consumerGroup
```

这两个 Topic 的队列都会参与 Rebalance、创建 ProcessQueue、创建 PullRequest，并共享同一个消费线程池。

### retry 和正常消息会并行吗？

会。

![RocketMQ retry and normal message parallel architecture](rocketmq-retry-normal-parallel-architecture.svg)

所以大量 retry 消息可能占用正常消息的消费线程。

最佳实践：

| 实践项 | 理由 |
|---|---|
| 只把 RocketMQ retry 用于偶发失败 | retry 消息会和正常消息共享消费线程池，长期失败会拖累正常消费 |
| 不要把 retry 当成业务分支控制或限流机制 | retry 的语义是“失败后重新投递”，不是稳定的业务调度/限流通道 |
| 监控 retry 堆积和 DLQ | 大量 retry 往往表示下游依赖、数据质量或幂等逻辑有问题 |

---

## 3.3 Orderly：顺序消费下的 ACK 与 retry

顺序消费失败时，Spring Adapter 返回：

```java
ConsumeOrderlyStatus.SUSPEND_CURRENT_QUEUE_A_MOMENT
```

来源：[DefaultRocketMQListenerContainer.java L492-L505](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/support/DefaultRocketMQListenerContainer.java#L492-L505)

语义是：

```text
当前 MessageQueue 暂停一段时间
失败消息之后的消息不能越过它继续消费
稍后重试当前队列
```

因此顺序消费不是像并发消费那样简单把失败消息投到 retry topic 后继续消费后面的消息。它更关注：

```text
保持同一个 MessageQueue 内的消费顺序
```

官方文档要点：顺序消息中，如果某条消息消费失败，后续消息需要等该消息成功后才能继续处理。  
来源：[RocketMQ FIFO Message](https://rocketmq.apache.org/docs/featureBehavior/03fifomessage/)

---

## 3.4 批量消费：Spring Adapter 的关键坑

### 默认安全：batch size = 1

`@RocketMQMessageListener` 默认：

```java
int consumeMessageBatchMaxSize() default 1;
```

来源：[RocketMQMessageListener.java L190-L192](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/annotation/RocketMQMessageListener.java#L190-L192)

所以普通 Spring Listener 默认是单条消息语义。

### 设置 `consumeMessageBatchMaxSize > 1` 后发生什么？

底层 SDK 可能一次传入：

```text
msgs = [m1, m2, m3, m4]
```

但是 `rocketmq-spring` 的默认 Adapter 不是调用 `onMessage(List<T> batch)`，而是：

```java
for (MessageExt messageExt : msgs) {
    container.handleMessage(messageExt);
}
```

来源：[DefaultRocketMQListenerContainer.java L468-L484](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/support/DefaultRocketMQListenerContainer.java#L468-L484)

所以如果 `m3` 失败：

```text
m1 成功
m2 成功
m3 失败
m4 未执行
return RECONSUME_LATER
```

而底层 SDK 收到 `RECONSUME_LATER` 后：

```text
ackIndex = -1
整批都按失败处理
```

结果可能是：

```text
m1、m2、m3、m4 都进入重试
```

这就是“一个消息失败导致一批消息重试”的来源。

### 原生 SDK 支持前缀 ACK，但 Spring 普通 Listener 不暴露

原生 `ConsumeConcurrentlyContext` 有：

```java
context.setAckIndex(index);
```

来源：[ConsumeConcurrentlyContext.java L51-L56](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/consumer/listener/ConsumeConcurrentlyContext.java#L51-L56)

底层语义：

```text
ackIndex 及之前：成功
ackIndex 之后：失败重试
```

但普通 `RocketMQListener<T>` 没有暴露 `ConsumeConcurrentlyContext`，所以不能精细控制批内 ACK。

### 真正批量消费怎么做？

如果确实需要批量消费，建议不用普通 `@RocketMQMessageListener + RocketMQListener<T>`，而是显式使用原生。示例代码（非 RocketMQ 源码）：

```java
consumer.registerMessageListener((MessageListenerConcurrently) (msgs, context) -> {
    try {
        batchHandle(msgs);
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
    } catch (Exception e) {
        return ConsumeConcurrentlyStatus.RECONSUME_LATER;
    }
});
```

或者按前缀成功控制。示例代码（非 RocketMQ 源码）：

```java
context.setAckIndex(i - 1);
return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
```

注意：`ackIndex` 只能表达“前缀成功，后缀失败”，不能表达离散成功/失败。

---

## 3.5 宕机时 ProcessQueue 未消费完怎么办？

如果机器挂了：

```text
本地 ProcessQueue 直接消失
Broker 不知道本地缓存里具体有哪些消息完成到哪一步
新的 Consumer 会从 Broker 保存的 consumer offset 继续拉取
```

因此可能重复消费的范围包括：

```text
已拉到本地但未处理的消息
正在处理但 Listener 未返回的消息
已处理成功但 offset 还未持久化到 Broker 的消息
```

因为 offset 先更新到客户端内存，再周期性持久化到 Broker。默认持久化间隔来自 `ClientConfig`：

```java
persistConsumerOffsetInterval = 1000 * 5;
```

来源：[ClientConfig.java L64-L67](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/ClientConfig.java#L64-L67)

所以 RocketMQ PushConsumer 需要按 **至少一次投递** 思维设计：

```text
业务必须幂等
```

---

## 4. 最佳实践

### 4.1 Concurrently

| 实践项 | 理由 |
|---|---|
| 默认保持 `consumeMessageBatchMaxSize = 1` | `rocketmq-spring` 默认 Adapter 是逐条 `handleMessage`，batch > 1 时一个失败可能导致整批重试 |
| 不要在 Listener 内把任务丢到自定义线程池后立刻返回成功 | PushConsumer 以 Listener 返回作为消费结果；提前返回会让 RocketMQ 误以为业务已成功 |
| 业务处理必须幂等 | offset 不是每条消息立即持久化，宕机、重试、rebalance 都可能导致重复消费 |
| 关注 retry 堆积 | retry topic 和正常 topic 共享同一个 `consumeExecutor`，堆积会抢占正常消息消费线程 |
| 大量失败时优先修业务/依赖 | RocketMQ retry 适合偶发失败，不适合承载长期失败或业务分支控制 |
| 结合 MQ 数量、实例数、业务耗时、本地流控调线程数 | 线程数只影响单实例内部执行能力，队列数和实例数决定水平分摊能力 |

### 4.2 Orderly

| 实践项 | 理由 |
|---|---|
| 只在确实需要队列内顺序时使用 | 顺序消费会牺牲吞吐，并且失败会影响当前队列后续消息 |
| 同一业务 key 路由到同一个 MessageQueue | RocketMQ 的顺序语义依赖同队列内按序推进 |
| 业务逻辑尽量短、稳、可重试 | 失败会暂停当前队列，耗时/不稳定逻辑会放大阻塞影响 |
| 不要单纯提高线程数追求顺序消费吞吐 | 顺序消费有效并发更接近 MessageQueue 数量，而不是线程池大小 |

### 4.3 批量消费

| 实践项 | 理由 |
|---|---|
| 普通 Spring Listener 不建议打开 `consumeMessageBatchMaxSize > 1` | Spring Adapter 仍然 for 循环逐条调用，失败时容易整批重试 |
| 如果要批量，优先用原生 `MessageListenerConcurrently` | 原生接口可以直接拿到 `List<MessageExt>` 和 `ConsumeConcurrentlyContext` |
| 批量处理必须幂等 | 批内部分成功后仍可能因为批量失败而重复执行 |
| 理解原生 `ackIndex` 的限制 | `ackIndex` 只能表达“前缀成功、后缀失败”，不能表达离散成功/失败 |

---

## 5. 参考资料

官方文档：

- [RocketMQ Consumer Types](https://rocketmq.apache.org/docs/featureBehavior/06consumertype/)
- [RocketMQ Consumer Load Balancing](https://rocketmq.apache.org/docs/featureBehavior/08consumerloadbalance/)
- [RocketMQ Consumer Progress](https://rocketmq.apache.org/docs/featureBehavior/09consumerprogress/)
- [RocketMQ Consumption Retry](https://rocketmq.apache.org/docs/featureBehavior/10consumerretrypolicy/)
- [RocketMQ FIFO Message](https://rocketmq.apache.org/docs/featureBehavior/03fifomessage/)
- [RocketMQ 4.x Push Consumer / Message Retry](https://rocketmq.apache.org/docs/4.x/consumer/02push/#message-retry)

源码：

- [ProcessQueue.java](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ProcessQueue.java)
- [RebalanceImpl.java](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/RebalanceImpl.java)
- [DefaultMQPushConsumerImpl.java](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/DefaultMQPushConsumerImpl.java)
- [ConsumeMessageConcurrentlyService.java](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/impl/consumer/ConsumeMessageConcurrentlyService.java)
- [ConsumeConcurrentlyContext.java](https://github.com/apache/rocketmq/blob/develop/client/src/main/java/org/apache/rocketmq/client/consumer/listener/ConsumeConcurrentlyContext.java)
- [DefaultRocketMQListenerContainer.java](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/support/DefaultRocketMQListenerContainer.java)
- [RocketMQMessageListener.java](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/annotation/RocketMQMessageListener.java)
- [RocketMQListener.java](https://github.com/apache/rocketmq-spring/blob/master/rocketmq-spring-boot/src/main/java/org/apache/rocketmq/spring/core/RocketMQListener.java)
