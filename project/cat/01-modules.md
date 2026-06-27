# 01 - 模块结构

CAT 顶层 Maven 模块（`pom.xml` 中 `<modules>`）：

| 模块             | 职责                                                                                        | 关键依赖                        |
| -------------- | ----------------------------------------------------------------------------------------- | --------------------------- |
| `cat-client`   | 旧版客户端（项目内仅作示例/工具，新版客户端在 `lib/java`）                                                       | netty-all, plexus           |
| `cat-core`     | 核心：消息编解码、消费框架、报表服务抽象、配置、DAL 基类                                                            | dal-jdbc, netty, mysql      |
| `cat-consumer` | 实时消费分析：8 类 Analyzer（Transaction/Event/Heartbeat/Problem/Cross/Dependency/State/Storage 等） | cat-core                    |
| `cat-hadoop`   | LogView 落地：本地块存储 + HDFS bucket                                                            | cat-core, hadoop-client     |
| `cat-alarm`    | 告警 SPI：Channel/Sender/Decorator/Spliter/Rule                                              | cat-core                    |
| `cat-home`     | Web/管理端 + 报表展示 + 任务调度 + 入口 (Servlet/JSP)                                                  | 全部上述 + jetty/jsp/freemarker |

部署时 **只需打包 cat-home**（其内部已聚合 client/core/consumer/hadoop/alarm）。

## 模块启动顺序

由 `org.unidal.initialization.Module` 编排：

```
CatClientModule  (lib/java，新版客户端)
   ↓
CatCoreModule
   ↓
CatConsumerModule  →  CatHadoopModule
                   ↓
              CatHomeModule (web 入口)
```

`cat-home/CatHomeModule.java`：
- `setup()`：启动 `TcpSocketReceiver`（Netty 2280 端口）
- `execute()`：启动 `ReportReloadTask`、`MessageConsumer`、`TaskConsumer`（job 机器）、`AlarmManager`（alert 机器）

## cat-home 内部包结构

```
com.dianping.cat
├── CatHomeModule.java          # 模块入口
├── servlet/CatServlet.java     # Servlet 启动
├── build/                      # Plexus 组件配置
│   ├── ComponentsConfigurator.java
│   ├── WebComponentConfigurator.java
│   ├── HomeAlarmComponentConfigurator.java
│   ├── CatDatabaseConfigurator.java
│   └── report/                 # 各 Analyzer 对应的报表组件配置
├── report/
│   ├── ReportModule.java       # @ModuleMeta(name="r")
│   ├── ReportPage.java         # 26 个报表页枚举
│   ├── page/                   # 每个页一个子包
│   │   ├── transaction/        # /r/t
│   │   ├── event/              # /r/e
│   │   ├── problem/            # /r/p
│   │   ├── heartbeat/          # /r/h
│   │   ├── logview/            # /r/m
│   │   ├── home/ logview/ ... 等 26 个
│   │   └── …
│   ├── alert/                  # 告警发送/规则联动
│   ├── graph/                  # SVG 图表
│   ├── service/                # ModelService 抽象
│   └── task/                   # 离线 Task（小时/天/周/月报）
└── system/
    ├── SystemModule.java       # @ModuleMeta(name="s")
    ├── page/
    │   ├── config/             # /s/config (52 个 op，最大)
    │   ├── login/ permission/ project/ business/ plugin/ router/
    └── …
```

## cat-consumer 包结构

每个 Analyzer 一个子包，包含：
- `XxxAnalyzer.java`：`extends AbstractMessageAnalyzer`，实时消费 `MessageTree`
- `XxxDelegate.java`：周期性持久化
- `model/`：codegen 生成的 XML 模型类（`entity/` + `transform/`）

```
com.dianping.cat.consumer
├── CatConsumerModule.java
├── transaction/      ID="transaction"
├── event/            ID="event"
├── heartbeat/        ID="heartbeat"
├── problem/          ID="problem"
├── cross/            ID="cross"
├── dependency/       ID="dependency"
├── state/            ID="state"
├── storage/          ID="storage"
├── matrix/           ID="matrix"
├── top/              ID="top"
├── dump/             ID="dump"        # logview dump
├── business/         ID="business"
└── config/           # consumer 端配置
```

## 代码生成

- `org.unidal.maven.plugins:codegen-maven-plugin`：从 `META-INF/dal/model/*.xml` 生成 model entity/visitor
- `org.unidal.maven.plugins:plexus-maven-plugin`：生成 Plexus DI components.xml
- `META-INF/dal/jdbc/*.xml`：DAL-JDBC ORM 配置，生成 DAO

## 技术栈年龄速览

- Servlet 2.5 / JSP 2.1（2007 年规范）
- Jetty 6.1.26（已停维护）
- Hadoop 2.4.1
- jstl 1.2、freemarker 2.3.9
- 客户端 jQuery + flot + jqGrid + Bootstrap 2/3
- Plexus IoC 容器（早期 Maven 同款，与 Spring 互斥）

→ 重构动机充分。前端框架 + 后端 DI 全需替换。
