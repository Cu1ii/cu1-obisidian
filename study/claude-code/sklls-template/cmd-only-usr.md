---
name: deploy
description: 部署到生产环境
disable-model-invocation: true (对于带副作用、Claude 不应自动触发的命令)：
allowed-tools: Bash(npm *), Bash(git *)
---

将应用部署到生产环境：

1. 运行测试
2. 构建应用
3. 推送到部署目标
4. 验证部署