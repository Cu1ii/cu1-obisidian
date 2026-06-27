# 验证：Apollo

> 部署位置：`~/fyj-server/compose/apollo.yml`
> 三组件：`infra-apollo-config` (8080) / `infra-apollo-admin` (8090) / `infra-apollo-portal` (8070)
> 数据库：复用 `infra-mysql`，需先导入 `apolloconfigdb` + `apolloportaldb`

## 1. 容器状态

```bash
cd ~/fyj-server/compose
docker compose -f apollo.yml ps
```

三个 service 均 `Up`，config + admin 期望 `(healthy)`。

## 2. 启动日志

```bash
docker compose -f apollo.yml logs --tail=80 apollo-config
docker compose -f apollo.yml logs --tail=80 apollo-admin
docker compose -f apollo.yml logs --tail=80 apollo-portal
```

关键：`Started ConfigServiceApplication` / `Started AdminServiceApplication` / `Started PortalApplication`。

## 3. 端口绑定

```bash
lsof -nP -iTCP:8070 -sTCP:LISTEN
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:8090 -sTCP:LISTEN
```

均应 `127.0.0.1`。

## 4. 健康检查端点

```bash
curl -s http://127.0.0.1:8080/health        # config
curl -s http://127.0.0.1:8090/health        # admin
curl -s http://127.0.0.1:8070/health        # portal
```

期望 JSON 含 `"status":"UP"`。

## 5. Eureka 注册状态

```bash
curl -s http://127.0.0.1:8080/eureka/apps | head -40
```

应见 `APOLLO-CONFIGSERVICE` 与 `APOLLO-ADMINSERVICE` 注册条目。

## 6. 数据库连通

```bash
docker exec -it infra-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SHOW DATABASES LIKE 'Apollo%';
USE ApolloConfigDB; SHOW TABLES;
USE ApolloPortalDB; SHOW TABLES;"
```

每库均应有几十张表（`App`、`Cluster`、`Item` 等）。

## 7. Portal 登录

浏览器访问 `http://127.0.0.1:8070`，账号 `apollo / admin`。登录后立即改密码（管理员 → 用户管理）。

## 8. 跨容器连通

```bash
docker run --rm --network infra-net curlimages/curl \
  curl -s http://infra-apollo-config:8080/health
```

## 一键速查

```bash
for p in 8070 8080 8090; do
  echo -n "port $p: "
  curl -fs "http://127.0.0.1:$p/health" >/dev/null && echo OK || echo FAIL
done
```

> Apollo 启动慢，三组件冷启需 1-2 分钟。等到 admin 注册进 Eureka，portal 才能正常显示集群。
