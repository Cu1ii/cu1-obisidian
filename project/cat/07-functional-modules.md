# 07 - 功能模块与依赖关系（重构视角）

按 **职责** 切分，非 Maven 包。每块都是重构时可独立替换/重写的单元。

## 模块全景图

```
                    ┌─────────────────────────────────────┐
                    │         M0 基础设施 (Infra)          │
                    │  IoC + MVC + DAL + Codec + Logging   │
                    └─────────────────────────────────────┘
                                     ↑ 全模块依赖
        ┌────────────┬───────────────┼────────────────┬────────────┐
        │            │               │                │            │
   ┌─────────┐  ┌────────┐      ┌─────────┐      ┌──────────┐ ┌────────┐
   │M1 接收   │  │M2 配置  │      │M3 消费   │←──── │M4 存储    │ │M5 集群  │
   │Ingest   │  │Config  │      │Consume  │      │Storage   │ │Cluster │
   └─────────┘  └────────┘      └─────────┘      └──────────┘ └────────┘
                     ↑               ↓                ↑           ↓
                     │          ┌─────────┐      ┌──────────┐    │
                     │          │M6 离线任务│─────→│ M4       │    │
                     │          │OfflineJob│      └──────────┘    │
                     │          └─────────┘            ↑          │
                     │               ↓                 │          │
                     │          ┌─────────┐            │          │
                     │          │M7 报表查询│────────────┘          │
                     │          │Query    │←───────────────────────┘
                     │          └─────────┘
                     │               ↓
                     │          ┌─────────┐
                     └──────────│M8 告警   │
                                │Alarm    │
                                └─────────┘
                                     ↓
                    ┌────────────┬───────────────┬─────────────┐
              ┌─────────┐  ┌─────────┐    ┌──────────┐  ┌──────────┐
              │M9 业务采集│  │M10 管理 │    │M11 认证   │  │M12 Web UI │
              │Ingest API│  │Admin   │    │Auth      │  │Frontend  │
              └─────────┘  └─────────┘    └──────────┘  └──────────┘
```

---

## M0 — 基础设施（Infra）

**作用**：跨模块共享的底层能力。重构后由 Spring Boot 提供，绝大部分可丢。

**当前实现**：
- IoC：Plexus + Unidal lookup（`@Named` `@Inject`）
- MVC：unidal `web-framework`（`@ModuleMeta` + `Handler` 双向 inbound/outbound）
- ORM：DAL-JDBC（XML codegen）
- 配置 codegen：unidal `codegen-maven-plugin`（XML schema → Java entity + visitor + parser）
- 编解码：自研 `MessageCodec`（PlainText/Native/Html/Waterfall）
- 集群协调：`TimerSyncTask` 定时拉 DB 同步配置
- 日志：log4j 1.2 + plexus-logging

**重构后**：
- IoC → Spring `@Component`/`@Service`
- MVC → Spring `@RestController`
- ORM → JPA / MyBatis-Plus
- 配置 codegen → 保留（迁 model 类成本太高）或一次性手写 POJO
- **编解码必须保留**（客户端协议契约）
- 日志 → SLF4J + Logback

**依赖**：无。被所有模块依赖。

---

## M1 — 消息接收（Ingest TCP）

**作用**：Netty 服务端，接收所有客户端 TCP 上报。

**当前实现**：`cat-core/com.dianping.cat.analysis`
- `TcpSocketReceiver`：Netty 2280 端口，Boss/Worker EventLoop
- `MessageDecoder`：长度前缀 + binary 解码 → `MessageTree`
- `MessageHandler`/`DefaultMessageHandler`：分发到 M3
- `ServerStatisticManager`：自身埋点（处理量、丢失数）

**重构后**：单独 modulith module。Netty 逻辑可零修改平移。Bean 注入改 Spring。

**依赖**：M0（编解码）→ 输出到 M3。

**对外契约**：TCP 协议（**冻结**，向后兼容客户端）。

---

## M2 — 配置中心（Config）

**作用**：服务端运行配置 + 业务配置 + 告警规则配置 + 路由配置统一入口。最杂的一块。

**当前实现**：散落多处，按生效域分四类。

### M2a 服务端运行配置
`cat-core/com.dianping.cat.config.server`
- `ServerConfigManager`：从 `/data/appdatas/cat/server.xml` + DB 加载
- 决定本机是否 `isJobMachine` / `isAlertMachine` / `isLocalMode` / `hdfs-enabled`
- `ServerFilterConfigManager`：丢弃域过滤

