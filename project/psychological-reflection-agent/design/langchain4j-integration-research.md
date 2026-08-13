---
title: LangChain4j 集成与能力边界调研
status: 调研结论 v0.1
type: technical-research
depends_on:
  - "[[technical-architecture-overview]]"
  - "[[agent-foundation-prd]]"
  - "[[business-workflow-runtime-prd]]"
  - "[[psychological-reflection-workflow-prd]]"
---
# LangChain4j 集成与能力边界调研

本文评估 LangChain4j 在心理自我反思 Agent 中的适用范围，重点回答四个问题：LangChain4j 本身提供什么能力、不使用 AI Services 时能否继续使用 Tool calling、Agent 基座是否应使用 ChatMemory，以及数据库中的 Skill 如何按需提供给模型。

本文以 [[technical-architecture-overview]] 当前基线为前提：`Session 1:N Turn`、`Turn 1:1 WorkflowExecution`；Execution 不跨 Turn；MVP 不支持跨 Worker 自动接管；ReAct 中断后从当前节点入口重新执行，不恢复内部 ModelRound。

## 1. 结论

采用以下组合：

```text
自建轻量 DSL 控制流
  + LangChain4j 低层模型 API
  + 自建节点内 ReAct 驱动器
  + 显式模型上下文组装
  + 数据库 Skill 按固定版本、按需加载
```

具体边界如下：

| 能力 | 选型结论 |
| --- | --- |
| 模型供应商接入 | 使用 LangChain4j `ChatModel`／`StreamingChatModel` |
| Tool calling 协议 | 使用低层 `ToolSpecification`、`ToolExecutionRequest`、`ToolExecutionResultMessage` |
| 节点内 ReAct | 自建循环，LangChain4j 只执行每个 ModelRound |
| 简单 LLM 节点 | 可选用 AI Services，但不进入核心 ReAct 链路 |
| ChatMemory | MVP 不作为持久化或会话真相源；优先显式维护 `List<ChatMessage>` |
| 原始对话 | 由 `foundation.session` 持久化 |
| 长期记忆 | 由 `foundation.memory` 按业务状态持久化 |
| Skill 内容 | 从 MySQL 或 MongoDB 读取，Execution 固定版本，模型按需调用 `load_skill` |
| 流程编排 | 保留自建轻量 DSL 内核 |
| `langchain4j-agentic` | 只作为候选 PoC，不进入 MVP 核心链路 |

核心原则是：业务存储决定「事实是什么」，上下文组装器决定「这一次让模型看到什么」，LangChain4j 负责「如何与模型通信」。

## 2. LangChain4j 能力边界

### 2.1 低层模型 API

LangChain4j 通过统一接口适配不同模型供应商：

- `ChatModel`：同步聊天调用。
- `StreamingChatModel`：流式聊天调用。
- `ChatRequest`／`ChatResponse`：请求、响应及元数据。
- `SystemMessage`、`UserMessage`、`AiMessage`、`ToolExecutionResultMessage`：统一消息模型。
- `ToolSpecification`：供应商无关的工具描述和参数 schema。
- `ResponseFormat`／`JsonSchema`：结构化输出约束。
- `ChatModelListener`：请求、响应和错误观测。

统一接口不能消除全部供应商差异。目标供应商仍需验证以下能力：

- 是否支持 Tool calling 和并行工具调用。
- 工具调用是否返回稳定的 call ID。
- 是否支持 partial tool call。
- 是否支持 JSON Schema，或者只能使用 JSON mode／Prompt 约束。
- usage、finish reason 和错误类型是否完整。
- 同步、流式和取消行为是否一致。

### 2.2 AI Services

AI Services 使用 Java 接口声明 LLM 服务，可自动完成：

- 方法参数到消息的转换。
- Java 方法到工具定义的转换。
- 工具参数解析和 Java 方法调用。
- 工具结果回传模型。
- 工具调用后的后续模型请求。
- ChatMemory、结构化输出、Guardrail 和流式响应集成。

AI Services 适合无复杂工具循环的单次分类、布尔判断、信息提取和结构化转换。它会隐藏一次服务调用内部的多个 ModelRound，因此不用于本项目核心 ReAct 节点。

即使不使用 AI Services，Tool calling 仍然可用，只是自动循环改由项目实现：

