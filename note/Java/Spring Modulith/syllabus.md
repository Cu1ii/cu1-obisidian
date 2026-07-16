# Spring Modulith · 课程大纲

> 这份大纲定义了完成本课题后你将掌握的所有能力。
> 学习深度：标准
> 文档数量因人而异，但掌握内容不打折扣。

## 核心掌握项

完成本课题后，你将能够：

### 模块化思维与边界识别

- [x] 能够解释 Spring Modulith 解决的问题：在单体应用内部显式建模模块边界，而不是直接拆微服务
- [x] 能够根据业务能力划分应用模块，并判断哪些包应该成为模块 API，哪些包应该保持内部实现
- [x] 能够区分简单模块、进阶模块、嵌套模块、开放模块四种建模方式的适用场景

### 结构约束与依赖治理

- [x] 能够使用 `ApplicationModules.of(...)` 生成应用模块模型，并用 `verify()` 验证模块依赖是否违规
- [x] 能够使用 `@ApplicationModule(allowedDependencies = ...)` 明确声明允许依赖的模块
- [x] 能够使用 `@NamedInterface` 暴露模块的特定接口面，避免其他模块依赖内部包

### 模块间协作与事件解耦

- [x] 能够判断什么时候应该用直接方法调用，什么时候应该用应用事件解耦模块协作
- [x] 能够使用 `@ApplicationModuleListener` 编写事务边界清晰的模块事件监听器
- [x] 能够解释事件发布登记表（Event Publication Registry）如何提升异步事件处理可靠性

### 测试、文档化与重构落地

- [ ] 能够使用 `@ApplicationModuleTest` 对单个模块做集成测试，而不是每次启动完整应用
- [ ] 能够使用 `PublishedEvents` 或 `Scenario` 验证模块事件是否按预期发布和消费
- [ ] 能够使用 `Documenter` 生成模块关系图与 Application Module Canvas，辅助评审重构结果
- [ ] 能够为现有 Spring Boot 项目制定渐进式 Spring Modulith 重构步骤

## 不在本课题范围内

- 不讲 Spring Boot、Spring Data、事务、领域事件的基础语法；默认你已有 Spring Boot 项目经验。
- 不完整展开微服务拆分、DDD 战略设计、事件风暴方法论，只在 Spring Modulith 落地需要时引用。
- 不替你直接重构项目源码；本课题提供判断框架、API 用法、验证方法，你在项目中实践后再带问题回来讨论。
- 不覆盖所有 Spring Modulith 扩展配置，只优先覆盖官方核心能力：模块建模、依赖验证、事件协作、测试、文档化。

## 学习进度

| 文档 | 覆盖掌握项 | 生成日期 |
|------|-----------|---------|
| [[note/Java/Spring Modulith/01.md\|01.md]] | Spring Modulith 定位；模块边界识别；`ApplicationModules.of(...).verify()` 入门 | 2026-06-23 |
| [[note/Java/Spring Modulith/02.md\|02.md]] | 四种模块建模方式；`allowedDependencies` 依赖白名单；`@NamedInterface` 命名接口面 | 2026-07-03 |
| [[note/Java/Spring Modulith/03.md\|03.md]] | 直接调用与事件协作的判断；`@ApplicationModuleListener`；事件发布登记表与 MyBatis/JDBC 落地 | 2026-07-05 |