### M2b Domain / 项目元数据
- `cat-home/system/page/project`：Project DAO（CRUD `project` 表）
- `cat-core/service/ProjectService`：缓存 + IP/Hostname 反查
- `DomainGroupConfigManager`：业务域分组

### M2c 告警规则配置（M8 用）
`cat-home/com.dianping.cat.report.alert/*/XxxRuleConfigManager`：
- `TransactionRuleConfigManager`、`EventRuleConfigManager`、`HeartbeatRuleConfigManager`、`ExceptionRuleConfigManager`、`BusinessRuleConfigManager`
- 全部继承 `BaseRuleConfigManager`（`alert/spi/config`）
- 存储：`config` 表 + 内存缓存 + `TimerSyncTask` 定时刷新

### M2d 客户端路由配置
`cat-home/system/page/router/config/RouterConfigManager`
- 决定客户端上报到哪台服务器
- `RouterConfigBuilder`：根据 state 报表自动调整路由

### M2e 各类业务配置
- `BusinessConfigManager`、`SampleConfigManager`、`ReportReloadConfigManager`
- `TopologyGraphConfigManager`、`StorageGroupConfigManager`、`BaselineConfigManager`
- `UserConfigManager`、`ResourceConfigManager`（M11 用）

**重构后**：建议统一一个 `config` modulith：
- 一张通用 `config` 表（K-V，按类型分）
- 暴露 `ConfigService<T>` 泛型接口
- 内存缓存 + DB 持久化 + Spring 事件通知（替代 TimerSyncTask）
- 告警规则单独子域，因为 schema 复杂

**依赖**：M0、M4（DB DAO）→ 被 M3、M7、M8、M10 使用。

---

## M3 — 实时消费（Consume）

**作用**：MessageTree 入内存，按业务维度（事务/事件/链路 …）实时统计。

**当前实现**：`cat-core/analysis` + `cat-consumer/consumer/*`
- `RealtimeConsumer`：单例消费总入口
- `PeriodManager` + `Period`：按小时滚动窗口
- `MessageAnalyzerManager`：按 ID 索引 Analyzer
- 12 个 `XxxAnalyzer`（Transaction/Event/Heartbeat/Problem/Cross/Dependency/State/Storage/Matrix/Top/Dump/Business）
  - 每个 Analyzer 一个内存 Report 模型
  - 独立工作线程 + 队列（`DefaultMessageQueue`）

**子模块特殊点**：
- `DumpAnalyzer`：不做统计，落 logview 链路 → 走 M4 块存储
- `TopAnalyzer`：跨域错误大盘
- `MatrixAnalyzer`：性能矩阵
- `BusinessAnalyzer`：消费 Metric 类消息

**重构后**：每个 Analyzer 一个 modulith module（按现有边界切分天然合理）。
- 用 Spring `ApplicationEventPublisher` 替代 `Period.distribute()` 直接调用
- 或者保留直接调用，因性能敏感

**依赖**：M1（输入 MessageTree）、M2（采样/过滤配置）→ 输出周期 Report 给 M4 持久化。

---

## M4 — 存储（Storage）

**作用**：报表二进制 + LogView 块 + 配置数据 持久化。

**当前实现**：三套并存。

### M4a MySQL（结构化）
`cat-core/META-INF/dal/jdbc/*.xml` + 生成 DAO
- 报表表：`hourly_report` / `daily_report` / `weekly_report` / `monthly_report` + 各自 `_content`（binary）
- 元数据：`project`、`config`、`task`、`report_task`、`alteration`、`alert`、`alert_summary`、`topology_graph`、`dailygraph`、`command`、`metric_screen`

### M4b 本地块存储（LogView）
`cat-core/message/storage` + `cat-hadoop/.../local`
- `LocalMessageBucket`：每域+每小时一个文件
- `MessageBlockReader/Writer`：snappy 压缩，定长块
- 写入方：`DumpAnalyzer`
- 读取方：`/r/m?op=view`

### M4c HDFS（可选冷存）
`cat-hadoop/.../hdfs`
- `HdfsBucket` / `HdfsBucketManager`
- 远程冷备 logview

