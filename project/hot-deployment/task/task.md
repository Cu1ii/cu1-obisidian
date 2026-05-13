# Spring Boot 热更新 IDEA 插件 — 原子任务列表

> 由 `plan/plan.md` 拆分而来，遵循每个任务只改一个文件、测试先行原则。
> 规则：奇数任务写测试，偶数任务写实现。
> **UT 技术栈：Spock 2.x（Groovy 4），基于 JUnit Platform。**

---

## 执行跟踪

> 执行规则：每完成一个 task，必须更新本清单并勾选对应待办；完成后通知用户，等待用户批准后再执行下一个 task。
> Git 规则：只允许在当前项目仓库 `/Users/fyj/Documents/project/jvav/hot-deployment` 内提交代码；外部计划/任务文档只更新内容，不执行 git 操作。
> 验证规则：每个实现任务完成后执行 `mvn clean install -U`；如出现 error，必须先解释原因与影响。

### 当前进度

- 当前停在：`T33` 之前，等待用户批准后再继续。
- 最近完成提交：`8ea6f0c Add compiler integration task spec`
- 最近验证：`mvn clean install -U` 通过，17 个测试通过，0 failures，0 errors，0 skipped。

### 已完成待办

- [x] `T2` 创建根 `pom.xml`，配置 Java 17、多模块聚合、依赖版本管理。
- [x] `T4` 创建 `common/pom.xml`，配置 Java 17 与基础依赖。
- [x] `T6` 创建 `agent/pom.xml`，配置 common/ASM 依赖与 shade agent manifest。
- [x] `T8` 创建 `plugin/pom.xml`，配置 Kotlin、IntelliJ 插件与 Spock 编译。
- [x] `T10` 创建 `HotUpdateAgent.java`，保存 `Instrumentation` 并注册 transformer。
- [x] `T23` 编写 Socket 传输协议 Spock 测试。
- [x] `T24` 创建 `SocketProtocol.java`，实现 4 字节长度头 + UTF-8 JSON 编解码。
- [x] `T25` 编写 Agent Socket Server/端口发现相关 Spock 测试。
- [x] `T26` 创建 `AgentSocketServer.java`，支持本地 socket 服务、PING-PONG 与 redefine 调度。
- [x] `T27` 编写 Plugin Socket Client Spock 测试。
- [x] `T28` 创建 `PluginSocketClient.kt`，支持异步 socket 请求与 PING。
- [x] `T35` 编写端口回传机制 Spock 测试。
- [x] `T36` 创建 `PortDiscovery.java`，写入并读取 Agent 监听端口。
- [x] `T37` 编写 `RedefineDispatcher` Spock 测试。
- [x] `T38` 创建 `RedefineDispatcher.java`，实现方法体 redefine、新增类与删除类分发。
- [x] `T40` 创建 `ClassInjector.java`，支持通过目标 ClassLoader 注入新增类。
- [x] `T47` 编写类删除边界 Spock 测试。
- [x] `T48` 创建 `ClassDeletionHandler.java`，返回不支持热删除类的明确错误。
- [x] 补充 Spock/Surefire 配置，确保 `*Spec` 测试实际执行。
- [x] 补充项目脚手架遗漏文件并提交，保证当前仓库状态干净。
- [x] `T29` 编写 VirtualFileListener Spock Spec：验证 `.java` 文件保存事件被捕获，Auto/Manual 模式行为差异。
- [x] `T30` 创建 `HotUpdateFileListener.kt`：监听 `.java` 保存事件；维护记录队列与 Auto 模式待更新队列。
- [x] `T31` 编写 Compiler 集成 Spock Spec：验证捕获 `.class` 输出路径并忽略非 class 输出。
- [x] `T32` 创建 `HotUpdateCompileTask.kt`：捕获编译输出 `.class` 路径，将变更类加入后续推送队列的数据来源。

### 待执行待办

- [ ] `T33` 编写 Spring Boot 进程检测 Spock Spec。
- [ ] `T34` 创建 `SpringBootProcessDetector.kt`。
- [ ] `T41` 编写变更检测 Diff Spock Spec。
- [ ] `T42` 创建 `ClassChangeDetector.kt`。
- [ ] `T43` 编写 Agent 参数自动注入 Spock Spec。
- [ ] `T44` 创建 `HotUpdateRunConfigurationExtension.kt`。

