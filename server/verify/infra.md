# 验证：Infra（MySQL + Redis）

> 部署位置：`~/fyj-server/compose/infra.yml`

## 1. 容器状态

```bash
cd ~/fyj-server/compose
docker compose -f infra.yml ps
```

期望输出两行 `Up` + `(healthy)`：

```
NAME           STATUS                   PORTS
infra-mysql    Up X minutes (healthy)   127.0.0.1:3306->3306/tcp
infra-redis    Up X minutes (healthy)   127.0.0.1:6379->6379/tcp
```

未 healthy：等 30s 再看（healthcheck 启动慢）。仍 unhealthy → 看日志。

## 2. 启动日志

```bash
docker compose -f infra.yml logs --tail=50 mysql
docker compose -f infra.yml logs --tail=50 redis
```

- MySQL 关键行：`ready for connections`
- Redis 关键行：`Ready to accept connections`

## 3. 端口绑定（必须 127.0.0.1）

```bash
lsof -nP -iTCP:3306 -sTCP:LISTEN
lsof -nP -iTCP:6379 -sTCP:LISTEN
```

应只见 `127.0.0.1:3306` / `127.0.0.1:6379`，**无** `*:3306`。出现 `*:` → 端口绑全网卡，整改未生效，回看 `infra.yml` `ports:` 是否为 `"127.0.0.1:3306:3306"`。

## 4. MySQL 连通

容器内：

```bash
docker exec -it infra-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES; SELECT VERSION();"
```

宿主（需 `brew install mysql-client`）：

```bash
mysql -h 127.0.0.1 -P 3306 -uroot -p -e "SELECT 1;"
```

跨容器（验证 `infra-net`）：

```bash
docker run --rm --network infra-net mysql:8.0.46 \
  mysql -h infra-mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;"
```

## 5. Redis 连通

容器内：

```bash
docker exec -it infra-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping
# 期望：PONG

docker exec -it infra-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning info server | grep redis_version
```

跨容器：

```bash
docker run --rm --network infra-net redis:7.4.9-alpine \
  redis-cli -h infra-redis -a "$REDIS_PASSWORD" --no-auth-warning ping
```

## 6. 无密码必须拒绝

```bash
docker exec -it infra-redis redis-cli ping
# 期望：(error) NOAUTH Authentication required.
```

`PONG` 出来 = 密码没生效，立刻查 `.env` 与 logs。

## 7. 数据目录落地

```bash
ls -la ~/fyj-server/infra/mysql/data/ | head
ls -la ~/fyj-server/infra/redis/data/ | head
```

mysql 应有 `mysql/`、`ibdata1`、`ib_logfile*` 等。redis 启动后写入才有 `appendonly.aof` / `dump.rdb`。

## 8. healthcheck 详情

```bash
docker inspect --format='{{json .State.Health}}' infra-mysql | python3 -m json.tool
docker inspect --format='{{json .State.Health}}' infra-redis | python3 -m json.tool
```

看 `Status` + 最近 `Log` 条目定位失败原因。

## 9. 网络归属

```bash
docker network inspect infra-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'
```

输出应同时含 `infra-mysql` 与 `infra-redis`（顺序不固定）。缺谁查谁的 yml 是否声明 `networks: [infra-net]` + 顶层 `external: true`。

## 一键速查

```bash
cd ~/fyj-server/compose
docker compose -f infra.yml ps
docker exec infra-mysql mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping
docker exec infra-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping
```

三行全绿 = 通过。

> 注：`$MYSQL_ROOT_PASSWORD` / `$REDIS_PASSWORD` 是宿主 shell 是否 export 决定，未 export 直接填密码字面值。
