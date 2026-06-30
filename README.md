# cu1-obisidian

个人 Obsidian 知识库，用于沉淀技术笔记、项目方案与日常记录。

## 项目结构

```
.
├── note/         # 笔记与日常记录
├── project/      # 项目文档与方案拆解
├── server/       # 本地服务部署与校验
└── sop/          # 标准操作流程
```

### note/ — 笔记与日常记录

- **ES/**：Elasticsearch 相关笔记目录，当前为空。
- **Java/**：Java 学习笔记，覆盖 Spring Modulith、JVM、基础知识与线程池源码分析。
- **OpenTelemetry/**：OpenTelemetry 学习大纲与笔记，主题包含核心概念、Java Spring / Go 接入与生产实践。
- **ai/**：AI 工程学习与实践笔记，当前包含 AI 工程技术学习路线，以及 review-agent 设计与评审流程实践。
- **redis/**：Redis 笔记，主题包含最佳实践、大 Value 分拆、多 key 合并、高可用部署与配套图示。
- **方案设计/**：方案类资料，当前包含“二级缓存解决热 key 问题”。
- **碎碎念/**：非正式记录，包含音乐、旅行、札记，以及日常开发思考类文章。
- **面试问题记录/**：面试准备资料，包含常见问题整理与反问清单。

### project/ — 项目文档与方案拆解

- **cat/**：CAT 4.0-RC1 现状梳理与重构准备文档，覆盖模块、架构、路由、存储与重构方案。
- **hot-deployment/**：Spring Boot 热更新 IDEA 插件项目文档，按知识准备、计划、规格、任务四类组织。
- **movie-line-search/**：电影台词搜索引擎项目设想与产品说明。
- **online-judge/**：Online Judge 一期 PRD，聚焦题库、判题、比赛与 ABAC 权限模型。
- **raptor/**：服务指标上报与分析系统需求文档，对标美团 Raptor。

### server/ — 本地服务部署与校验

- `compose/`：本地基础设施的 Docker Compose 编排文件，覆盖 MySQL、Redis、Kafka、Elasticsearch、Apollo、CAT 等组件。
- `scripts/`：服务运维脚本，当前包含备份脚本。
- `verify/`：各组件与全栈自检文档，用于验证部署结果。
- `init.md`：本地局域网开发服务器初始部署方案。

### sop/

标准操作流程目录，当前为空。
