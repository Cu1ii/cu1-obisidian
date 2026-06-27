# OpenTelemetry（含 Java Spring / Go 最佳实践）· 课程大纲

> 这份大纲定义了完成本课题后你将掌握的所有能力。
> 学习深度：标准
> 文档数量因人而异，但掌握内容不打折扣。

## 核心掌握项

完成本课题后，你将能够：

### 一、核心概念与数据模型

- [ ] 能用自己的话解释 Traces / Metrics / Logs 三类 Signal 的本质区别与各自适用的问题域
- [ ] 能画出一次跨服务调用的 Span 树，并说明 trace_id / span_id / parent_span_id 的含义与生成时机
- [ ] 能区分 OTel API、SDK、Collector、Exporter 各自的职责与边界，并解释为什么 API/SDK 必须分离
- [ ] 能解释 Context Propagation（W3C TraceContext + Baggage）的工作原理，并读懂 `traceparent` header 的字段含义

### 二、Java Spring 接入与最佳实践

- [ ] 能判断何时用 Java Agent（auto-instrumentation）、何时用 Spring Boot Starter、何时手写 SDK，并说明各自代价
- [ ] 能在 Spring Boot 应用中为 Spring MVC / WebClient / JDBC 接入 OTel，并向 Span 添加自定义 Attributes
- [ ] 能用 `@WithSpan` 或编程方式创建自定义 Span，并避免 Span 泄漏与 Context 丢失（如异步线程池场景）

### 三、Go 接入与最佳实践

- [ ] 能在 Go 服务中正确初始化 TracerProvider / MeterProvider，并通过 `defer shutdown` 优雅清理
- [ ] 能为 `net/http`、gRPC、`database/sql` 等典型库织入 otelhttp / otelgrpc instrumentation
- [ ] 能用 `context.Context` 正确派生 Span，识别"Context 没传下去导致 Trace 断裂"的反模式

### 四、生产实战与可观测性体系

- [ ] 能设计一个 OTel Collector 管道（receivers / processors / exporters），并解释 Agent / Gateway 部署模式的选择
- [ ] 能判断 Head Sampling vs Tail Sampling 的适用场景，并设计合理采样率
- [ ] 能识别并避免常见反模式：高基数 Attribute、Span 内存泄漏、过度采样、跨语言 Context 丢失

## 不在本课题范围内

- Prometheus / Grafana / Jaeger / Tempo 等后端的深度部署与调优（只触及"对接 OTel"层面）
- eBPF / Service Mesh（Istio / Linkerd）侧的零侵入遥测方案
- 商业 APM 厂商（Datadog / NewRelic / Dynatrace）对比与选型
- OpenTelemetry Logs SDK 的语言级细节（成熟度差异较大，仅在数据模型层覆盖）

## 学习进度

| 文档 | 覆盖掌握项 | 生成日期 |
|------|-----------|---------|
| （每次生成新文档后自动追加一行） |
