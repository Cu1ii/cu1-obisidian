# AI 中转站 MVP 实施计划

基于 [[project/ai-gateway/00-mvp-scope.md]]，目标是在 2-3 天内完成可上线内测版本。

## 1. 目标与技术边界

- 单仓库：`server/` + `web/`
- 后端：Spring Boot + Spring Modulith
- 数据库：MySQL
- 配置中心：Apollo
- 前端：Vue 3 + Element Plus
- 用户流程：邮箱注册 -> 后缀白名单校验 -> 管理员审核 -> 登录 -> 用户自助管理 API Key
- 上游接入：Apollo 配置驱动 + `OpenAICompatibleProviderClient`
- Cloudflare：不纳入 2-3 天 P0，作为上线后增强项

## 2. 代码结构

```text
project/ai-gateway/
├─ 00-mvp-scope.md
├─ 01-implementation-plan.md
├─ server/
└─ web/
```

后端 Modulith 模块：

```text
server/src/main/java/com/xxx/aigateway/
├─ gateway/       # /v1 API、请求/响应转发
├─ provider/      # Provider Adapter、模型路由
├─ apikey/        # API Key 生成、hash、鉴权、禁用
├─ account/       # 用户、余额、充值、扣费
├─ usage/         # 请求日志、token、费用、耗时
├─ auth/          # 注册、登录、审核状态
├─ admin/         # 管理后台接口
└─ config/        # Apollo 配置绑定和校验
```

前端目录：

```text
web/src/
├─ views/
│  ├─ auth/
│  ├─ dashboard/
│  ├─ api-keys/
│  ├─ usage/
│  └─ admin/
├─ api/
├─ router/
├─ stores/
└─ components/
```

## 3. 基础工程任务

### 3.1 后端初始化

- [ ] 初始化 Spring Boot 项目。
- [ ] 引入 Spring Modulith、Spring Web、Spring Security、Validation。
- [ ] 引入 MySQL Driver、数据访问框架和 Flyway。
- [ ] 接入 Apollo Client。
- [ ] 配置开发、测试、生产环境 profile。
- [ ] 配置统一响应结构和全局异常处理。
- [ ] 配置 request id / trace id。
- [ ] 配置日志格式和敏感字段脱敏。
- [ ] 按 Modulith 创建模块包。
- [ ] 增加 Modulith 模块边界验证测试。

### 3.2 前端初始化

- [ ] 初始化 Vue 3 项目。
- [ ] 引入 Vue Router、Pinia、Element Plus。
- [ ] 配置 API 请求客户端。
- [ ] 配置登录态恢复和退出登录。
- [ ] 配置路由守卫。
- [ ] 配置用户路由和管理员路由。
- [ ] 配置统一错误提示、loading 和空状态组件。

### 3.3 数据库迁移

- [ ] 创建 `users` 表。
- [ ] 创建 `api_keys` 表。
- [ ] 创建 `request_logs` 表。
- [ ] 创建 `balance_logs` 表。
- [ ] 添加 email、key prefix、request id、created_at 索引。
- [ ] 增加迁移回滚或本地重建说明。
- [ ] 创建管理员初始化 seed 方案。

## 4. 用户认证与审核

### 4.1 用户模型

用户状态：

```text
PENDING_REVIEW
ACTIVE
REJECTED
DISABLED
```

角色：

```text
USER
ADMIN
```

实现任务：

- [ ] 定义用户实体、Repository 和 Service。
- [ ] 密码使用 BCrypt 或 Argon2 hash。
- [ ] 禁止保存明文密码。
- [ ] 记录注册时间、更新时间、最近登录时间。
- [ ] 处理 email 唯一约束。

### 4.2 邮箱注册

- [ ] 实现邮箱格式校验。
- [ ] 实现密码长度和复杂度校验。
- [ ] 从 Apollo 读取邮箱后缀白名单。
- [ ] 非白名单邮箱拒绝注册。
- [ ] 重复邮箱拒绝注册。
- [ ] 注册成功后状态设为 `PENDING_REVIEW`。
- [ ] 不接入邮箱验证码和邮件服务。
- [ ] 返回等待管理员审核提示。

Apollo 配置示例：

```yaml
ai:
  auth:
    allowedEmailDomains:
      - example.com
      - company.com
```

### 4.3 登录与登录态

- [ ] 实现邮箱 + 密码登录。
- [ ] 只允许 `ACTIVE` 用户登录。
- [ ] 待审核、拒绝、禁用账号返回明确状态。
- [ ] 使用 HttpOnly Cookie 保存登录态。
- [ ] 配置 Secure、SameSite 和过期时间。
- [ ] 实现登出接口。
- [ ] 实现登录态失效处理。
- [ ] 所有受保护接口校验登录态。