### 跳过或未按原子顺序完成的任务

- [ ] `T1` 未单独编写 Maven 多模块结构测试。
- [ ] `T3` 未单独编写 common POM 结构测试。
- [ ] `T5` 未单独编写 agent POM 结构测试。
- [ ] `T7` 未单独编写 plugin POM 结构测试。
- [ ] `T9` 未单独编写 Agent premain 测试。
- [ ] `T11`-`T18` PoC 与 Spring Boot sample 任务尚未执行。
- [ ] `T19`-`T22` 原计划 DTO 测试/实现与当前代码包结构不完全一致，后续需要整理或补齐。
- [ ] `T39` 未单独编写 `ClassInjectorSpec`，但 `ClassInjector.java` 已实现。

---

## Phase 1: Foundation & Feasibility PoC（Week 1–2）

| 编号 | 类型 | 任务 | 目标文件 |
|------|------|------|----------|
| T1 | 测试 | 验证 Maven 多模块聚合结构：编写 Spock Spec 检查根 pom 是否正确声明 `common`、`agent`、`plugin` 三个子模块，且依赖版本统一。 | `agent/src/test/groovy/com/github/hotdeploy/agent/it/MavenStructureSpec.groovy` |
| T2 | 实现 | 创建根 `pom.xml`：聚合器配置，统一 `groupId`/`version`，`dependencyManagement` 集中声明 ASM 9.x、Kotlin、Spock 2.x（Groovy 4）版本。 | `pom.xml` |
| T3 | 测试 | 验证 `common` 模块 POM 结构：检查 `packaging=jar`、`source/target=1.8`，且无外部依赖。 | `common/src/test/groovy/com/github/hotdeploy/common/it/PomStructureSpec.groovy` |
| T4 | 实现 | 创建 `common/pom.xml`：最底层模块，零外部依赖，职责为定义 Socket 通信 DTO。 | `common/pom.xml` |
| T5 | 测试 | 验证 `agent` 模块 POM 结构：检查 `maven-shade-plugin` 配置、`Premain-Class` manifest 是否正确。 | `agent/src/test/groovy/com/github/hotdeploy/agent/it/AgentPomStructureSpec.groovy` |
| T6 | 实现 | 创建 `agent/pom.xml`：依赖 `common` + ASM 9.x，配置 `maven-shade-plugin` 打 fat-jar，manifest 包含 `Premain-Class`、`Can-Redefine-Classes`、`Can-Retransform-Classes`。 | `agent/pom.xml` |
| T7 | 测试 | 验证 `plugin` 模块 POM 结构：检查 IntelliJ Platform 插件配置、`ideaVersion=2022.1.1`、`sinceBuild`/`untilBuild`、Kotlin 1.9.x、Spock/Groovy 编译插件。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/it/PluginPomStructureSpec.groovy` |
| T8 | 实现 | 创建 `plugin/pom.xml`：依赖 `common`，配置 `org.jetbrains.intellij` 插件，`source/target=17`，引入 `gmavenplus-plugin` 支持 Groovy/Spock 测试编译。 | `plugin/pom.xml` |
| T9 | 测试 | 编写 Agent premain Spock Spec：验证 `premain` 方法被正确调用，且 `Instrumentation` 实例被非空保存。 | `agent/src/test/groovy/com/github/hotdeploy/agent/HotUpdateAgentSpec.groovy` |
| T10 | 实现 | 创建 `HotUpdateAgent.java`：实现 `premain(String, Instrumentation)`，保存 `Instrumentation` 实例到静态字段；注册一个空的 `ClassFileTransformer`。 | `agent/src/main/java/com/github/hotdeploy/agent/HotUpdateAgent.java` |
| T11 | 测试 | 编写 PoC-A Spock Spec：在 JDK 8/17/21 上分别验证 `Instrumentation.redefineClasses()` 对方法体修改、新增方法、新增字段的行为，记录异常类型。 | `agent/src/test/groovy/com/github/hotdeploy/agent/poc/RedefineBoundarySpec.groovy` |
| T12 | 实现 | 创建 PoC-A 目标类：`PocTargetClass.java`，包含可被修改的方法体、以及用于测试新增方法/字段的占位结构。 | `agent/src/test/java/com/github/hotdeploy/agent/poc/PocTargetClass.java` |
| T13 | 测试 | 编写 PoC-B Spock Spec：验证 `ClassFileTransformer.transform()` 中通过 ASM 为类注入可替换桩子（`MethodContainer` 委托）的可行性，记录启动耗时。 | `agent/src/test/groovy/com/github/hotdeploy/agent/poc/LoadTimeInstrumentationSpec.groovy` |
| T14 | 实现 | 创建 PoC-B ASM 桩子代码：`PocMethodContainer.java` 与 `PocTransformer.java`，实现方法体委托到可替换容器。 | `agent/src/test/java/com/github/hotdeploy/agent/poc/PocTransformer.java` |
| T15 | 测试 | 编写兼容性基线 Spock Spec：验证 Agent 可 attach 到 Spring Boot 3 示例进程，不影响启动时间（启动耗时偏差 < 5%）。 | `agent/src/test/groovy/com/github/hotdeploy/agent/it/AttachCompatibilitySpec.groovy` |
| T16 | 实现 | 创建 `sample/spring-boot-3-sample/pom.xml`：Spring Boot 3.x（JDK 17+）单模块示例工程，用于 attach 兼容性验证。 | `sample/spring-boot-3-sample/pom.xml` |
| T17 | 测试 | 编写 Spring Boot 3 Sample 启动 Spock Spec：验证示例项目能正常启动并暴露一个 HelloController 端点。 | `sample/spring-boot-3-sample/src/test/groovy/com/example/demo/DemoApplicationSpec.groovy` |
| T18 | 实现 | 创建 Spring Boot 3 Sample 主类：`DemoApplication.java`，含一个基本的 `HelloController`。 | `sample/spring-boot-3-sample/src/main/java/com/example/demo/DemoApplication.java` |

**Phase 1 出口标准**：
- `doc/poc-report.md` 明确结论：L1 在所有目标 JDK 可行；L2 实现路径已锁定或降级。

---

## Phase 2: Communication & Process Detection（Week 3–4）

| 编号 | 类型 | 任务 | 目标文件 |
|------|------|------|----------|
| T19 | 测试 | 编写 Socket 协议 DTO Spock Spec：验证 `RedefineRequest` / `RedefineResponse` 的序列化/反序列化、Base64 字节码编码正确。 | `common/src/test/groovy/com/github/hotdeploy/common/protocol/DtoSpec.groovy` |
| T20 | 实现 | 创建 `RedefineRequest.java`：定义 Socket 通信请求 DTO，含 `type`、`payload.classes[]`（`name`、`operation`、`bytes`）。 | `common/src/main/java/com/github/hotdeploy/common/protocol/RedefineRequest.java` |
| T21 | 测试 | 编写 `RedefineResponse` Spock Spec：验证状态码、错误消息、批量类处理结果列表。 | `common/src/test/groovy/com/github/hotdeploy/common/protocol/ResponseSpec.groovy` |
| T22 | 实现 | 创建 `RedefineResponse.java`：定义响应 DTO，含 `type`、`results[]`（`className`、`status`、`message`）。 | `common/src/main/java/com/github/hotdeploy/common/protocol/RedefineResponse.java` |
| T23 | 测试 | 编写 Socket 传输协议 Spock Spec：验证 4 字节大端长度头 + UTF-8 JSON 的编码与解码，边界情况（空包、超长包）。 | `common/src/test/groovy/com/github/hotdeploy/common/protocol/SocketProtocolSpec.groovy` |
| T24 | 实现 | 创建 `SocketProtocol.java`：实现 Length-prefixed JSON 编解码器（`encode`、`decode`）。 | `common/src/main/java/com/github/hotdeploy/common/protocol/SocketProtocol.java` |
| T25 | 测试 | 编写 Agent Socket Server Spock Spec：验证 `ServerSocket` 启动、单连接请求解析、PING-PONG 响应、并发连接处理。 | `agent/src/test/groovy/com/github/hotdeploy/agent/socket/AgentSocketServerSpec.groovy` |
| T26 | 实现 | 创建 `AgentSocketServer.java`：独立线程运行 `ServerSocket`（绑定 `localhost:0`），解析请求，调度到 `RedefineDispatcher`，返回响应。 | `agent/src/main/java/com/github/hotdeploy/agent/socket/AgentSocketServer.java` |
| T27 | 测试 | 编写 Plugin Socket Client Spock Spec：验证连接超时（5000ms）、重试（1 次）、PING-PONG 端到端、线程安全（非阻塞 EDT）。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/socket/PluginSocketClientSpec.groovy` |
| T28 | 实现 | 创建 `PluginSocketClient.kt`：连接 Agent Server，带超时与重试；使用 `ApplicationManager.executeOnPooledThread` 异步发送请求。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/socket/PluginSocketClient.kt` |
| T29 | 测试 | 编写 VirtualFileListener Spock Spec：验证 `.java` 文件保存事件被捕获，Auto/Manual 模式行为差异（Auto 触发队列，Manual 仅记录）。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/listener/FileListenerSpec.groovy` |
| T30 | 实现 | 创建 `HotUpdateFileListener.kt`：注册 `VirtualFileListener`，监听 `.java` 保存事件；维护待更新队列。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/listener/HotUpdateFileListener.kt` |
| T31 | 测试 | 编写 Compiler 集成 Spock Spec：验证调用 `CompilerManager.make()` 后能正确捕获输出 `.class` 文件路径。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/compiler/CompilerIntegrationSpec.groovy` |
| T32 | 实现 | 创建 `HotUpdateCompileTask.kt`：触发增量编译，捕获输出 `.class` 文件路径，将变更类加入推送队列。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/compiler/HotUpdateCompileTask.kt` |
| T33 | 测试 | 编写 Spring Boot 进程检测 Spock Spec：验证 `RunManager` 扫描逻辑：匹配 `SpringBootApplicationConfigurationType`、运行中 `ProcessHandler`、主类名 `*Application`；多匹配时弹出选择。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/process/ProcessDetectorSpec.groovy` |
| T34 | 实现 | 创建 `SpringBootProcessDetector.kt`：扫描运行配置，识别目标 Spring Boot 进程 PID；多进程时弹出 `PopupChooserBuilder`。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/process/SpringBootProcessDetector.kt` |
| T35 | 测试 | 编写端口回传机制 Spock Spec：验证 Agent 启动后端口写入临时文件（或 JVM 参数回传），Plugin 能正确读取。 | `agent/src/test/groovy/com/github/hotdeploy/agent/socket/PortDiscoverySpec.groovy` |
| T36 | 实现 | 创建 `PortDiscovery.java`：Agent 启动时将监听端口写入临时文件；Plugin 读取该文件获取连接地址。 | `agent/src/main/java/com/github/hotdeploy/agent/socket/PortDiscovery.java` |

**Phase 2 出口标准**：
- 示例项目 Run 后，Plugin 状态栏显示 "已连接 Agent (PID: xxxx)"。
- Plugin 与 Agent 能完成 PING-PONG。

---

## Phase 3: Core Hot Update Logic（Week 5–7）

| 编号 | 类型 | 任务 | 目标文件 |
|------|------|------|----------|
| T37 | 测试 | 编写 L1（方法体热更新）Spock Spec：验证 `RedefineDispatcher` 能正确调用 `Instrumentation.redefineClasses(ClassDefinition)`，方法体修改后反射调用返回新结果。 | `agent/src/test/groovy/com/github/hotdeploy/agent/core/RedefineDispatcherSpec.groovy` |
| T38 | 实现 | 创建 `RedefineDispatcher.java`：接收字节码数组，调用 `redefineClasses` 完成 L1 方法体替换；返回每个类的状态。 | `agent/src/main/java/com/github/hotdeploy/agent/core/RedefineDispatcher.java` |
| T39 | 测试 | 编写新增类注入 Spock Spec：验证通过反射获取 `LaunchedURLClassLoader` / `AppClassLoader`，调用 `defineClass()` 注入新类后，类可被正常加载。 | `agent/src/test/groovy/com/github/hotdeploy/agent/core/ClassInjectorSpec.groovy` |
| T40 | 实现 | 创建 `ClassInjector.java`：通过反射获取目标 `ClassLoader`，调用 `defineClass()` 注入新增类；支持 `LaunchedURLClassLoader` 与 `AppClassLoader` 探测。 | `agent/src/main/java/com/github/hotdeploy/agent/core/ClassInjector.java` |
| T41 | 测试 | 编写变更检测 Diff Spock Spec：验证 `ClassChangeDetector` 通过 CRC/最后修改时间识别已变更的类，避免重复推送未变更类。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/diff/ClassChangeDetectorSpec.groovy` |
| T42 | 实现 | 创建 `ClassChangeDetector.kt`：维护 `Map<String, Long>`（类名 → CRC/最后修改时间），过滤未变更类。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/diff/ClassChangeDetector.kt` |
| T43 | 测试 | 编写 Agent 参数自动注入 Spock Spec：验证 `RunConfigurationExtension` 能在 Spring Boot 启动配置中自动追加 `-javaagent:/path/to/agent.jar`。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/run/RunConfigurationExtensionSpec.groovy` |
| T44 | 实现 | 创建 `HotUpdateRunConfigurationExtension.kt`：监听 `RunConfiguration` 启动事件，自动注入 `-javaagent` 参数；支持在 Settings 中关闭。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/run/HotUpdateRunConfigurationExtension.kt` |
| T45 | 测试 | 编写 L2 结构变更 Spock Spec（依赖 PoC-B 结论）：若采用 Load-time Instrumentation，验证新增方法可通过桩子被调用。 | `agent/src/test/groovy/com/github/hotdeploy/agent/core/L2StructureChangeSpec.groovy` |
| T46 | 实现 | 创建 `L2StructureTransformer.java`（若 PoC-B 可行）：首次加载时通过 ASM 注入可替换桩子；热更新时更新调度表使新增方法/字段生效。若不可行，实现为抛出明确不支持异常。 | `agent/src/main/java/com/github/hotdeploy/agent/core/L2StructureTransformer.java` |
| T47 | 测试 | 编写类删除边界 Spock Spec：验证 JVM 不支持卸载类时，Agent 正确返回 "不支持删除，请重启" 提示。 | `agent/src/test/groovy/com/github/hotdeploy/agent/core/ClassDeletionSpec.groovy` |
| T48 | 实现 | 创建 `ClassDeletionHandler.java`：接收删除类请求，返回 "不支持热删除类" 的明确错误响应，不执行任何操作。 | `agent/src/main/java/com/github/hotdeploy/agent/core/ClassDeletionHandler.java` |

**Phase 3 出口标准**：
- 修改 Controller 方法体 → HTTP 请求 1 秒内返回新结果。
- 新增 Service 类 → 可被 Spring 上下文加载（配合刷新或占位符）。

---

## Phase 4: UI, Config & Stability（Week 8–9）

| 编号 | 类型 | 任务 | 目标文件 |
|------|------|------|----------|
| T49 | 测试 | 编写 Toolbar Action 状态流转 Spock Spec：验证灰色（无变更）→ 蓝色（有待推送）→ 旋转（更新中）→ 绿色（成功）→ 红色（失败）的状态切换。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/ui/action/ToolbarActionSpec.groovy` |
| T50 | 实现 | 创建 `HotUpdateAction.kt`：实现 `AnAction`，注册到 `MainToolbar`；根据状态切换图标与提示文本；失败时触发 Balloon。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/ui/action/HotUpdateAction.kt` |
| T51 | 测试 | 编写 StatusBarWidget Spock Spec：验证常驻右下角显示连接状态（Agent 版本 / PID）、最后更新时间、快捷入口点击。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/ui/statusbar/StatusBarWidgetSpec.groovy` |
| T52 | 实现 | 创建 `HotUpdateStatusBarWidget.kt`：实现 `StatusBarWidget`，显示连接状态、PID、最后更新时间；提供快速操作入口。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/ui/statusbar/HotUpdateStatusBarWidget.kt` |
| T53 | 测试 | 编写 Balloon 通知 Spock Spec：验证失败时 `Notifications.Bus.notify()` 被正确触发，标题含摘要，内容含 "View Details" 链接。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/ui/notification/BalloonNotificationSpec.groovy` |
| T54 | 实现 | 创建 `HotUpdateNotifier.kt`：封装 `Notifications.Bus.notify()`，失败时弹出 Balloon，标题为摘要，内容含打开日志面板链接。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/ui/notification/HotUpdateNotifier.kt` |
| T55 | 测试 | 编写 ToolWindow Spock Spec：验证表格列（Time / Class Name / Operation / Status / Message）、Clear 按钮、Export to File 功能。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/ui/toolwindow/ToolWindowSpec.groovy` |
| T56 | 实现 | 创建 `HotUpdateToolWindowFactory.kt`：实现 `ToolWindowFactory`，ID `HotUpdateLog`；表格展示历史记录；底部按钮 Clear / Export。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/ui/toolwindow/HotUpdateToolWindowFactory.kt` |
| T57 | 测试 | 编写 Settings 持久化 Spock Spec：验证 `PersistentStateComponent` 能正确读写项目级 XML（`.idea/hot-update.xml`）与全局级配置。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/config/SettingsPersistenceSpec.groovy` |
| T58 | 实现 | 创建 `HotUpdateSettings.kt`：实现 `PersistentStateComponent`，管理项目级与全局级配置（启用开关、触发模式、Debounce delay、Debug logging、Agent timeout）。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/config/HotUpdateSettings.kt` |
| T59 | 测试 | 编写 Configurable UI Spock Spec：验证设置面板字段与 `HotUpdateSettings` 的双向绑定，修改后即时生效。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/config/ConfigurableSpec.groovy` |
| T60 | 实现 | 创建 `HotUpdateConfigurable.kt`：实现 `Configurable`，路径 `Settings | Tools | Hot Update`；提供 UI 表单绑定到 `HotUpdateSettings`。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/config/HotUpdateConfigurable.kt` |
| T61 | 测试 | 编写 Agent 错误边界 Spock Spec：验证 Socket handler、Instrumentation callback 入口均包 `try-catch`，异常不抛出，记录到 `System.err` 或日志文件。 | `agent/src/test/groovy/com/github/hotdeploy/agent/error/ErrorBoundarySpec.groovy` |
| T62 | 实现 | 创建 `AgentErrorHandler.java`：统一封装 Agent 所有入口的异常捕获，记录到本地日志文件，避免抛出影响目标 JVM。 | `agent/src/main/java/com/github/hotdeploy/agent/error/AgentErrorHandler.java` |
| T63 | 测试 | 编写 Plugin 错误边界 Spock Spec：验证后台任务异常后，UI 状态栏更新为红色；通信超时单独处理不挂起 EDT。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/error/PluginErrorHandlerSpec.groovy` |
| T64 | 实现 | 创建 `PluginErrorHandler.kt`：封装 Plugin 后台任务异常处理，捕获后更新状态栏为红色；通信超时独立处理。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/error/PluginErrorHandler.kt` |

**Phase 4 出口标准**：
- 所有 UI 元素在 macOS / Windows / Linux 渲染正常。
- 错误场景均有明确提示，不阻塞 IDEA 主线程。

---

## Phase 5: Testing, Docs & Release（Week 10–12）

| 编号 | 类型 | 任务 | 目标文件 |
|------|------|------|----------|
| T65 | 测试 | 编写多模块 Sample Spock Spec：验证插件能正确识别子模块中的变更类，编译输出路径正确，只推送变更模块的类。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/it/MultiModuleSampleSpec.groovy` |
| T66 | 实现 | 创建 `sample/spring-boot-2-sample/pom.xml`：Spring Boot 2.x 多模块示例工程，用于验证子模块类推送。 | `sample/spring-boot-2-sample/pom.xml` |
| T67 | 测试 | 编写跨平台路径处理 Spock Spec：验证 Windows 路径分隔符、Agent jar 路径含空格、macOS / Linux 路径兼容性。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/util/PathResolverSpec.groovy` |
| T68 | 实现 | 创建 `PathResolver.kt`：处理不同 OS 的路径分隔符、空格转义、Agent jar 绝对路径解析。 | `plugin/src/main/kotlin/com/github/hotdeploy/plugin/util/PathResolver.kt` |
| T69 | 测试 | 编写 CI workflow 验证 Spock Spec：验证 GitHub Actions YAML 语法正确，`buildPlugin`、Spock 单元测试、打包 artifact 步骤完整。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/ci/CiWorkflowSpec.groovy` |
| T70 | 实现 | 创建 `.github/workflows/ci.yml`：构建 plugin 与 agent jar、运行 Spock 单元测试、打包 artifact、Release 时自动上传。 | `.github/workflows/ci.yml` |
| T71 | 测试 | 编写 `.gitignore` 验证 Spock Spec：确认覆盖 IntelliJ IDEA、Maven、Java/Kotlin/Groovy 标准忽略规则。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/it/GitignoreValidationSpec.groovy` |
| T72 | 实现 | 创建 `.gitignore`：覆盖 `.idea/`、`target/`、`*.iml`、OS 生成文件等标准规则。 | `.gitignore` |
| T73 | 测试 | 编写 README 结构验证 Spock Spec：检查关键章节（安装、使用、能力边界、FAQ）存在，且明确列出 L1/L2 支持范围。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/docs/ReadmeStructureSpec.groovy` |
| T74 | 实现 | 创建 `README.md`：功能介绍、安装步骤（Marketplace / 本地安装）、使用方法、能力边界表格、FAQ。 | `README.md` |
| T75 | 测试 | 编写 CONTRIBUTING 结构验证 Spock Spec：检查环境搭建、Agent 调试（attach/premain）、IDEA 插件调试章节完整。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/docs/ContributingStructureSpec.groovy` |
| T76 | 实现 | 创建 `CONTRIBUTING.md`：环境搭建、Agent 调试指南、IDEA 插件调试方式（Maven / 直接运行）。 | `CONTRIBUTING.md` |
| T77 | 测试 | 编写 ARCHITECTURE 结构验证 Spock Spec：检查 plan.md 中的 4 个 Mermaid 图表（系统架构图、热更新时序图、类替换决策流程图、Agent 启动流程）在 ARCHITECTURE.md 中均有对应章节。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/docs/ArchitectureStructureSpec.groovy` |
| T78 | 实现 | 创建 `ARCHITECTURE.md`：完整包含 plan.md 中的 4 个 Mermaid 图表（系统架构图、热更新通信时序图、类替换决策流程图、Agent 启动与挂载流程），并补充协议格式说明与模块依赖关系。 | `ARCHITECTURE.md` |
| T79 | 测试 | 编写 Marketplace 发布配置验证 Spock Spec：验证插件 zip 结构正确、`plugin.xml` 元数据完整、版本兼容性声明正确。 | `plugin/src/test/groovy/com/github/hotdeploy/plugin/release/MarketplaceConfigSpec.groovy` |
| T80 | 实现 | 创建 Marketplace 发布配置与脚本：准备插件描述、截图路径、`plugin.xml` 最终版本号与兼容性声明（2022.1+）。 | `plugin/src/main/resources/META-INF/plugin.xml`（最终发布版） |

