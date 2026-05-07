# Spring Boot 热更新 IDEA 插件 - 需求规格说明书

> 状态：V1.1（L2 热更新方案，工期 2-3 个月）
> 编写日期：2026-05-02
> 适用范围：本地热更新（一期），远程热更新（二期规划）
> 定位：真正的类级别热更新，不重启 JVM / ClassLoader

---

## 1. 项目目标

开发一款开源的 IntelliJ IDEA 插件，配合自研 Java Agent，为 Spring Boot 项目提供**真正的类级别热更新**能力——替换类字节码而不重启 JVM 或丢弃 ClassLoader。

- **开源**：代码托管于公开仓库，接受社区贡献
- **兼容**：支持 IntelliJ IDEA 2022.x 及以上版本（Ultimate / Community）
- **零依赖**：不依赖 `spring-boot-devtools`，不依赖 DCEVM，不依赖 JRebel
- **标准 JDK**：支持主流 OpenJDK / Oracle JDK 8 / 11 / 17 / 21，无需用户替换 JVM
- **工期**：2-3 个月，个人开发者可独立完成核心链路

---

## 2. 市面上方案的能力边界（参考）

| 能力 | JRebel（商业） | HotSwapAgent（开源） | 本插件目标（一期） |
|---|---|---|---|
| 方法体修改 | ✅ 毫秒级 | ✅ 毫秒级 | ✅ 毫秒级 |
| 新增/删除方法 | ✅ | ✅ | ✅ |
| 新增/删除字段 | ✅ | ✅ | ✅ |
| 新增/删除类 | ✅ | ✅ | ✅ |
| 修改方法签名（参数/返回值） | ✅ | ❌ | ❌（2-3 个月做不到） |
| 修改注解后 Spring 刷新 | ✅ | ⚠️ 部分（插件不完善） | ❌（需要 Spring 框架级集成） |
| 修改接口实现 / 类继承 | ✅ | ❌ | ❌（JVM 规范禁止） |
| `static final` 常量 | ❌ | ❌ | ❌（编译期内联，无解） |
| 框架插件（MyBatis / Hibernate） | ✅ 丰富 | ⚠️ 有但不完善 | ❌（不在一期范围） |
| 远程热部署 | ✅ | ❌ | 二期规划 |
| 依赖条件 | 付费 | 需 DCEVM / JBR | **标准 JDK 即可** |

**核心差异化**：
- 比 HotSwapAgent 简单：不依赖 DCEVM，标准 JDK 开箱即用
- 比 JRebel 轻量：开源免费，只聚焦最常用、最稳定的类结构变更
- 不支持方法签名变更：这是 JRebel 的核心护城河，2-3 个月无法突破

---

## 3. 热更新能力分层定义

| 级别 | 名称 | 支持范围 | 本插件定位 |
|---|---|---|---|
| **L1** | 方法体热替换 | 仅方法内部逻辑 | ✅ 已覆盖 |
| **L2** | 结构变更热替换 | 新增/删方法、字段、类 | ✅ **一期核心目标** |
| **L3** | 框架级热替换 | 注解刷新、MyBatis XML、JPA 实体 | ❌ 不在一期 |
| **L4** | 签名级热替换 | 方法签名变更后级联更新调用方 | ❌ 2-3 个月做不到 |
| **L5** | 全量热替换 | 继承关系、接口实现、枚举 | ❌ JVM 规范限制，行业无解 |

---

## 4. 用户故事

### US-001 作为开发者，我希望保存代码后自动触发热更新

- 我修改 Java 代码并按下 `Ctrl+S` 后，插件自动编译变更并推送 Agent 进行类替换
- 替换在毫秒级完成，应用无需重启，HTTP 请求不中断
- 我可以关闭自动模式，完全由自己控制更新时机

### US-002 作为开发者，我希望手动控制热更新时机

- 我可以通过工具栏按钮或快捷键手动触发热更新
- 手动触发时，插件立即编译所有待变更类并一次性推送 Agent
- 即使开启了自动模式，我也能随时手动强制触发一次

### US-003 作为开发者，我希望修改 Java 方法体后毫秒级生效

- 我修改已有方法的内部逻辑，热更新后新逻辑立即生效
- 正在执行的请求不受影响，新进入的请求走新逻辑

### US-004 作为开发者，我希望新增/删除方法、字段或类后热更新生效

- 我在现有类中新增或删除方法，热更新后新结构立即可用
- 我在现有类中新增或删除字段，热更新后新字段可读写
- 我新增一个完整的 Java 类，热更新后新类可被 Spring 容器和其他类正常引用
- 我删除一个不再使用的类，热更新后该类从 JVM 中卸载

