# AI 中转站 MVP 开发清单

目标：2-3 天内做出一个可上线自用/小范围给朋友用的 AI API 中转站。先跑通「用户拿自己的 key 调接口 -> 系统转发到上游模型 -> 记录用量 -> 可控额度」这条主链路。

产品假设：首批用户是你自己和少量朋友，核心价值不是完整商业化，而是快速获得一个 **可控成本、可发放额度、OpenAI API 兼容、可替换上游** 的中转层。

## 1. MVP 定位

只做一个 **OpenAI API 兼容的 AI 网关**。

MVP P0 必须支持：

- 用户获得自己的 API Key
- 用户用 OpenAI SDK / OpenAI 请求格式调用你的服务
- 后端根据模型配置转发到上游供应商
- 记录请求、token、费用、错误、耗时
- 用户有额度，额度不足自动拒绝请求
- 管理员可以看用户用量、禁用 key、手动充值/调整额度
- 支持基础鉴权、限流、超时、错误日志和后台登录保护

MVP P1 可以上线后补：

- 用户控制台
- 动态供应商/模型配置后台
- 更漂亮的统计图表
- 接入文档完善版
- 更多模型接口，例如 embeddings、images
- 多上游自动 failover、权重路由、测速排序

第一版明确不做：

- 在线支付
- 复杂套餐系统
- 多租户组织权限
- 精细化账单发票
- 模型广场/复杂前台官网
- Prompt 管理、工作流、聊天 UI
- 高并发、多区域、自动容灾
- 内容安全策略

## 2. 技术栈

按你现有熟悉度，MVP 建议：

- 后端：Java Spring Boot + Spring Modulith
- 数据库：MySQL
- 配置中心：Apollo
- 前端后台：Vue 3 + Element Plus / Naive UI
- 上游 HTTP 客户端：Spring WebClient / OkHttp，选你更熟的
- 部署：沿用你现有 Java 服务部署方式

选型原则：

- 后端你熟 Java Spring，所以不要为了全栈一体强上 Next.js。
- Spring Modulith 只用来做单体内模块边界，不在 MVP 里引入微服务、消息中间件或复杂事件编排。
- MySQL 已经够用，不需要为了 MVP 换 PostgreSQL。
- Apollo 已经有，MVP 的供应商、模型映射、价格配置先放 Apollo，不做配置后台。
- Vue 做管理后台很合适，页面简单、开发快。

## 3. 核心架构

```text
用户 / OpenAI SDK
  -> /v1/chat/completions
  -> Spring Boot / Spring Modulith 网关
  -> API Key 鉴权 / 限流 / 额度检查
  -> 模型路由配置 Apollo
  -> Provider Adapter
  -> 上游 AI Provider
  -> 记录日志 / token / 扣费
  -> 返回 OpenAI-compatible 响应
```

MVP 只抽象一层 Provider Adapter：

```text
AiProviderClient
  - chatCompletion()
  - streamChatCompletion()
  - listModels()
```

第一版只实现：

```text
OpenAICompatibleProviderClient
```

含义：

- 只要上游兼容 OpenAI API，就可以通过 Apollo 配置接入。
- 不兼容 OpenAI 格式的供应商，后续再新增单独 Adapter。
- 不做插件系统、不做复杂 SPI、不做可视化编排。

### 3.1 Spring Modulith 模块划分

MVP 保持一个后端单体，但按 Modulith 拆清楚包边界：

```text
com.xxx.aigateway
  ├─ gateway        # /v1 OpenAI-compatible API、请求/响应转发
  ├─ provider       # AiProviderClient、OpenAICompatibleProviderClient、模型路由
  ├─ apikey         # API Key 生成、hash、鉴权、禁用
  ├─ account        # 用户、余额、充值、扣费
  ├─ usage          # 请求日志、token、费用、耗时
  ├─ admin          # /admin 后台接口
  └─ config         # Apollo 配置绑定、配置校验
```

