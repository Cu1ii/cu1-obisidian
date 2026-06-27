# 03 - 路由与 Unidal MVC

## URL 总规则

```
http://{host}:{port}/cat/{module}/{path}?op={action}&...

  module = "r"  → ReportModule    (业务报表查看)
  module = "s"  → SystemModule    (管理/配置)
  path   = ReportPage 或 SystemPage 的短路径（如 t/e/p/h/m/config）
  op     = Action 枚举的 name 字符串
```

例：
- `/cat/r/t?op=view&domain=foo&date=2024010110` → 小时事务报表
- `/cat/r/p?op=detail&domain=foo&id=...` → Problem 详情
- `/cat/s/config?op=projects` → 项目配置
- `/cat/s/config?op=transactionRule` → 事务告警规则
- `/cat/s/login?op=login` → 登录

## web.xml 关键映射

`cat-home/src/main/webapp/WEB-INF/web.xml`：

```xml
<servlet>
  <servlet-name>cat-servlet</servlet-name>
  <servlet-class>com.dianping.cat.servlet.CatServlet</servlet-class>
  <load-on-startup>1</load-on-startup>
</servlet>
<servlet>
  <servlet-name>mvc-servlet</servlet-name>
  <servlet-class>org.unidal.web.MVC</servlet-class>
  <load-on-startup>2</load-on-startup>
</servlet>

<servlet-mapping>
  <servlet-name>mvc-servlet</servlet-name>
  <url-pattern>/r/*</url-pattern>
</servlet-mapping>
<servlet-mapping>
  <servlet-name>mvc-servlet</servlet-name>
  <url-pattern>/s/*</url-pattern>
</servlet-mapping>
```

Filter 链：
- `cat-filter` (CatFilter)：CAT 自身埋点（事务）
- `permission-filter`：未登录跳转 `/s/login`，无权限跳 `/s/permission?op=error`
- `domain-filter`：解析/补全 domain 参数

## Unidal MVC 路由解析

### 注解

| 注解 | 作用 |
|---|---|
| `@ModuleMeta(name="r")` | 类级，绑定 URL 第一段。位于 `ReportModule.java`/`SystemModule.java` |
| `@ModulePagesMeta({...})` | 类级，列出该 module 下所有 page Handler |
| `@PayloadMeta(Payload.class)` | 方法级，声明请求参数绑定类 |
| `@InboundActionMeta(name="t")` | 方法级，绑定 URL 第二段（path） |
| `@OutboundActionMeta(name="t")` | 方法级，输出渲染入口 |

### Handler 接口

```java
public interface PageHandler<C extends ActionContext<?>> {
    void handleInbound(C ctx);   // 解析参数 / 跳转
    void handleOutbound(C ctx);  // 装数据 / 选 view
}
```

每个 page 子包标准 5 件套：
- `Action.java` ← 枚举（op 值）
- `Payload.java` ← 请求参数 POJO
- `Context.java` ← `ActionContext<Payload>`
- `Model.java` ← 给 JSP 用的视图模型
- `Handler.java` ← 业务入口
- `JspViewer.java` + `JspFile.java` ← `Action → JSP 路径` 映射

### 实例：transaction 路由

```
URL: /cat/r/t?op=view&domain=foo&date=2024010110
        │  │   └→ Action.HOURLY_REPORT (name="view")
        │  └→ ReportPage.TRANSACTION (path="t") + InboundActionMeta(name="t")
        └→ ReportModule (@ModuleMeta name="r")

→ com.dianping.cat.report.page.transaction.Handler.handleOutbound()
→ switch(HOURLY_REPORT) → getHourlyReport(payload)
→ JspViewer → /jsp/report/transaction/transaction.jsp
```

## ReportPage 全集（src: `report/ReportPage.java`）

| Page | name | path | URL 前缀 | 功能 |
|---|---|---|---|---|
| HOME | home | home | /r/home | 首页 |
| PROBLEM | problem | p | /r/p | 问题报告 |
| TRANSACTION | transaction | t | /r/t | 事务报告 |
| EVENT | event | e | /r/e | 事件报告 |
| HEARTBEAT | heartbeat | h | /r/h | 心跳报告 |
| LOGVIEW | logview | m | /r/m | 详情链路 |
| MODEL | model | model | /r/model | 跨实例 XML 互查 |
| MATRIX | matrix | matrix | /r/matrix | 矩阵 |
| CROSS | cross | cross | /r/cross | 调用链 |
| CACHE | cache | cache | /r/cache | 缓存 |
| STATE | state | state | /r/state | 服务端状态 |
| DEPENDENCY | dependency | dependency | /r/dependency | 依赖拓扑 |
| STATISTICS | statistics | statistics | /r/statistics | 统计 |
| ALTERATION | alteration | alteration | /r/alteration | 变更事件接收/查询 |
| MONITOR | monitor | monitor | /r/monitor | 业务指标接收 API |
| NETWORK | network | network | /r/network | 网络监控 |
| APP | app | app | /r/app | App 端监控 |
| ALERT | alert | alert | /r/alert | 告警接收 API |
| OVERLOAD | overload | overload | /r/overload | 过载 |
| STORAGE | storage | storage | /r/storage | DB/Cache 存储 |
| TOP | top | top | /r/top | 错误大盘 |
| BROWSER | browser | browser | /r/browser | Web 端监控 |
| SERVER | server | server | /r/server | 服务器监控 |
| BUSINESS | business | business | /r/business | 业务监控 |
| APPSTATS | appstats | appstats | /r/appstats | App 统计 |
| CRASH | crash | crash | /r/crash | App Crash |
| APPLOG | applog | applog | /r/applog | App 日志 |

> 注：`ReportModule` 中 `@ModulePagesMeta` 实际只列了 20 个 Handler。`network/app/browser/server/appstats/crash/applog` 几个枚举存在但 Handler 未在 ReportModule 中注册，可能依赖懒加载或老代码残留。重构时核对。

## SystemPage 入口

`/s/login`、`/s/config`、`/s/project`、`/s/business`、`/s/plugin`、`/s/permission`、`/s/router`

详见 [[04-pages-apis|页面与接口映射]]。

## ViewerPattern：Handler 输出选择

```java
if (payload.isXml()) {
    m_xmlViewer.view(ctx, model);   // 输出 XML（跨实例聚合用）
} else {
    m_jspViewer.view(ctx, model);   // 转发 JSP
}
```

部分页面（如 `monitor/Handler.java`）不渲染页面，直接作为 HTTP API：
- `/r/monitor?op=count&group=...&domain=...&key=...` 上报 metric
- `/r/alert?op=insert&...` 接收外部告警
- `/r/alteration?op=insert&...` 接收变更事件
- `/r/app?op=linechartJson&...` 返回 JSON 图表数据
- `/r/web?op=json&...` 浏览器监控 JSON
- `/r/browser?op=speedJson&...` 速度数据 JSON
- `/r/top?op=api` 大盘 JSON
