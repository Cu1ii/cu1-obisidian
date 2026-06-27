# CAT 重构文档索引

CAT 4.0-RC1 现状梳理。为前后端分离重构（Vue 前端 + Spring Modulith 后端）做准备。

## 文档目录

- [[01-modules|模块结构]] — Maven 模块划分、依赖关系、技术栈
- [[02-architecture|架构与数据流]] — 客户端上报 → 服务端消费 → 报表查询全链路
- [[03-routing|路由与 MVC 框架]] — Unidal MVC、`/r/*` `/s/*` 入口约定
- [[04-pages-apis|页面与接口映射]] — 所有 ReportPage / SystemPage 的 URL → JSP/Handler 映射
- [[05-storage|存储层]] — DAL-JDBC、MySQL 报表元数据、HDFS LogView、本地块存储
- [[06-refactor-plan|重构建议]] — Vue + Spring Modulith 拆分思路、API 抽取优先级
- [[07-functional-modules|功能模块与依赖关系]] — **重构视角**：13 个职责模块 (M0–M12)、依赖矩阵、modulith 落地方案

## 关键事实速查

- **版本**：4.0-RC1，Java 8，Maven 多模块
- **IoC**：Plexus（codehaus）+ Unidal lookup，*非 Spring*
- **MVC**：unidal `web-framework`，URL `/{module}/{action}?op={op}`
- **DAO**：DAL-JDBC（基于 XML codegen）
- **前端**：JSP + JSTL + jQuery + Bootstrap + flot/jqGrid，无前后端分离
- **协议**：Netty TCP 2280，自研二进制协议（PlainText/Native/Html/Waterfall）
- **存储**：MySQL（元数据 + 报表索引）+ 本地块存储 + HDFS（可选 logview）