```text
创建 ToolSpecification
  → ChatModel 返回 ToolExecutionRequest
  → 运行时校验并执行工具
  → 创建 ToolExecutionResultMessage
  → 连同稳定上下文再次调用 ChatModel
```

如果工具来自固定 Java 方法，可以通过 `ToolSpecifications.toolSpecificationsFrom(...)` 复用注解和反射生成工具定义；如果工具来自数据库制品，应直接从受控 schema 构建 `ToolSpecification`。

### 2.3 ChatMemory

ChatMemory 是模型工作记忆，不是完整对话历史。LangChain4j 提供：

- `MessageWindowChatMemory`：按消息数量保留窗口。
- `TokenWindowChatMemory`：按 token 预算保留窗口。
- `ChatMemoryStore`：自定义持久化。
- SystemMessage 的保留和替换规则。
- 工具请求与工具结果的成对淘汰。

ChatMemory 可能淘汰、摘要或改写模型上下文。官方明确区分：History 保存用户实际看到的完整记录，Memory 只保存供模型使用的部分信息。

### 2.4 Skills API

LangChain4j Skills API 支持：

- 从文件系统或 classpath 加载 Skill。
- 使用 builder 从数据库、远程 API 或运行时数据创建 `Skill`。
- `activate_skill` 按需加载完整指令。
- `read_skill_resource` 读取 Skill 附属资源。
- Skill 激活后才暴露 scoped tools。

Skills API 当前被官方标记为 experimental。它可以作为参考或 PoC，但本项目不依赖它定义 Skill 制品生命周期。

### 2.5 Agentic 编排

`langchain4j-agentic` 提供 sequence、conditional、loop、parallel、human-in-the-loop、AgenticScope、checkpoint 和恢复等能力，但整个模块当前仍为 experimental，且主要面向 Java builder／注解式编排。

本项目需要后台发布的版本化 WorkflowDefinition DSL、节点注册、输入输出校验、Skill／Prompt 版本绑定和领域 SPI，因此 MVP 保留自建轻量 DSL 控制流。Agentic 模块只做独立 PoC，不作为 WorkflowExecution 的权威执行内核。

## 3. 模块落点

### 3.1 总体调用关系

```text
runtime.engine
  └── 解释 WorkflowDefinition DSL
      └── 调用领域节点
          └── runtime.react.ReactExecutor
              └── foundation.model.ModelGateway
                  └── LangChain4j
                      ├── ChatModel
                      └── StreamingChatModel
```

依赖约束：

- 仅 `foundation.model` 直接依赖 LangChain4j 模型供应商实现。
- `runtime.react` 只依赖项目自己的模型调用契约。
- `domain` 不引用任何 `dev.langchain4j.*` 类型。
- `runtime.spi` 只暴露不可变 DTO 和受限能力接口。
- `ApplicationModules.verify()` 继续校验模块边界。

### 3.2 Agent 基座中的模型网关

`foundation.model` 保留业务无关的生产控制：

- 模型路由快照、供应商启停、权重和降级顺序。
- User、模型和 token 维度的配额与并发限制。
- 超时、最大上下文、最大输出和取消。
- 重试、熔断和失败降级。
- 请求、响应及供应商事件的统一映射。
- usage、模型版本、耗时和成本元数据记录。
- 正文不得进入日志、指标 tag 或成本流水。

建议定义项目自己的接口，不向上泄漏 LangChain4j 类型：

```java
public interface ModelGateway {
    ModelResult invoke(ModelRequest request);
    ModelStreamHandle stream(ModelRequest request, ModelEventConsumer consumer);
}
```

```java
public record ModelRequest(
        UserContext user,
        String executionId,
        String modelRoute,
        List<ModelMessage> messages,
        List<ModelTool> tools,
        OutputSchema outputSchema,
        ModelLimits limits
) {}
```

```java
public sealed interface ModelResult {
    record FinalText(String text, ModelUsage usage) implements ModelResult {}
    record ToolCalls(List<ModelToolCall> calls, ModelUsage usage) implements ModelResult {}
    record Structured(String json, ModelUsage usage) implements ModelResult {}
    record Failed(ModelError error) implements ModelResult {}
}
```