MVP 使用原则：

- 模块之间只通过公开 service / interface 调用，不跨模块直接访问内部实现。
- 可以用 Spring Modulith 的模块验证测试检查边界。
- 暂时不强依赖 Modulith 事件发布；扣费、日志可以先用同步调用保证速度。
- 不为了“架构漂亮”拆太细，先保证主链路上线。

## 4. Apollo 配置

MVP 的上游供应商、模型映射、价格配置放 Apollo。

示例：

```yaml
ai:
  providers:
    openai:
      type: openai-compatible
      baseUrl: https://api.openai.com/v1
      apiKey: ${OPENAI_API_KEY}
      enabled: true
    siliconflow:
      type: openai-compatible
      baseUrl: https://api.siliconflow.cn/v1
      apiKey: ${SILICONFLOW_API_KEY}
      enabled: true

  models:
    gpt-4o-mini:
      provider: openai
      providerModel: gpt-4o-mini
      inputPrice: 0.15
      outputPrice: 0.60
      enabled: true
    deepseek-chat:
      provider: siliconflow
      providerModel: deepseek-ai/DeepSeek-V3
      inputPrice: 0.14
      outputPrice: 0.28
      enabled: true

  limits:
    requestTimeoutSeconds: 60
    maxRequestBodyBytes: 1048576
    apiKeyRateLimitPerMinute: 60
```

MVP 约束：

- `baseUrl` 只允许 HTTPS。
- 生产环境优先使用预置供应商域名，不允许随便填任意 URL。
- 上游 API Key 只在服务端读取，不暴露到前端。
- Apollo 改配置后，服务端可以热加载；如果热加载来不及做，重启生效也可以接受。

## 5. 核心模块

### 5.1 API 转发层

P0 必须开发：

- `POST /v1/chat/completions`
- `GET /v1/models`
- OpenAI-compatible 请求格式
- 支持非 stream
- 支持 stream，优先保证可用，不追求完美兼容所有边界
- 请求头鉴权：`Authorization: Bearer sk-xxx`
- 根据请求里的 `model` 查 Apollo 模型映射
- 调用 `OpenAICompatibleProviderClient`
- 转发上游响应，尽量保持 OpenAI 格式
- 捕获并标准化错误返回

P1 再做：

- `POST /v1/embeddings`
- `POST /v1/images/generations`
- 多供应商自动重试 / failover

### 5.2 上游供应商接入

P0 必须开发：

- Apollo 配置上游 `baseUrl`
- Apollo 配置上游 API Key
- Apollo 配置模型映射，例如：
  - 用户请求 `gpt-4o-mini`
  - 实际转发到某个上游的具体模型名
- Apollo 配置模型输入/输出价格
- 上游启用/禁用
- 简单失败处理：主供应商失败后返回标准化错误即可，MVP 不做多供应商自动重试或切换

P0 不做：

- 供应商配置后台
- 模型配置后台
- 权重路由
- 健康检查自动摘除

### 5.3 用户与 API Key

P0 必须开发：

- 用户表
- API Key 表
- 管理员创建 API Key
- API Key 禁用、删除
- API Key 只展示一次，数据库存 hash
- 数据库存 `key_prefix` 用于后台识别
- 每个 key 绑定用户
- 每个用户有余额/额度字段

MVP 账户体系：

- 管理员手动创建用户
- 管理员手动发 key
- 不做用户自助注册
- 不做复杂注册审核

### 5.4 额度与计费

P0 必须开发：

- 请求前检查用户是否有额度
- 请求后记录 token 和估算费用
- 扣减用户余额/额度
- 管理员可手动加余额
- 支持不同模型不同单价

关键约束：

- 并发请求必须防透支：用 MySQL 事务、行锁、原子条件更新，或先做固定额度预扣。
- stream 请求必须有结算兜底：正常结束、客户端中断、上游异常都要记录日志并尽量扣费。
- 如果上游没有返回 usage，MVP 可以先按本地 tokenizer 或粗略估算 token，但必须记录 `estimated = true`。
- 余额单位建议用「内部点数」而不是人民币余额，避免支付和财务复杂度。