**重构后**：
- M4a → JPA / MyBatis-Plus，schema 不变
- M4b → 抽 `LogviewStorageService` 接口（implementations: local / hdfs / s3）
- M4c → 升级到现代对象存储更合适（S3/OSS/HDFS3）

**依赖**：M0 → 被 M3（写）、M6（聚合写）、M7（读）使用。

---

## M5 — 集群协调（Cluster）

**作用**：CAT 多实例间互拉数据 + 路由调度。

**当前实现**：`cat-core/report/server`
- `RemoteServersManager`：维护对端实例列表
- `ServersUpdater` / `ServersUpdaterManager`：定时同步
- `BaseRemoteModelService`：通过 `/r/model?xml=true&...` 跨实例拉报表
- `RouterConfigBuilder` (M2d)：根据 state 报表生成客户端路由表

**关键流程**：
- 每个采集机只持有自己接收到的客户端数据
- 用户查询时：`CompositeModelService` 同时拉本地 + 所有远端，合并后返回
- 客户端路由：根据负载 + 健康度自动分流

**重构后**：
- 跨实例查询改 gRPC 或保留 HTTP
- 路由能力可考虑外部化（K8s service mesh / Nacos）
- 这块是 CAT 自治的关键，**不可省略**

**依赖**：M0、M2、M7（报表查询接口）→ 被 M7 用于聚合查询。

---

## M6 — 离线任务（Offline Job）

**作用**：聚合小时报表为日 / 周 / 月报，重建报表，CMDB 同步等。

**当前实现**：`cat-home/report/task`
- `DefaultTaskConsumer`：扫 `task` 表，分发任务
- `TaskBuilder` 接口：每个 Analyzer 一个实现（`build/report/*ComponentConfigurator` 注册）
  - `buildHourlyTask` / `buildDailyTask` / `buildWeeklyTask` / `buildMonthlyTask`
- `ReportFacade`：构建报表内容
- 子目录：
  - `current/`：当前小时报表重建（CurrentReportBuilder）
  - `cmdb/`：CMDB 项目信息同步
  - `reload/`：报表重新加载（`ReportReloadTask`）

**触发方式**：周期切换时插入 `task` 表 → JobMachine 抢占执行

**重构后**：用 Spring `@Scheduled` 或独立 modulith。task 表保留作为分布式锁。建议：
- 引入 Quartz / XXL-Job 替代手写 `DefaultTaskConsumer`
- 否则用 ShedLock 保证多实例下只跑一份

**依赖**：M0、M2、M3（拉历史 Report）、M4（写聚合结果）。只在 `isJobMachine=true` 实例运行。

---

## M7 — 报表查询（Query）

**作用**：所有 `/r/{xxx}` 报表页面背后的取数 + 计算 + 渲染逻辑。

**当前实现**：`cat-home/report/page/*` + `cat-core/report/service`
- 每个 Analyzer 对应一组 4 类 Service：
  - `LocalXxxService`：当前小时实时（**直接读 M3 内存模型**）
  - `RemoteXxxService`：从其他实例 HTTP 拉
  - `HistoricalXxxService`：从 MySQL 读 binary
  - `CompositeXxxService`：组合上述三者
- 请求模型：`ModelRequest` / `ModelResponse<T>`
- 视图：`Handler` → `JspViewer`（HTML） / `XmlViewer`（跨实例互拉用）

**关键继承**：
```
ModelService<T>
├── LocalModelService<T>          (cat-core)
├── BaseRemoteModelService<T>     (cat-core)
├── BaseHistoricalModelService<T> (cat-core)
└── BaseCompositeModelService<T>  (cat-core)
   └── CompositeXxxService        (cat-home，每个 Analyzer)
```

**重构后**：
- `ModelService<T>` 抽象保留（接口好用）
- 每个 Analyzer 一个 modulith module 暴露 REST controller
- `XmlViewer` 改 JSON（跨实例拉数也用 JSON）
- 大对象传输考虑 Protobuf

**依赖**：M0、M3（实时数据）、M4（历史数据）、M5（远端聚合）。

---

## M8 — 告警（Alarm）

**作用**：定时扫描报表 + 规则匹配 + 多渠道通知。

**当前实现**：两层（SPI + 业务实现）