### US-005 作为开发者，我希望热更新失败时收到清晰提示

- 热更新失败时，IDEA 状态栏显示失败原因（如"字段类型变更不支持"、"类加载器隔离"）
- 弹出 Balloon 通知，附带失败详情和解决建议
- 当我需要排查时，可开启详细日志模式，查看每个类的热更新结果与 Agent 返回的错误码

### US-006 作为开发者，我希望在多模块 Maven/Gradle 项目中正确识别目标进程

- 我的项目包含多个子模块，一个 IDEA 窗口只运行一个 Spring Boot 应用
- 插件准确识别当前窗口中正在运行的 Spring Boot JVM 进程
- 热更新只推送变更到该进程，不影响其他未运行模块

### US-007 作为开发者，我希望通过 IDEA 连接到远程开发机进行热更新（二期）

- 我在本地 IDEA 修改代码，实际运行环境在远程开发机上
- 插件支持将本地编译后的类文件热更新到远程机器上的 Spring Boot 进程
- 远程更新的失败提示与本地一致

---

## 5. 功能需求

### FR-001 自动/手动触发模式

- 插件提供两种触发模式，在 **Settings | Tools | Hot Update** 中切换：
  - **Auto**：监听 `.java` 文件保存事件，自动编译并触发热更新
  - **Manual**：不自动响应保存，仅通过工具栏按钮或快捷键触发
- 模式切换即时生效，无需重启 IDEA
- 默认模式：**Manual**（避免半成品代码被推送）

### FR-002 Java 类结构变更热更新（一期）

**明确支持的变更类型：**
- 方法体逻辑修改
- 新增 / 删除方法（包括修改方法访问修饰符）
- 新增 / 删除 / 修改字段（非 `static final`）
- 新增 / 删除类（包括内部类、匿名类）

**明确不支持的变更类型（一期排除，遇到时提示失败）：**
- 修改类继承关系（extends / superclass）
- 修改接口实现列表（implements）
- 修改方法签名导致调用点不兼容（参数类型/数量、返回值类型）
- 修改注解中的元数据（如 `@Value`、`@Autowired`）——字节码可换，但 Spring 不会重新解析
- 修改 `static final` 基本类型 / String 常量（编译期内联问题）
- 修改枚举类型（添加/删除枚举值）

### FR-003 Agent 自动注入

- 插件检测到用户启动 Spring Boot 应用时，**自动**在 JVM 启动参数中追加 `-javaagent:插件内置Agent路径`
- 用户无需手动下载 Agent 或修改 JVM 参数
- Agent jar 随插件一起分发，安装插件即获得 Agent
- 用户可在设置中查看当前使用的 Agent 版本和路径

### FR-004 失败处理与降级

- 热更新失败后，IDEA 状态栏显示红色图标 + 简短失败原因
- 弹出 Balloon 通知，包含：
  - 失败原因摘要（如"不支持修改接口实现"、"类版本不兼容"）
  - **View Details** 按钮：打开热更新日志面板
- 详细日志模式（`-X` 启动参数或设置中的 Debug 开关）：
  - 打开 **Hot Update** 工具窗口
  - 列出本次尝试中所有变更的类
  - 标注状态：Success / Failed / Skipped
  - Failed 类附带 Agent 返回的具体错误信息（JVM 错误码 / 异常堆栈）
- **不涉及"强制重启应用"按钮**——本插件定位是热更新，不提供 restart 降级路径

### FR-005 Spring Boot 进程识别

- 插件自动扫描当前 IDEA 窗口内正在运行的 Run Configuration
- 识别目标进程的依据（优先级由高到低）：
  1. 当前激活的 Run Configuration 类型为 `Spring Boot`
  2. 正在运行的 JVM 主类包含 `@SpringBootApplication` 注解
  3. 正在运行的 JVM 主类名匹配 `*Application` 通配模式
- 若窗口内有多个符合条件的进程，弹出选择框让用户指定目标
- 若窗口内无符合条件的进程，状态栏提示"未检测到 Spring Boot 进程"

### FR-006 配置持久化

- 插件配置同时支持 **IDE 全局级别** 和 **项目级别**
- 项目级配置存储于 `.idea/hot-update.xml`
- 项目级配置覆盖全局配置，未设置的项目沿用全局默认值
- 可配置项包括：
  - 触发模式（Auto / Manual）
  - 详细日志开关
  - 自动编译前等待延迟（防抖，毫秒，默认 300ms）
  - Agent 通信超时（毫秒，默认 5000ms）

---

## 6. 非功能需求

### NFR-001 性能

