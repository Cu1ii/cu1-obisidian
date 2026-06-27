# 04 - 页面与接口映射

按 module → page → action 的三层结构枚举所有入口。

## /r/* — Report 报表入口

### /r/t — Transaction 事务

| op | 说明 | JSP |
|---|---|---|
| `view` | 小时报表 | `transaction.jsp` |
| `history` | 历史报表 | `transactionHistoryReport.jsp` |
| `graphs` | 单 type 图表 | `transactionGraphs.jsp` |
| `historyGraph` | 历史图表 | `transactionHistoryGraphs.jsp` |
| `groupReport` | 分组小时报表 | `transactionGroup.jsp` |
| `groupGraphs` | 分组图表 | `transactionGraphs.jsp` |
| `historyGroupReport` | 分组历史报表 | `transactionHistoryGroupReport.jsp` |
| `historyGroupGraph` | 分组历史图表 | `transactionHistoryGraphs.jsp` |

参数共有：`domain`、`date` (YYYYMMDDHH)、`ip`、`type`、`name`、`group`、`xml=true` 出 XML

### /r/e — Event 事件

同 transaction 八种 op，JSP 在 `jsp/report/event/`

### /r/p — Problem 问题

| op | 说明 |
|---|---|
| `view` | 小时 |
| `history` | 历史 |
| `detail` | 详情 |
| `group` | 分组 |
| `thread` | 按线程 |
| `hourlyGraph` | 小时图 |
| `historyGraph` | 历史图 |
| `groupGraphs` | 分组图 |

### /r/h — Heartbeat 心跳

`view`、`history`、`historyPart`

### /r/m — LogView

`view` — 通过 `id={MessageId}` 取链路

### /r/cross — Cross 调用链

`host`、`method`、`view` (project)、`historyHost`、`historyMethod`、`history`、`query`

### /r/cache

`view`、`history`

### /r/matrix

`view`、`history`

### /r/state

`view`、`history`、`graph`、`historyGraph`

### /r/storage

`view`、`hourlyGraph`、`history`、`dashboard`

### /r/dependency

`lineChart`、`dependencyGraph`、`dashboard`

### /r/top

`health`、`view`、`api`（**JSON 输出**）

### /r/statistics

`historyService`、`historyHeavy`、`historyUtilization`、`summary`

### /r/alteration

`insert` (POST 变更事件)、`view`

### /r/alert

`alert` (POST 触发)、`insert` (POST 接收外部告警)、`view`

### /r/monitor — 业务指标采集 API

| op | 含义 |
|---|---|
| `count` | 计数 |
| `avg` | 平均 |
| `sum` | 求和 |
| `batch` | 批量（TAB 分隔） |

无视图，纯 HTTP 接收端点。

### /r/business

`view`

### /r/overload

`view`

### /r/home

`view`、`checkpoint`、`threadDump`

### /r/model — 跨实例互查

`xml` — 内部使用，集群间互拉 XML 报表

## /s/* — System 管理入口

### /s/login

`login`、`logout`

### /s/permission

`user`、`resource`、`error`

### /s/project

`domains`、`projectUpdate`

### /s/business

`list`、`add`、`delete`

### /s/plugin

`view`、`doc`

### /s/router

`api`、`json`、`build`、`model`

### /s/config （**52 个 op**，大杂烩）

按主题分组：

**项目配置**
- `projects`、`projectAdd`、`updateSubmit`、`projectDelete`

**拓扑图**
- `topologyGraphNodeConfigList`、`topologyGraphNodeConfigAdd`、`topologyGraphNodeConfigAddSumbit`、`topologyGraphNodeConfigDelete`
- `topologyGraphEdgeConfigList`、`topologyGraphEdgeConfigAdd`、`topologyGraphEdgeConfigAddSumbit`、`topologyGraphEdgeConfigDelete`
- `topoGraphFormatUpdate`