`foundation.model` 内部再完成项目 DTO 与 LangChain4j `ChatRequest`、`ChatResponse`、`ToolSpecification` 和 `ResponseFormat` 的双向映射。

## 4. 节点内 ReAct 落地

### 4.1 运行时职责

`runtime.react` 掌握整个 ReAct 循环：

- ModelRound 数量和总 token 预算。
- 节点总超时和每轮模型超时。
- 当前节点允许的 Skill／工具集合。
- 工具参数、领域、版本和权限校验。
- 工具顺序执行或受控并行。
- 工具异常、重试和模型降级。
- 工具轮次与最终答案的区分。
- 每轮模型和工具 trace。
- 取消信号。
- 最终结果到 OutputSink 的交付。

### 4.2 单轮结果

每个 ModelRound 聚合后只产生一种结果：

| 结果 | 条件 | 后续动作 |
| --- | --- | --- |
| `ToolRequests` | 响应包含完整、合法的工具请求 | 执行工具，回填结果，开始下一轮 |
| `FinalAnswer` | 响应不包含工具请求，且形成完整文本或结构化结果 | 结束 ReAct，交给 OutputSink |
| `Failed` | 供应商错误、协议不完整、工具非法或预算耗尽 | 重试、降级或终止节点 |

同一轮同时包含正文和工具请求时，聚合结果一律为 `ToolRequests`。正文作为该轮 assistant message 的一部分回填下一轮模型上下文，但不得进入 Turn 用户可见正文或 SSE。

### 4.3 循环示意

```java
while (budget.canContinue()) {
    ModelResult result = modelGateway.invoke(currentRequest);

    switch (result) {
        case ModelResult.ToolCalls calls -> {
            List<ModelMessage> toolResults = toolExecutor.execute(
                    toolPolicy.validate(calls.calls(), allowedSkills)
            );
            context.append(calls);
            context.append(toolResults);
            budget.recordRound(calls.usage());
        }
        case ModelResult.FinalText text -> {
            return ReactResult.finalText(text.text(), budget.snapshot());
        }
        case ModelResult.Structured structured -> {
            return ReactResult.structured(structured.json(), budget.snapshot());
        }
        case ModelResult.Failed failed -> {
            if (!retryPolicy.canRetry(failed.error(), budget)) {
                return ReactResult.failed(failed.error());
            }
        }
    }
}
```

以上是接口草案，用于固定职责边界，不是待直接复制的实现代码。

### 4.4 流式事件映射

LangChain4j `StreamingChatResponseHandler` 可映射为项目供应商事件：

| LangChain4j 回调 | 项目事件 |
| --- | --- |
| `onPartialResponse` | `content_delta` |
| `onPartialToolCall` | `tool_call_delta` |
| `onCompleteToolCall` | 完整工具请求片段 |
| `onCompleteResponse` | `finish` 和 `usage` |
| `onError` | `error` |
| `onPartialThinking` | 丢弃或进入受控内部 trace，禁止发给前端 |

调用链保持为：

```text
LangChain4j callback
  → ModelResponseAdapter
  → ModelRoundAggregator
  → ToolRequests / FinalAnswer / Failed
  → OutputSink
  → Turn / MQ / SSE
```

当前心理流程基线采用 `buffered_text`，MVP 可以优先接同步 `ChatModel`。只有领域 PRD 明确允许 `stream_text` 后，才接通模型流到用户 SSE 的最后一段。

## 5. ChatMemory 取舍

### 5.1 使用 ChatMemory 的优点

- 自动维护消息数量或 token 窗口。
- 自动保留和替换 SystemMessage。
- 自动保持工具请求与工具结果消息成对。
- 与 AI Services 集成简单。
- 可通过 `ChatMemoryStore` 接入自定义存储。

### 5.2 使用 ChatMemory 的缺点

- Memory 不等于用户可见 History，不能替代 Session／Turn。
- 窗口淘汰的消息也会从 `ChatMemoryStore` 中删除。
- `updateMessages()` 在消息变化时全量更新当前列表，ReAct 可能产生频繁写入。
- AI Services 不保护同一 `memoryId` 的并发调用。
- 自动累积会降低上下文来源和授权审计的透明度。
- 无法表达长期记忆的待确认、激活、拒绝、删除、版本和来源引用。
- 用户删除或撤销授权时，还需要处理缓存失效和残留上下文。