### 4.4 管理员初始化

- [ ] 提供 Apollo 或环境变量管理员邮箱配置。
- [ ] 提供首次启动管理员 seed。
- [ ] 管理员密码不写入代码仓库。
- [ ] 管理员接口统一校验 `role = ADMIN`。

## 5. API Key 模块

### 5.1 API Key 生命周期

- [ ] 用户登录后自助创建 API Key。
- [ ] 支持自定义 key 名称。
- [ ] 生成高强度随机 key。
- [ ] 完整 key 只在创建成功时返回一次。
- [ ] 数据库只保存 key hash。
- [ ] 保存 key prefix 供列表识别。
- [ ] 支持用户查看 key 列表、状态和创建时间。
- [ ] 支持用户删除 key。
- [ ] 支持用户禁用和启用 key。
- [ ] 记录 `last_used_at`。

### 5.2 API Key 鉴权

实现统一鉴权组件：

```text
Authorization: Bearer sk-xxx
```

鉴权流程：

1. 提取 Bearer Token。
2. 根据 prefix 查询候选 key。
3. 对 token 做 hash 比对。
4. 检查 key 状态。
5. 检查用户状态。
6. 注入当前用户、key 和 request context。
7. 更新最近使用时间。

错误场景：

- [ ] 缺少 API Key。
- [ ] API Key 无效。
- [ ] API Key 已禁用。
- [ ] 用户未审核。
- [ ] 用户已禁用。

## 6. Apollo 与 Provider Adapter

### 6.1 Apollo 配置绑定

实现配置对象：

```text
AiProviderProperties
AiModelProperties
AiLimitProperties
AuthProperties
```

实现任务：

- [ ] 绑定 provider 配置。
- [ ] 绑定 model 配置。
- [ ] 绑定价格配置。
- [ ] 绑定超时、请求体大小和限流配置。
- [ ] 绑定邮箱后缀白名单。
- [ ] 校验 model 引用的 provider 是否存在。
- [ ] 校验 `baseUrl` 使用 HTTPS。
- [ ] 校验价格为非负数。
- [ ] 校验启用状态。
- [ ] 确认 Apollo 配置热加载或重启生效策略。

### 6.2 Provider 接口

定义：

```text
AiProviderClient
├─ chatCompletion()
├─ streamChatCompletion()
└─ listModels()
```

定义统一模型：

```text
ChatCompletionRequest
ChatCompletionResponse
ChatCompletionChunk
TokenUsage
ProviderError
```

### 6.3 OpenAI Compatible Provider

实现 `OpenAICompatibleProviderClient`：

- [ ] 非 stream 请求。
- [ ] stream 请求。
- [ ] public model 到 provider model 映射。
- [ ] 上游 Authorization 注入。
- [ ] 请求超时。
- [ ] 上游错误转换。
- [ ] 上游响应转 OpenAI-compatible 格式。
- [ ] request id 透传或重新生成。
- [ ] 不兼容 OpenAI 格式的供应商暂不实现。
- [ ] 不实现插件系统、复杂 SPI、可视化编排。

### 6.4 模型路由

```text
publicModel -> provider -> providerModel
```

示例：

```text
deepseek-chat
  -> siliconflow
  -> deepseek-ai/DeepSeek-V3
```

MVP 不做：

- [ ] 权重路由。
- [ ] 自动 failover。
- [ ] 多供应商重试。
- [ ] 健康检查自动摘除。
- [ ] 供应商/模型动态配置后台。

## 7. 网关 API

### 7.1 `POST /v1/chat/completions`

实现流程：

1. API Key 鉴权。
2. 请求体大小限制。
3. 请求参数校验。
4. 查找模型配置。
5. 检查用户状态。
6. 预扣额度。
7. 调用 Provider Adapter。
8. 返回 OpenAI-compatible 响应。
9. 记录 token、费用、耗时和状态。
10. 按实际 usage 或估算 usage 结算。

任务：

- [ ] 实现非 stream 请求。
- [ ] 校验 `model`、`messages` 和必要参数。
- [ ] 处理未知模型。
- [ ] 处理禁用模型。
- [ ] 处理 provider 未配置。
- [ ] 统一返回错误格式。

### 7.2 `GET /v1/models`

- [ ] 返回 Apollo 中启用的公开模型。
- [ ] 不返回上游 API Key。
- [ ] 不暴露不必要的内部配置。
- [ ] 禁用模型不出现在结果中。

### 7.3 Stream

- [ ] 读取上游 SSE/chunked 流。
- [ ] 转发给客户端。
- [ ] 正常结束时记录 usage。
- [ ] 上游异常时记录失败日志。
- [ ] 客户端中断时记录中断状态。
- [ ] usage 缺失时使用估算并标记。
- [ ] 设置最大 stream 执行时间。