### M8a SPI 层
`cat-alarm/com.dianping.cat.alarm.spi`：
- `AlertManager`：发送总入口
- `AlertEntity`：告警事件载体
- `AlertChannel`：渠道枚举（MAIL/SMS/WX/DX）
- `AlertType`：类型枚举（Business/Exception/Heartbeat/Transaction/Event）
- `sender/`：`MailSender` / `SmsSender` / `WeixinSender` / `Sender` 抽象 + `SenderManager`
- `decorator/`：消息模板渲染（FreeMarker），按规则定制邮件正文
- `spliter/`：长消息切分（短信/微信有长度限制）
- `receiver/Contactor`：联系人解析（Project 联系人/默认联系人）
- `rule/DataChecker`：通用阈值规则引擎

### M8b 业务告警
`cat-home/com.dianping.cat.report.alert`：
- `AlarmManager`：启动 5 个告警线程
- `XxxAlert`（Business/Exception/Heartbeat/Transaction/Event）：周期扫描对应 Report → DataChecker → 触发 AlertManager.send()
- `XxxRuleConfigManager`：配置（已归 M2c）
- `XxxDecorator`、`XxxContactor`：渠道定制

**重构后**：
- M8a 保留为公共 SPI（一个 modulith）
- M8b 每个告警类型一个子模块，依赖 M2c 配置 + M7 查报表 + M8a 发送
- 渠道扩展（钉钉/Lark/企微/Webhook）走插件化
- 只在 `isAlertMachine=true` 实例运行

**依赖**：M0、M2c（规则）、M7（取报表）→ 输出邮件/短信/IM。

---

## M9 — 业务数据采集 API（Ingest API）

**作用**：HTTP 端点接收非 TCP 的数据流（外部系统主动推送）。

**当前实现**：`cat-home/report/page/*`，纯 HTTP 入口，不渲染页面。
- `/r/monitor` (`MonitorAnalyzer`)：业务指标 count/avg/sum/batch
- `/r/alert?op=insert`：外部告警接入（Zabbix 等）
- `/r/alert?op=alert`：直接发告警（绕过规则）
- `/r/alteration?op=insert`：变更事件
- `/r/app`、`/r/web`、`/r/browser`、`/r/crash`、`/r/applog`、`/r/appstats`：移动 + Web 端监控数据

**重构后**：
- 单独 modulith，路径迁到 `/api/v1/ingest/{type}`
- 老路径加 nginx 重写兼容旧接入
- 这块**最容易迁**，先做，验证 Vue/SpringBoot 链路

**依赖**：M0、M4（部分直接写 DB），不依赖 M3 内存模型。

---

## M10 — 管理后台（Admin）

**作用**：所有 `/s/*` 配置类页面。

**当前实现**：`cat-home/system/page/*`
- `config/`（52 个 op）：项目 / 拓扑 / 各类规则 / 路由 / 采样 / 服务器 / 报表重载
- `project/`：项目 CRUD
- `business/`：业务标签
- `plugin/`：插件文档查看
- `router/`：路由配置可视化
- `permission/`：用户/资源（归 M11）
- `login/`：登录（归 M11）

**重构后**：
- 全部改 RESTful CRUD，按主题拆资源（projects、rules、topology、router 等）
- Vue 写表单，复用 ant-design / element-plus 后台模板
- 每个主题一个 modulith 子模块，复用 M2 的 ConfigService

**依赖**：M0、M2（背后是各 ConfigManager）、M11（鉴权）。

---

## M11 — 认证授权（Auth）

**作用**：登录 + 权限校验。

**当前实现**：散在 `cat-home/system/page/login` + `permission` + Filter
- `PermissionFilter`（web.xml）：URL 拦截，未登录跳 `/s/login`
- `UserConfigManager`：用户 XML 配置（不是 DB!）
- `ResourceConfigManager`：URL → 角色映射 XML
- 登录态存 Session

**重构后**：
- 改 Spring Security + JWT
- 用户表入 DB
- 角色 / 资源走 RBAC 模型
- 这块**整个推倒重写**最干净

**依赖**：M0、M2（用户/资源配置）、M4。

---

## M12 — Web 前端（Frontend）

**作用**：浏览器渲染 + 交互。

**当前实现**：JSP + JSTL + jQuery + Bootstrap 2/3 + flot/jqGrid/SVG
- 渲染：`JspViewer` 转发到 `/jsp/report/*` 或 `/jsp/system/*`
- 静态资源：`webapp/assets`（AdminLTE）+ `webapp/js`、`webapp/css`、`webapp/images`
- 图表：服务端 `cat-home/report/graph` 生成 SVG（!）