MVP 最简单计费策略：

1. 请求前按模型设置一个最小预扣额度。
2. 请求完成后按实际 usage 或估算 usage 结算。
3. 多退少补；异常时至少记录日志，不让请求完全消失。

### 5.5 请求日志

P0 必须记录：

- 请求时间
- 用户 ID
- API Key ID
- key_prefix
- public model
- provider
- provider model
- prompt tokens
- completion tokens
- total tokens
- 是否估算 token
- 估算费用
- 状态：成功/失败/中断
- 标准化错误码
- 脱敏后的短错误信息
- 响应耗时

默认不记录完整 prompt/response，降低隐私风险。

错误日志要求：

- `error_message` 必须脱敏和限长。
- 不得写入 prompt、response、Authorization 头、上游 API Key 或完整上游错误体。
- 需要保留足够信息用于定位：错误类别、上游状态码、内部 request id。

### 5.6 管理后台

P0 后台只做这些：

- 用户列表
- 创建用户
- 用户余额/额度调整
- API Key 创建、列表、禁用、删除
- 请求日志列表
- 简单统计：今日请求量、今日 token、今日费用、错误数

P0 不做：

- 供应商配置后台
- 模型配置后台
- 用户控制台
- 复杂图表

后台交互最低要求：

- 列表页有 loading、empty、error 状态。
- 表单提交有 submitting、success、validation error 状态。
- 禁用 key、删除 key、调整额度前必须二次确认。
- 操作成功后刷新列表或展示明确反馈。

后台安全要求：

- 所有 `/admin/*` 接口必须服务端校验登录态。
- 所有 `/admin/*` 接口必须校验 `role = admin`。
- 如果后台使用 cookie session，写接口要做 SameSite / CSRF token / Origin 校验之一。

### 5.7 用户控制台

P1 再做。

如果后续要做，能力是：

- 查看 API Key 列表、名称、前缀、状态、创建时间、最近使用时间
- 创建成功后一次性展示完整 key 并提供复制按钮
- 丢失后只能删除并重新创建
- 查看余额/额度
- 查看最近请求记录
- 复制调用示例

## 6. 数据表

MVP MySQL 最少这些表。

### 6.1 `users`

- id
- email
- role
- balance
- status
- created_at
- updated_at

### 6.2 `api_keys`

- id
- user_id
- key_hash
- key_prefix
- name
- status
- created_at
- updated_at
- last_used_at

### 6.3 `request_logs`

- id
- request_id
- user_id
- api_key_id
- key_prefix
- public_model
- provider
- provider_model
- status
- prompt_tokens
- completion_tokens
- total_tokens
- estimated_tokens
- cost
- latency_ms
- error_code
- error_message
- created_at

### 6.4 `balance_logs`

- id
- user_id
- amount
- balance_before
- balance_after
- type
- reason
- request_log_id
- created_at

MVP 不需要 `providers` / `models` 表，因为供应商和模型配置先放 Apollo。等 P1 做动态配置后台时再迁入数据库。

## 7. 最小 API 设计

### 7.1 用户调用

```bash
curl https://your-domain.com/v1/chat/completions \
  -H "Authorization: Bearer sk-your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "hello"}],
    "stream": false
  }'
```

### 7.2 OpenAI-compatible API

- `POST /v1/chat/completions`
- `GET /v1/models`

### 7.3 管理后台 API

- `POST /admin/users`
- `GET /admin/users`
- `POST /admin/api-keys`
- `GET /admin/api-keys`
- `PATCH /admin/api-keys/:id/status`
- `DELETE /admin/api-keys/:id`
- `PATCH /admin/users/:id/balance`
- `GET /admin/request-logs`
- `GET /admin/stats/today`

