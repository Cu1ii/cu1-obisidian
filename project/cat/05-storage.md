# 05 - 存储层

## MySQL（cat 库）

主表（DAL-JDBC schema 定义在 `cat-core/src/main/resources/META-INF/dal/jdbc/`）：

| 表 | 用途 |
|---|---|
| `project` | 业务域配置 |
| `hourly_report` + `hourly_report_content` | 小时报表索引 + 二进制内容 |
| `daily_report` + `daily_report_content` | 日报 |
| `weekly_report` + `weekly_report_content` | 周报 |
| `monthly_report` + `monthly_report_content` | 月报 |
| `topology_graph` | 拓扑图节点 |
| `dailygraph` | 日级图 |
| `task` | 离线 task 调度 |
| `report_task` | task 状态 |
| `alteration` | 变更记录 |
| `alert` | 告警事件流水 |
| `alert_summary` | 告警汇总 |
| `command` | 命令（App 端） |
| `metric_screen` | 指标大盘配置 |

报表二进制：
- `*_content` 表的 `content` 字段是 `DefaultNativeParser.parse()` 可还原的字节流
- 编码由 `cat-consumer` 的各 model `transform/DefaultNativeBuilder/Parser` 生成

DDL 入口：`script/CatApplication.sql`（一个文件，全量建表）

## DAL-JDBC

- 定义：`META-INF/dal/jdbc/*.xml`（codegen 输入）
- 生成：`com.dianping.cat.core.dal.*Dao` / `*Entity` / `*` POJO
- 调用方：`AbstractReportService` 子类（如 `TransactionReportService`）

```java
@Inject HourlyReportDao m_hourlyReportDao;
@Inject HourlyReportContentDao m_hourlyReportContentDao;

m_hourlyReportDao.findAllByDomainNamePeriod(...)
m_hourlyReportContentDao.findByPK(id, period, READSET_CONTENT)
```

## 本地块存储（LogView）

`cat-core/com.dianping.cat.message.storage`：

- `LocalMessageBucket`：每域 / 每小时一个文件
- `MessageBlock`：固定大小压缩块（snappy）
- `MessageBlockReader/Writer`：随机读写
- 写入：`DumpAnalyzer` 消费链路 → 累积 → 周期切换时刷盘
- 路径：`server-config` 中 `local-base-dir`（默认 `/data/appdatas/cat/bucket/`）

## HDFS（可选）

`cat-hadoop/org.unidal.cat.message.storage.hdfs`：
- `HdfsBucket` / `HdfsBucketManager`
- 配置在 `server.xml`，`hdfs-base-dir`
- 一般做异地冷存，可关

## 配置文件

`cat-home/src/main/resources/config/`：

| 文件 | 用途 |
|---|---|
| `business-report-config.xml` | 业务报表大盘 |
| `business-tag-config.xml` | 业务 tag |
| `businessRuleConfig.xml` | 业务告警规则 |
| `databaseRuleConfig.xml` | DB 监控规则 |
| `domainGroup.xml` | 域分组 |
| `eventRule.xml` | 事件告警规则 |
| `exceptionRuleConfig.xml` | 异常告警规则 |
| `heartbeat-display-policy.xml` | 心跳展示策略 |
| `heartbeatRuleConfig.xml` | 心跳告警规则 |
| `resource-config.xml` | 权限资源 |
| `routerConfig.xml` | 客户端路由 |
| `server-metric-config.xml` | 服务器指标 |
| `storageCacheRule.xml`、`storageRPCRule.xml`、`storageSQLRule.xml` | 存储类告警规则 |
| `storageGroup.xml` | 存储分组 |
| `topoGraphFormat.xml`、`topologyConfig.xml` | 拓扑图 |
| `transactionRule.xml` | 事务告警规则 |
| `user-config.xml` | 用户/权限 |

> 这些是默认值，运行时由对应 ConfigManager 加载并合并 DB 中存的配置版本。重构时：默认配置可保留 XML 形式或迁到 Spring 的 `@ConfigurationProperties` / DB。

## CAT 自身配置

- 服务端配置：`server.xml`（`local-mode`、`hdfs-enabled`、`storage`、`alarm-machines` 等）
- 路径优先级：`/data/appdatas/cat/server.xml` → 类路径
- 客户端：`/data/appdatas/cat/client.xml`

## 报表运算时序

```
T 实时:
  Client → TCP → Analyzer 累积内存模型

T+1h (周期切换):
  Period.finish() → 各 Analyzer.doCheckpoint(true)
  → XxxDelegate.makeReport() → DefaultNativeBuilder.build()
  → bytes → INSERT hourly_report + hourly_report_content

T+1day:
  TaskConsumer → TaskBuilder → 聚合 24 个 hourly → daily_report
  → 同样 binary 入库

周/月类似（TaskBuilder.WEEK / MONTH）
```

## 重构时的存储考量

- **报表 binary 是历史包袱**：自定义二进制 + codegen 模型，跨语言代价高。Vue 前端无法直接消费，须先在后端解码为 JSON。
- **MySQL schema 完全可保留**：表结构稳定，迁到 JPA/MyBatis-Plus 无难度。
- **本地块存储**：协议自洽，重构期可包一层 REST 出口（GET /api/logview/{messageId}）即可。
- **配置 XML**：迁到 Spring `@ConfigurationProperties` 或独立 config 模块。