**重构后**：
- Vue 3 + TypeScript + Vite + Pinia + vue-router 全新工程
- 图表 → ECharts / antv（**前端绘制**，废弃服务端 SVG）
- UI 库选 element-plus / ant-design-vue
- 与后端通过 REST + WebSocket（实时刷新报表）

**依赖**：M9 + M10 + M7 的 REST 接口（不再依赖后端 view 层）。

---

## 依赖关系矩阵

| 模块 \\ 依赖 | M0 | M1 | M2 | M3 | M4 | M5 | M6 | M7 | M8 | M9 | M10 | M11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **M0 Infra** | - | | | | | | | | | | | |
| **M1 Ingest TCP** | ✓ | - | | | | | | | | | | |
| **M2 Config** | ✓ | | - | | ✓ | | | | | | | |
| **M3 Consume** | ✓ | ✓ | ✓ | - | | | | | | | | |
| **M4 Storage** | ✓ | | | | - | | | | | | | |
| **M5 Cluster** | ✓ | | ✓ | | | - | | | | | | |
| **M6 Offline Job** | ✓ | | ✓ | ✓ | ✓ | | - | | | | | |
| **M7 Query** | ✓ | | ✓ | ✓ | ✓ | ✓ | | - | | | | |
| **M8 Alarm** | ✓ | | ✓ | | ✓ | | | ✓ | - | | | |
| **M9 Ingest API** | ✓ | | ✓ | | ✓ | | | | | - | | |
| **M10 Admin** | ✓ | | ✓ | | ✓ | | | | | | - | ✓ |
| **M11 Auth** | ✓ | | ✓ | | ✓ | | | | | | | - |
| **M12 Frontend** | (only REST) | | | | | | | ✓ | | ✓ | ✓ | ✓ |

---

## 重构推荐拆分（modulith 落地）

```
spring-modulith roots:
├── infra              ← M0
├── ingest-tcp         ← M1
├── config             ← M2 (含 a/b/d/e；c 单独)
├── alert-rules        ← M2c (规则配置 schema 复杂，独立)
├── consumer-core      ← M3 共享部分（Period/AnalyzerManager）
│   ├── transaction    ← M3 子（一个 Analyzer 一个 module）
│   ├── event
│   ├── heartbeat
│   ├── problem
│   ├── cross
│   ├── dependency
│   ├── state
│   ├── storage
│   ├── matrix
│   ├── top
│   └── business
├── logview            ← DumpAnalyzer + M4b
├── storage            ← M4a (DB DAO 层)
├── cluster            ← M5
├── offline-job        ← M6
├── query              ← M7 公共 ModelService
├── alarm-spi          ← M8a
├── alarm              ← M8b
├── ingest-api         ← M9
├── admin              ← M10 后台 REST
├── auth               ← M11
└── api-gateway        ← REST 总聚合 (controller 集中地)

separate repo:
└── cat-web            ← M12 Vue
```

## 重构推进顺序（基于依赖）

依赖少的先动：

1. **M0 + M11 + M9**（Spring Boot 骨架 + Auth + Ingest API）
   先把 Spring 容器立起来。Ingest API 是无状态的 REST，验证链路。Auth 重写最干净。

2. **M4 + M2**（存储 + 配置）
   ORM 切换，配置表统一。后续模块都依赖。

3. **M1 + M3**（TCP 接收 + Analyzer）
   Netty 平移，Analyzer 改 Spring bean。**协议不动**。

4. **M5 + M6 + M8a**（集群 + 离线任务 + 告警 SPI）
   后台无 UI 的部分，改完不影响用户感知。

5. **M7 + M8b + M10**（查询 + 告警业务 + 管理）
   全改 REST。这一步起 Vue 前端。

6. **M12** 跟着 5 一起做（边出 REST 边写页面）。

## 灰度策略

- 新老共存：旧 cat-home 继续运行，新 Spring Boot 跑 9090，nginx 按路径分流
- M9（采集 API）最先迁完，因为外部依赖少
- M3 双写阶段：老 Plexus 集群跑数据，新集群只接镜像流量
- 报表数据库共享（同一份 MySQL），保证查询切流期间数据一致
- 最后切流量、下线老进程