后台接口可以先不追求 REST 完美，能稳定管理即可。

## 8. 2-3 天开发顺序

### Day 1：跑通非 stream 主链路

- 初始化 Spring Boot + Spring Modulith 项目、MySQL、Vue 后台项目
- 按 Modulith 建 `gateway`、`provider`、`apikey`、`account`、`usage`、`admin`、`config` 模块包
- 建 `users`、`api_keys`、`request_logs`、`balance_logs`
- 接 Apollo，读取 provider/model 配置
- 实现 API Key 生成、hash、鉴权
- 实现 `/v1/chat/completions` 非 stream 转发
- 实现 OpenAI-compatible Provider Adapter
- 实现模型映射
- 实现请求日志
- 实现基础额度检查和扣费

验收标准：

- 用 curl 或 OpenAI SDK 能成功请求你的中转 API
- 请求能被转发到至少一个上游
- 数据库能看到日志和扣费记录

### Day 2：后台可管理 + 上线可控

- 实现 Vue 管理后台
- 管理用户、key、额度、请求日志
- 实现 key 禁用/删除
- 实现错误处理标准化
- 限流：按 API Key 每分钟限制请求数
- 请求超时控制
- 请求体大小限制
- 管理员登录和 role 校验
- 部署到线上域名

验收标准：

- 管理员能手动开用户、发 key、充值额度
- 管理员能禁用 key、查看日志
- 用户能用 key 正常调用
- 超额、禁用、错误模型都有明确错误返回

### Day 3：stream、并发扣费、安全兜底

- 支持 stream 响应
- stream 正常结束 / 中断 / 上游异常时都有日志和结算兜底
- 并发扣费防透支：事务、行锁、原子条件更新或预扣
- 错误日志脱敏和限长
- Apollo baseUrl 安全约束
- 简单统计：今日请求量、token、费用、错误数
- 写一页最小接入说明
- 少量真实请求压测和自测

验收标准：

- 可以小范围发给真实用户试用
- 出问题能通过后台定位
- 成本不会无限失控

## 9. 上线前必须检查

- [ ] 用户 key 不明文存数据库
- [ ] 完整 API Key 只在创建时展示一次
- [ ] 上游 key 不暴露到前端
- [ ] Apollo 里的上游配置只在服务端读取
- [ ] 生产环境上游 `baseUrl` 不允许任意非 HTTPS 地址
- [ ] 每个请求都有超时
- [ ] 每个 key 都有限流
- [ ] 余额不足会拒绝请求
- [ ] 并发请求不会绕过余额限制
- [ ] 禁用用户/key 会立即生效
- [ ] 错误请求也会记录日志
- [ ] 错误日志不包含 prompt、response、Authorization、上游 key
- [ ] stream 请求不会导致扣费或日志丢失
- [ ] 管理员后台有登录保护和 role 校验
- [ ] MySQL 有备份方案

## 10. 推荐 MVP 砍掉的东西

这些不要第一版做：

- 自动支付充值
- 优惠券
- 邀请返佣
- 多级代理
- 模型测速排序
- 多上游自动熔断切换
- 复杂 Modulith 事件编排
- 供应商/模型动态配置后台
- 用户自助控制台
- 完整审计系统
- 企业组织空间
- Prompt 审核
- 内容安全策略
- 聊天前端

先把 API 中转、鉴权、扣费、日志、最小后台跑通。

## 11. 最简成功标准

MVP 上线即成功的标准：

1. 管理员能创建用户并发放 API Key。
2. 用户能用 OpenAI SDK 调你的 `/v1/chat/completions`。
3. 系统能根据 Apollo 模型配置转发到至少一个 OpenAI-compatible 上游。
4. 系统能记录 token、费用、错误和耗时。
5. 用户额度用完后自动拒绝请求。
6. 管理员能手动充值、禁用 key、查看日志。
7. 并发和 stream 不会导致明显超额扣费或日志丢失。

做到这 7 点，就可以上线内测。