## 8. 额度与扣费

### 8.1 基础规则

- [ ] 使用内部点数作为余额单位。
- [ ] 请求前检查额度。
- [ ] 管理员可增加或扣减余额。
- [ ] 每次余额变化写入流水。
- [ ] 每个请求关联余额流水。

### 8.2 并发防透支

采用 MySQL 事务 + 原子更新：

```sql
UPDATE users
SET balance = balance - :reservedAmount
WHERE id = :userId
  AND balance >= :reservedAmount;
```

实现任务：

- [ ] 余额不足时原子拒绝。
- [ ] 预扣成功后才调用上游。
- [ ] 请求完成后按实际成本多退少补。
- [ ] 失败请求释放预扣或正确结算。
- [ ] 余额流水和请求日志可追踪。
- [ ] 并发测试验证不会透支。

### 8.3 Token 与费用

- [ ] 优先使用上游返回 usage。
- [ ] usage 缺失时使用本地估算。
- [ ] 记录 `estimated_tokens = true`。
- [ ] 按 Apollo 模型价格计算费用。
- [ ] 记录输入 token、输出 token、总 token。

## 9. 请求日志与安全日志

### 9.1 `request_logs`

字段：

- `request_id`
- `user_id`
- `api_key_id`
- `key_prefix`
- `public_model`
- `provider`
- `provider_model`
- `status`
- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `estimated_tokens`
- `cost`
- `latency_ms`
- `error_code`
- `error_message`
- `created_at`

### 9.2 `balance_logs`

字段：

- `user_id`
- `amount`
- `balance_before`
- `balance_after`
- `type`
- `reason`
- `request_log_id`
- `created_at`

### 9.3 脱敏规则

- [ ] 不保存完整 prompt。
- [ ] 不保存完整 response。
- [ ] 不保存 Authorization。
- [ ] 不保存上游 API Key。
- [ ] 错误消息限长并脱敏。
- [ ] 保留错误类别、上游状态码和内部 request id。

## 10. 管理后台

### 10.1 管理接口

- [ ] `GET /admin/users`
- [ ] `POST /admin/users`
- [ ] `PATCH /admin/users/:id/status`
- [ ] `PATCH /admin/users/:id/balance`
- [ ] `GET /admin/api-keys`
- [ ] `PATCH /admin/api-keys/:id/status`
- [ ] `DELETE /admin/api-keys/:id`
- [ ] `GET /admin/request-logs`
- [ ] `GET /admin/stats/today`

### 10.2 用户审核

- [ ] 查看待审核用户。
- [ ] 审核通过。
- [ ] 拒绝注册并填写 reason。
- [ ] 禁用用户。
- [ ] 恢复用户。
- [ ] 审核后用户才能登录和调用 API。

### 10.3 Vue 页面

P0 页面：

- [ ] 注册页。
- [ ] 登录页。
- [ ] 待审核提示页。
- [ ] 用户 API Key 页面。
- [ ] 用户余额页面。
- [ ] 用户请求记录页面。
- [ ] 管理员用户列表。
- [ ] 管理员审核列表。
- [ ] 管理员额度调整页面。
- [ ] 管理员 API Key 管理页面。
- [ ] 管理员请求日志页面。
- [ ] 管理员今日统计页面。

统一交互：

- [ ] loading。
- [ ] empty。
- [ ] error。
- [ ] 表单校验。
- [ ] 提交中状态。
- [ ] 成功提示。
- [ ] 删除、禁用、调整额度二次确认。

## 11. 限流与基础安全

- [ ] 按 API Key 限制每分钟请求数。
- [ ] 限制请求体大小。
- [ ] 设置上游请求超时。
- [ ] 设置最大 stream 执行时间。
- [ ] 所有管理接口校验管理员角色。
- [ ] Cookie 使用 HttpOnly、Secure、SameSite。
- [ ] 生产环境只允许 HTTPS。
- [ ] Provider `baseUrl` 使用域名白名单。
- [ ] 拒绝 private、loopback、link-local、metadata 地址。
- [ ] 统一错误码，避免泄露内部信息。

Cloudflare 后续任务：

- [ ] WAF。
- [ ] IP 限制。
- [ ] DDoS 防护。
- [ ] 边缘限流。
- [ ] 管理后台额外访问保护。

## 12. 测试任务

### 12.1 Modulith

- [ ] 模块边界验证通过。
- [ ] 禁止跨模块访问内部实现。
- [ ] 检查模块依赖方向。

### 12.2 认证