**Phase 5 出口标准**：
- CI 全绿（build + Spock test）。
- 至少在一个干净环境（无源码、仅 Marketplace 安装）中按 README 步骤可完成完整热更新。

---

## 附录：任务统计

| Phase | 任务数 | 测试任务（奇数） | 实现任务（偶数） |
|-------|--------|------------------|------------------|
| Phase 1 | T1–T18 | 9 | 9 |
| Phase 2 | T19–T36 | 9 | 9 |
| Phase 3 | T37–T48 | 6 | 6 |
| Phase 4 | T49–T64 | 8 | 8 |
| Phase 5 | T65–T80 | 8 | 8 |
| **总计** | **80** | **40** | **40** |

---

## 附录：关键依赖关系（执行顺序）

```
T2(根pom) → T4(common/pom) → T6(agent/pom) → T8(plugin/pom)
  ↓              ↓                ↓
T10(Agent主类) ← T12(PoC目标类) ← T14(PoC桩子)
  ↓
T20~24(Common DTO/协议) → T26(Agent Server) ↔ T28(Plugin Client)
  ↓
T30(文件监听) → T32(编译触发) → T34(进程检测) → T36(端口发现)
  ↓
T38(Redefine L1) ↔ T40(类注入) ↔ T42(变更检测) ↔ T44(自动注入Agent)
  ↓
T50(Toolbar) → T52(状态栏) → T54(Balloon) → T56(ToolWindow)
  ↓
T58(设置持久化) → T60(设置面板) → T62(Agent错误) → T64(Plugin错误)
  ↓
T66~80(文档/发布)
```

> 说明：表格内编号连续，同一 Phase 内建议按编号顺序执行；跨 Phase 时，需等待前一 Phase 出口标准通过后再进入下一阶段（尤其是 Phase 1 PoC 结论会影响 Phase 3 L2 实现）。