**心跳告警规则**
- `heartbeatRuleConfigList`、`heartbeatRuleUpdate`、`heartbeatRuleSubmit`、`heartbeatRulDelete`
- `displayPolicy`

**告警接收人/策略**
- `alertDefaultReceivers`、`alertPolicy`、`alertSenderConfigUpdate`

**异常规则**
- `exception`、`exceptionThresholdAdd`、`exceptionThresholdUpdate`、`exceptionThresholdUpdateSubmit`、`exceptionThresholdDelete`
- `exceptionExcludeAdd`、`exceptionExcludeUpdateSubmit`、`exceptionExcludeDelete`

**事务/事件/存储 规则**
- `transactionRule`、`transactionRuleUpdate`、`transactionRuleSubmit`、`transactionRuleDelete`
- `eventRule`、`eventRuleUpdate`、`eventRuleSubmit`、`eventRuleDelete`
- `storageRule`、`storageRuleUpdate`、`storageRuleSubmit`、`storageRuleDelete`
- `storageGroupConfigUpdate`

**域分组配置**
- `domainGroupConfigs`、`domainGroupConfigUpdate`、`domainGroupConfigSubmit`、`domainGroupConfigDelete`

**路由 / 采样 / 服务器配置**
- `routerConfigUpdate`
- `sampleConfigUpdate`
- `serverFilterConfigUpdate`、`serverConfigUpdate`
- `reportReloadConfigUpdate`
- `allReportConfig`

## JSP 目录结构

`cat-home/src/main/webapp/jsp/`

```
jsp/
├── report/                       # /r/* 渲染目标
│   ├── transaction/              # 8 个 jsp
│   ├── event/
│   ├── problem/
│   ├── heartbeat/
│   ├── home/                     # 含 interface/ 子目录（API 文档）
│   ├── alert/ alteration/ app/ applog/ appstats/
│   ├── browser/ business/ cache/ crash/ cross/
│   ├── dependency/ event/ exceptionAlert/ heartbeat/
│   ├── heavy/ highload/ jar/ logview/ matrix/
│   ├── monitor/ network/ overload/ problem/
│   ├── server/ service/ state/ statistics/
│   ├── storage/ summary/ top/ transaction/ utilization/
│   └── …
└── system/                       # /s/* 渲染目标
    ├── activity/ aggregation/ alarm/ alert/
    ├── appConfig/ appRule/ black/ bug/
    ├── business/ defaultReceiver/ display/
    ├── domainGroup/ eventRule/ exception/
    ├── heartbeat/ permission/ plugin/ project/
    ├── reload/ router/ sample/ sender/
    ├── server/ storage/ storageRule/
    ├── thirdParty/ topology/ transactionRule/
    ├── urlPattern/ utilization/ webRule/
    ├── login.jsp、project.jsp、web.jsp、webconfig.jsp、configTree.jsp
    └── …
```

## 公共静态资源

```
webapp/
├── assets/   # AdminLTE 风格后台模板（css/js/font/img）
├── css/      # CAT 自有样式
├── js/       # 老 jQuery + 业务脚本（datatable 等）
├── images/
├── img/
├── doc/      # 离线 doc
└── WEB-INF/
    ├── web.xml
    ├── app.tld         # JSP 自定义标签库
    └── tags/           # JSP tag files
```

## 输出格式分类

| 类型 | 触发 | 用途 |
|---|---|---|
| HTML JSP | 默认 | 页面渲染 |
| XML | `xml=true` 参数或专门 op | 跨实例聚合（`/r/model`） |
| JSON | 部分 op（如 `top?op=api`、`app?op=linechartJson`、`web?op=json`、`browser?op=speedJson`） | AJAX/外部接入 |
| 纯 ack | `monitor`、`alert?op=insert`、`alteration?op=insert` | 数据采集端点 |

> **重构启示**：纯 API 类入口（monitor/alert/alteration/app/web/browser/top api）已经天然适合保留为后端 RESTful 接口；其余 JSP 渲染入口需要改为返回 JSON，由 Vue 接管渲染。
