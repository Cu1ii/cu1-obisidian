# 06 - 重构建议（Vue + Spring Modulith）

## 目标拆分

```
cat-monorepo/
├── cat-server/                 # Spring Boot + Modulith
│   ├── core/                   # 消息编解码、TCP 接收（保留 Netty）
│   ├── consumer/               # Analyzer + Period
│   ├── storage/                # MySQL DAO（JPA/MyBatis）+ 本地块 + HDFS
│   ├── alarm/                  # 告警 SPI
│   ├── report/                 # 报表查询 + REST 控制器
│   ├── config/                 # 配置管理
│   ├── auth/                   # 登录 / 权限
│   └── application/            # 启动类 + 模块装配
└── cat-web/                    # Vue 3 + Vite + TypeScript
    ├── src/
    │   ├── api/                # axios 封装，对应 server REST
    │   ├── views/              # 各报表页面（按 ReportPage 拆）
    │   ├── components/         # 图表/表格通用组件
    │   ├── stores/             # Pinia
    │   └── router/             # vue-router
    └── …
```

## Spring Modulith 模块边界

按 `cat-consumer` 已有的 Analyzer 切分，每个 Analyzer 作为一个 Modulith module：

| Modulith module | 对应 CAT |
|---|---|
| `transaction` | TransactionAnalyzer + 报表查询 |
| `event` | EventAnalyzer |
| `problem` | ProblemAnalyzer |
| `heartbeat` | HeartbeatAnalyzer |
| `cross` | CrossAnalyzer |
| `dependency` | DependencyAnalyzer |
| `state` | StateAnalyzer |
| `storage` | StorageAnalyzer |
| `top` | TopAnalyzer |
| `logview` | DumpAnalyzer + bucket 读写 |
| `business` | BusinessAnalyzer + monitor 上报 |
| `alarm` | cat-alarm |
| `config` | 全局配置中心 |
| `auth` | 登录 / 权限 |
| `infra` | 共享：Period、TCP 接收、消息编解码 |

模块间通信遵循 Modulith 的事件 + ApplicationModuleListener，避免直接调用其他模块的 internal 包。

## 后端 REST 接口设计原则

URL 统一 `/api/v1/{domain}/{resource}`，废弃 `/r/x?op=y` 风格：

| 旧 URL | 新 REST |
|---|---|
| `/r/t?op=view&domain=foo&date=2024010110` | `GET /api/v1/transaction/hourly?domain=foo&date=2024010110` |
| `/r/t?op=history&domain=foo&start=...&end=...` | `GET /api/v1/transaction/range?domain=foo&start=...&end=...` |
| `/r/t?op=graphs&...` | `GET /api/v1/transaction/graphs?...` |
| `/r/p?op=detail&id=...` | `GET /api/v1/problem/{id}` |
| `/r/m?op=view&id=...` | `GET /api/v1/logview/{messageId}` |
| `/r/monitor?op=count&...` | `POST /api/v1/metric/count` (body) |
| `/r/alert?op=insert` | `POST /api/v1/alert` |
| `/r/alteration?op=insert` | `POST /api/v1/alteration` |
| `/s/config?op=projects` | `GET /api/v1/admin/projects` |
| `/s/config?op=transactionRule` | `GET /api/v1/admin/rules/transaction` |
| `/s/login?op=login` | `POST /api/v1/auth/login` |

返回统一 `{code, msg, data}` 包裹。报表大对象用 `data.report`，含 `domain/period/machines[]/types[]` 等结构（直接把 codegen 的 entity 改 Jackson 序列化即可）。

## 前端页面拆分（Vue Router）

```
/                                 → 首页（替代 /r/home）
/transaction                      → 事务报表
/transaction/graph                → 图表
/transaction/history              → 历史
/event /problem /heartbeat /...   → 同模式
/logview/:id                      → 链路详情
/dashboard/topology               → 拓扑大盘
/dashboard/storage                → 存储大盘
/admin/projects                   → 项目管理
/admin/rules/transaction          → 事务告警规则
/admin/users                      → 权限
/login                            → 登录
```

## 重构推进顺序（建议）

1. **第 1 阶段：搭骨架**
   - 新建 Spring Boot 工程，迁 `cat-core` Netty TCP 接收 + 消息编解码（这部分稳定，纯 Java，少改）
   - 引入 Spring Modulith，把 Analyzer 包按上表落到各 module
   - MySQL DAO 改 JPA / MyBatis-Plus
   - 留旧 cat-home 当存量入口共存

2. **第 2 阶段：API 层抽出**
   - 选 1 个高频报表（推荐 transaction）：写 REST controller，把 codegen entity 标 Jackson 序列化
   - Vue 3 起一个空壳，先实现 transaction 页
   - 双轨：JSP 与 Vue 并存，Nginx 按路径分流

3. **第 3 阶段：批量迁页**
   - event/problem/heartbeat 等同结构页一次性迁
   - 大盘类（top/storage/dashboard）独立做（新视觉）
   - 管理类（/s/config 52 个 op）按主题拆 RESTful 资源

4. **第 4 阶段：废弃 JSP/Plexus**
   - 移除 `cat-home`、`cat-client` 老模块
   - 客户端只保留 `lib/java`（已经是新版）
   - Plexus IoC 全部转 Spring `@Component`

5. **第 5 阶段：长尾**
   - LogView binary 块存储抽 service
   - 配置 XML 迁 DB 或 Spring config
   - 告警渠道改插件化（SPI 已经类似）

## 风险点

- **报表 binary 解码**：codegen 出来的 visitor 链很重，迁到新模块时保留原 model 包是最稳妥的（不重写）。
- **跨实例 RemoteModelService**：旧版用 `/r/model?xml=...` 互拉。新版要么保留 XML，要么改 gRPC 内部调用。
- **DAL-JDBC**：unidal 自研 ORM，重构必须替换。codegen XML → 手写 JPA entity 是一次性投入。
- **Plexus 依赖注入**：所有 `@Named(type=…)` `@Inject` 替换为 Spring 的 `@Component` `@Autowired`，简单但量大（每个 Handler/Service/Manager 都要改）。
- **Servlet 2.5 / Jetty 6**：Spring Boot 内嵌 Tomcat/Jetty 9+ 可直接替换，但 `web.xml` 风格的 Filter 需用 `FilterRegistrationBean` 重写。
- **Unidal MVC 注解**：`@ModuleMeta`/`@InboundActionMeta` → 全改 Spring `@RestController`/`@RequestMapping`。

## 必须保留的资产

- 客户端协议（不改 = 现有客户端零成本兼容）
- MySQL 表结构（数据迁移成本最高，能不动就不动）
- Netty 接收逻辑（`TcpSocketReceiver` 几乎可平移）
- Analyzer 业务计算逻辑（核心知识在这）
- codegen 的 model 类（重写代价大，让它跑就行）

## 不必保留

- Plexus 容器
- Unidal MVC + JSP + JSTL
- AdminLTE 模板（assets/）
- web.xml + Filter（改 Spring 配置）
- DAL-JDBC（改 JPA / MyBatis）
- `cat-client` 旧模块（已经废弃，文档明示）