- [ ] 合法邮箱注册。
- [ ] 非白名单邮箱拒绝。
- [ ] 重复邮箱拒绝。
- [ ] 密码 hash 不保存明文。
- [ ] 待审核用户无法登录。
- [ ] 审核通过后可以登录。
- [ ] 禁用用户无法登录。
- [ ] 登录态过期后需要重新登录。

### 12.3 API Key

- [ ] 创建 key 只返回一次完整值。
- [ ] 数据库只保存 hash。
- [ ] 有效 key 调用成功。
- [ ] 无效 key 被拒绝。
- [ ] 禁用 key 立即失效。
- [ ] 删除 key 后立即失效。

### 12.4 Provider

- [ ] OpenAI-compatible 非 stream 成功。
- [ ] OpenAI-compatible stream 成功。
- [ ] 模型映射正确。
- [ ] 未配置模型返回明确错误。
- [ ] 上游超时正确转换。
- [ ] 上游 4xx/5xx 正确转换。
- [ ] 上游错误日志不泄露 key 和请求内容。

### 12.5 额度

- [ ] 余额不足拒绝请求。
- [ ] 单请求扣费正确。
- [ ] 并发请求不会透支。
- [ ] 失败请求预扣能释放或正确结算。
- [ ] stream 中断会产生日志。
- [ ] usage 缺失时使用估算并标记。

### 12.6 管理后台

- [ ] 普通用户不能调用 `/admin/*`。
- [ ] 管理员可以审核用户。
- [ ] 管理员可以调整余额。
- [ ] 管理员可以禁用 key。
- [ ] 管理员可以查询日志。
- [ ] 管理员写操作具备 CSRF 或 Origin 防护。

## 13. 2-3 天排期

### Day 1：后端主链路

- [ ] 创建单仓库结构。
- [ ] 初始化 Spring Modulith。
- [ ] 接入 MySQL、Flyway、Apollo。
- [ ] 创建用户、key、日志、余额流水表。
- [ ] 完成注册和审核状态。
- [ ] 完成登录。
- [ ] 完成 API Key 创建和鉴权。
- [ ] 完成 Apollo 配置绑定。
- [ ] 完成 OpenAI-compatible Provider。
- [ ] 完成非 stream `/v1/chat/completions`。
- [ ] 完成基础日志和扣费。

验收：

- [ ] curl 或 OpenAI SDK 可以成功请求中转 API。
- [ ] 请求能转发到至少一个上游。
- [ ] 数据库能看到日志和扣费记录。

### Day 2：后台与可用性

- [ ] 完成 Vue 项目和路由。
- [ ] 完成注册、登录、待审核页面。
- [ ] 完成用户 API Key、余额、请求记录页面。
- [ ] 完成管理员用户审核页面。
- [ ] 完成额度调整、key 管理、请求日志页面。
- [ ] 完成限流、超时、请求体限制。
- [ ] 完成管理接口权限校验。
- [ ] 部署测试环境。

验收：

- [ ] 管理员能审核用户、发 key、充值额度。
- [ ] 管理员能禁用 key、查看日志。
- [ ] 用户能用 key 正常调用。
- [ ] 超额、禁用、错误模型都有明确错误返回。

### Day 3：stream 与上线兜底

- [ ] 完成 stream 转发。
- [ ] 完成 stream 日志和结算。
- [ ] 完成并发扣费防透支。
- [ ] 完成错误脱敏。
- [ ] 完成上游 URL 白名单。
- [ ] 完成核心集成测试。
- [ ] 完成线上 Apollo 配置。
- [ ] 完成数据库备份。
- [ ] 完成真实请求验证。
- [ ] 发布小范围内测。

## 14. 最终验收标准

- [ ] 注册邮箱属于 Apollo 白名单后缀。
- [ ] 新注册用户必须经过管理员审核。
- [ ] 审核通过用户可以正常登录。
- [ ] 用户可以自助创建和删除 API Key。
- [ ] 用户可以用 OpenAI SDK 调用 `/v1/chat/completions`。
- [ ] 至少一个 OpenAI-compatible 上游可以通过 Apollo 配置接入。
- [ ] 非 stream 和 stream 均可正常调用。
- [ ] 请求日志、token、费用、错误、耗时可查询。
- [ ] 余额不足和并发请求不会导致明显超额。
- [ ] 管理员可以审核用户、调整额度、禁用 key。
- [ ] 不接入 Cloudflare 也不影响 MVP 上线。

## 15. 明确不做

- [ ] 邮箱验证码或验证邮件。
- [ ] 在线支付。
- [ ] 复杂套餐。
- [ ] 供应商/模型动态配置后台。
- [ ] 多上游自动 failover。
- [ ] 权重路由和测速排序。
- [ ] 用户组织和企业权限。
- [ ] 完整审计系统。
- [ ] Prompt 审核和内容安全策略。
- [ ] Cloudflare 集成。