- 从文件保存到热更新完成的延迟应 **< 1 秒**（单模块，10 个类以内变更）
- Agent 类替换操作本身应在 **< 100ms** 内完成
- 自动模式下，保存防抖延迟默认 300ms

### NFR-002 兼容性

- 支持 IntelliJ IDEA 2022.1 及以上版本（Ultimate / Community）
- 支持 Windows、macOS、Linux 操作系统
- 支持 Spring Boot 2.x 和 3.x
- 支持标准 OpenJDK / Oracle JDK 8 / 11 / 17 / 21
- **不需要用户安装 DCEVM 或替换 JVM**

### NFR-003 稳定性

- 热更新失败不得导致目标 JVM 崩溃、僵死或类加载器泄漏
- Agent 内部异常必须被捕获，不得向上传播导致 JVM 不稳定
- 所有 Agent 与插件的通信必须设置超时（默认 5 秒）
- 插件自身异常不得阻塞 IDEA 主线程或编译流程

### NFR-004 可维护性

- 代码需包含完整的中文/英文注释（面向开源社区）
- 提供 CONTRIBUTING.md，说明本地调试插件和 Agent 的步骤
- 核心逻辑（变更检测、类替换通信）与 IDEA UI 层解耦，便于单元测试
- Agent 模块独立编译为 jar，与 IDEA 插件模块分离

---

## 7. 技术方案

### 7.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    IntelliJ IDEA 插件层                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ 文件变更监听  │  │ 进程检测/通信 │  │ UI（状态栏/面板） │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │ Socket / 共享内存 / JMX
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      Java Agent 层                          │
│  ┌────────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Instrumentation│  │ 类结构变更处理│  │ 类加载器协调   │  │
│  │ redefineClasses│  │（方法/字段/类）│  │（支持新增类） │  │
│  └────────────────┘  └──────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 7.2 Agent 核心原理

1. **启动注入**：插件在 Spring Boot 进程启动时，通过修改 Run Configuration 的 VM options，自动追加 `-javaagent:路径/hot-update-agent.jar`
2. **类文件监听**：Agent 通过 `Instrumentation.addTransformer()` 注册 `ClassFileTransformer`，拦截类加载事件
3. **类替换**：
   - 方法体变更：直接使用 `Instrumentation.redefineClasses()`
   - 结构变更（新增方法/字段/类）：通过自定义字节码操作（ASM/Javassist）生成新类定义，利用 Agent 的类加载器协调能力完成替换
   - 新增类：通过目标 ClassLoader 的 `defineClass()` 动态注入
4. **通信协议**：插件与 Agent 之间通过本地 Socket（或 JMX）传输变更类的字节码

### 7.3 关键技术决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| 字节码操作库 | **ASM**（或 Javassist） | ASM 更轻量、控制更精细；Javassist API 更友好，适合快速开发 |
| 通信方式 | **本地 Socket**（localhost:随机端口） | 简单可靠，跨平台，易调试 |
| 新增类处理 | 通过目标 ClassLoader `defineClass()` | Instrumentation 原生不支持新增类，需借助 ClassLoader 反射 |
| 类加载器策略 | 识别 Spring Boot 的 `LaunchedURLClassLoader` | Spring Boot 用自定义 ClassLoader，Agent 需与之协调 |

---

## 8. 里程碑规划（2-3 个月）

### Week 1-2：插件脚手架 + Agent PoC

- [ ] IDEA 插件项目搭建（Gradle + IntelliJ Platform Gradle Plugin）
- [ ] Agent 模块搭建（独立子项目，输出 jar）
- [ ] PoC：Agent 成功附加到运行中的 Spring Boot 进程，完成一次简单的 `redefineClasses`
- [ ] 验证 Spring Boot 3.x + JDK 17/21 下的兼容性

### Week 3-4：文件变更监听 + 进程通信

- [ ] IDEA 侧：文件保存监听、自动/手动触发逻辑
- [ ] 进程检测：识别当前窗口运行的 Spring Boot JVM
- [ ] 插件 ↔ Agent 通信通道（Socket 协议设计 + 实现）
- [ ] Agent 侧：接收字节码、调用 Instrumentation API

### Week 5-7：核心热更新逻辑

- [ ] 方法体修改热更新（redefineClasses）
- [ ] 新增/删除方法（ASM 字节码重构 + 类替换）
- [ ] 新增/删除字段（同上）
- [ ] 新增/删除类（通过 ClassLoader defineClass）
- [ ] 变更类编译（调用 IDEA 编译 API）

### Week 8-9：UI + 配置 + 稳定性

