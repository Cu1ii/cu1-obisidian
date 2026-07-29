# AI 中转站项目

目标：2-3 天内做出一个可上线自用/小范围内测的 AI API 中转站 MVP。

## 文档目录

- [[project/ai-gateway/00-mvp-scope.md]]：MVP 范围、模块、数据表、开发顺序、上线检查清单

## 当前 MVP 核心

先做一个 OpenAI API 兼容网关：

1. 用户创建/获得 API Key
2. 用户调用 `/v1/chat/completions`
3. 系统转发到上游模型供应商
4. 系统记录 token、费用、错误、耗时
5. 用户额度不足时拒绝请求
6. 管理员可充值、禁用 key、查看日志