### 5.3 MVP 决策

MVP 不使用持久化 ChatMemory，采用显式上下文组装：

```text
foundation.session 的完整对话
  + foundation.memory 中已授权、已激活的记忆点
  + 固定版本 Prompt
  + 当前节点材料
  + 当前 ReAct 工具消息
  → ContextAssembler
  → List<ModelMessage>
  → ModelGateway
```

ReAct 内部使用 `List<ChatMessage>` 或等价的项目消息列表维护稳定上下文。这样删除、授权和版本变更能在下一次组装时立即生效，恢复时也可以从权威存储重新组装。

如果后续确实需要复用 token 窗口与工具消息淘汰能力，可以引入 Execution 级、非持久化 `TokenWindowChatMemory`：

- `memoryId` 使用 `executionId`，不使用 `sessionId`。
- 仅在当前 Execution 内共享。
- Execution 结束后清理。
- 不保存长期记忆的权威状态。
- 进程恢复时从节点入口重新组装，不恢复 ChatMemory 内部临时消息。

## 6. 数据库 Skill 按需加载

### 6.1 Skill 与工具的区别

指令型 Skill 是给模型的行为说明，例如剖析引导、总结格式和危机响应要求。执行型能力是受控 Java 工具，例如读取激活记忆、保存业务结果和查询 Session。

两者关系如下：

```text
SkillDefinition
  └── 告诉模型应该按什么规则工作、何时调用哪些工具

ToolSpecification + ToolExecutor
  └── 真正执行读取和写入
```

数据库只保存 Skill 指令、资源、工具引用和参数 schema，不保存并动态执行任意代码。实际 ToolExecutor 必须来自预注册、可测试的 Java 实现。

### 6.2 数据来源

LangChain4j Skill 可以通过 builder 从任意来源创建，因此 MySQL、MongoDB、远程 API 或配置中心均可作为来源：

```java
Skill skill = Skill.builder()
        .name(definition.key())
        .description(definition.description())
        .content(definition.content())
        .resources(toResources(definition.resources()))
        .build();
```

但是，当前项目强调按需加载和版本固定，不直接采用「Execution 启动时把所有 Skill 正文加载进内存」的模式。

### 6.3 推荐流程

Execution 创建时：

```text
读取已发布 WorkflowDefinition
  → 解析节点引用的 Skill
  → 校验版本仍可用于新实例
  → 固定 skillId + version
  → 保存 Execution 的绑定清单
```

节点执行时：

```text
读取当前节点绑定的 Skill name + description
  → 只把目录提供给模型
  → 同时暴露 load_skill(skill_id)
```

模型请求 `load_skill` 后：

```text
解析参数
  → 校验 Skill 属于当前领域
  → 校验当前节点允许使用
  → 校验 Execution 已绑定该 skillId + version
  → 按固定版本查询 MySQL／MongoDB 或版本缓存
  → 返回 Skill 正文
  → 写入 ModelCallTrace
```

模型不得指定版本，运行时也不得在工具调用时查询 `latest`。

### 6.4 `load_skill` 低层工具

```java
ToolSpecification loadSkill = ToolSpecification.builder()
        .name("load_skill")
        .description("加载当前节点允许使用的 Skill")
        .parameters(JsonObjectSchema.builder()
                .addStringProperty("skill_id")
                .required("skill_id")
                .build())
        .build();
```

工具执行器只接受绑定清单中的 ID：

```java
String execute(ToolExecutionRequest request) {
    LoadSkillArguments args = parseAndValidate(request.arguments());
    BoundSkill bound = executionSkills.requireAllowed(args.skillId());

    SkillDefinition skill = skillRepository.findByIdAndVersion(
            bound.skillId(),
            bound.version()
    );

    return skill.content();
}
```

工具至少校验：

- `skill_id` 参数合法。
- Skill 属于当前领域命名空间。
- 当前节点允许使用。
- Execution 已固定该版本。
- 版本存在且未被逻辑删除。
- SkillDefinition 不包含 User 正文。
- 拒绝原因进入 trace，但不向模型泄漏内部数据。

### 6.5 MySQL 与 MongoDB 的选择

从 LangChain4j 角度，两者都能工作。存储选择应服从项目自身事务和查询需求：