- [ ] 工具栏按钮（闪电图标 + 状态动画）
- [ ] 状态栏实时反馈
- [ ] Balloon 失败通知
- [ ] 热更新日志面板（-X 模式）
- [ ] 设置面板（全局 + 项目级配置持久化）
- [ ] 错误边界：Agent 异常不崩溃 JVM，通信超时处理

### Week 10-12：测试 + 文档 + 开源

- [ ] 多模块项目测试（Maven / Gradle）
- [ ] 跨平台测试（Windows / macOS / Linux）
- [ ] JDK 版本矩阵测试（8 / 11 / 17 / 21）
- [ ] GitHub 仓库初始化 + CI（GitHub Actions 多平台构建）
- [ ] README + CONTRIBUTING + 使用文档
- [ ] 开源发布（JetBrains Marketplace 或 GitHub Release）

### Phase 2：远程热更新（后续规划，3 个月以后）

- [ ] 远程 JVM 进程发现与连接
- [ ] 本地编译类文件同步到远程
- [ ] 远程 Agent 通信协议（SSH 隧道 / TLS）
- [ ] 远程失败处理

---

## 9. 界面与交互设计

### 9.1 工具栏按钮

- 在 IDEA 主工具栏增加 **Hot Update** 按钮（闪电图标）
  - 正常状态：灰色闪电（无可更新变更或未检测到进程）
  - 可点击：蓝色闪电（有变更待更新）
  - 更新中：旋转动画
  - 成功：绿色对勾（2 秒后恢复）
  - 失败：红色叉号（点击打开 Balloon）

### 9.2 设置面板

**路径**：`Settings | Tools | Hot Update`

```
[ ] Enable hot update for this project

Trigger mode:
  ( ) Auto (on file save)
  ( ) Manual (toolbar button / shortcut)

Auto mode options:
  Debounce delay: [ 300 ] ms

Advanced:
  [ ] Enable debug logging (-X)
  Agent communication timeout: [ 5000 ] ms

Agent info:
  Version: 1.0.0
  Path: /Users/xxx/Library/Application Support/JetBrains/.../hot-update-agent.jar
```

### 9.3 日志面板

**路径**：`View | Tool Windows | Hot Update`

- 表格列：Time | Class Name | Operation | Status | Message
- Operation 值：MethodBody / AddMethod / DeleteMethod / AddField / DeleteField / AddClass / DeleteClass
- Status 值：Success（绿色）/ Failed（红色）/ Skipped（灰色）
- 底部提供 **Clear** 和 **Export** 按钮

---

## 10. 术语表

| 术语 | 解释 |
|---|---|
| **HotSwap** | JVM 标准的类热替换机制，仅支持方法体修改，通过 JDWP 协议触发 |
| **Instrumentation** | JVM 提供的 API，允许在运行时修改已加载类的字节码 |
| **Java Agent** | 通过 `-javaagent` 参数在 JVM 启动时加载的 jar，可注册 `ClassFileTransformer` |
| **redefineClasses** | Instrumentation API 方法，用于替换已加载类的字节码，限制较多 |
| **ClassLoader.defineClass()** | ClassLoader 的 protected 方法，用于动态定义新类 |
| **ASM** | 轻量级 Java 字节码操作和分析框架 |
| **Javassist** | 另一个字节码操作库，API 更接近 Java 源码，易于使用 |
| **LaunchedURLClassLoader** | Spring Boot 自定义的 ClassLoader，用于加载嵌套 jar 中的类 |

---

## 11. 风险与假设

### 假设

- 用户已安装并启用 IntelliJ IDEA 官方 Java 插件（提供编译能力）
- 用户的 Spring Boot 项目可通过 IDEA 的 Run/Debug Configuration 正常启动
- 热更新的目标 JVM 与 IDEA 运行在同一用户权限下（本地场景）
- 用户接受"不支持方法签名变更、注解刷新、继承关系修改"的限制

### 风险

| 风险 | 影响 | 缓解措施 |
|---|---|---|
| Agent jar 被 macOS Gatekeeper / Windows Defender 拦截 | 高 | 提供手动加载指引；文档说明如何添加信任 |
| JDK 版本升级导致 Instrumentation 行为变化 | 中 | CI 矩阵覆盖 8/11/17/21；PoC 阶段充分验证 |
| Spring Boot 的 LaunchedURLClassLoader 行为变化 | 中 | 支持 2.x 和 3.x；测试用例覆盖 |
| 类加载器隔离导致新增类无法被正确加载 | 中 | Agent 需精确识别目标 ClassLoader，测试多模块场景 |
| Agent 内存泄漏（未正确清理类引用） | 中 | 单元测试 + 长时间运行压测；Metaspace 监控 |
| 用户期望过高（以为能替代 JRebel） | 高 | README 和文档中明确能力边界，不夸大宣传 |