- WorkflowDefinition、SkillDefinition、PromptDefinition 的发布状态、版本绑定和引用完整性需要强一致，优先放 MySQL。
- Skill 大正文或附属资源如果放 MongoDB，MySQL 仍应保存版本、发布状态和内容引用；发布时必须确保引用内容已经存在且不可变。
- Execution 绑定的是完整版本标识和内容引用，不能只绑定 MongoDB 中可被原地覆盖的文档 ID。
- 可以增加按 `skillId + version` 的只读缓存，但发布新版本必须使用新键，不能覆盖旧版本缓存。

## 7. 不采用的方案

### 7.1 ChatMemory 作为 Session 存储

不采用。ChatMemory 会淘汰消息，不能保存完整用户历史，也不表达 Turn 状态、删除和授权。

### 7.2 ChatMemory 作为长期记忆存储

不采用。长期记忆必须由 `foundation.memory` 保存状态、版本、来源和用户确认记录。

### 7.3 AI Services 自动执行核心 ReAct

不采用。自动工具循环会隐藏 ModelRound、权限、预算和中间输出边界。

### 7.4 Skills API 作为制品真相源

不采用。Skills API 可承载运行时 Skill 对象，但发布、版本、停用、命名空间和 Execution 绑定仍由项目运行时负责。

### 7.5 LangChain4j Agentic 直接替换动态 DSL 内核

MVP 不采用。当前模块为 experimental，且仍需自建 DSL 编译、制品生命周期、Execution／Turn、领域 SPI 和一致性适配。

## 8. 验证清单

### 8.1 模型网关

- 至少验证两个目标供应商的同步调用。
- 验证模型路由快照、超时、重试、降级和取消。
- 统一 usage、finish reason 和错误分类。
- 验证正文不进入日志、指标 tag 和成本流水。
- 验证 Spring Boot 3.5、Java 17 与 Spring Modulith 边界。

### 8.2 Tool calling 与 ReAct

- 单工具、多工具和并行工具请求。
- 无 call ID 或不支持 partial tool call 的供应商。
- 非法工具名、错误参数和越权 Skill。
- 工具轮同时返回正文时，正文不进入 SSE。
- ModelRound、token、超时和工具次数上限。
- 工具失败的可重试、不可重试和降级路径。
- 取消后不继续执行后续工具。

### 8.3 结构化和流式输出

- JSON Schema 支持与不支持的供应商。
- JSON mode／Prompt 降级后的解析失败处理。
- 结构化成功后继续执行领域校验。
- `buffered_text` 未通过校验时不写用户可见正文。
- 真正启用 `stream_text` 后，再验证 token 顺序、事件游标和取消。

### 8.4 Skill

- Execution 创建时固定 Skill 版本。
- Skill 停用后，已有 Execution 仍按绑定版本运行，新 Execution 不再绑定。
- `load_skill` 不接受模型指定的版本。
- MySQL／MongoDB 查询失败、缓存失效和内容缺失处理。
- Skill 正文和资源不包含 User 数据。
- 按 `executionId + nodeId + skillId + version` 记录 trace。

### 8.5 上下文与记忆

- Session 删除、记忆删除或撤销授权后，下一次组装不再包含旧内容。
- 上下文超限时按确定性优先级裁剪。
- 工具请求和工具结果保持配对。
- 进程恢复时从权威存储重新组装，不依赖内存残留。
- 不同 User、Session 和 Execution 的上下文不串用。

## 9. 官方资料

- [LangChain4j AI Services](https://docs.langchain4j.dev/tutorials/ai-services)
- [LangChain4j Tools](https://docs.langchain4j.dev/tutorials/tools)
- [LangChain4j Response Streaming](https://docs.langchain4j.dev/tutorials/response-streaming)
- [LangChain4j Structured Outputs](https://docs.langchain4j.dev/tutorials/structured-outputs)
- [LangChain4j Chat Memory](https://docs.langchain4j.dev/tutorials/chat-memory)
- [LangChain4j Skills](https://docs.langchain4j.dev/tutorials/skills)
- [LangChain4j Agents and Agentic AI](https://docs.langchain4j.dev/tutorials/agents)
- [LangChain4j Spring Boot Integration](https://docs.langchain4j.dev/tutorials/spring-boot-integration)

