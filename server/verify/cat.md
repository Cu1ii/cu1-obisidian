# 验证：CAT

> 部署位置：`~/fyj-server/compose/cat.yml`
> 基础镜像：`meituaninc/cat:3.0.1`（dianping/cat 社区维护之官方 docker 镜像）
> 本地构建镜像：`infra-cat:3.0.1-mysql8`（替换 driver 为 mysql-connector-java 5.1.49 以兼容 MySQL 8）
> 容器名：`infra-cat`
> 端口映射：`2281:8080`（HTTP/UI）、`2280:2280`（TCP 上报）
> 数据库：复用 `infra-mysql`，需先建 `cat` 库并导入 `Cat.sql`
> 关键 .env：
> - `MYSQL_ROOT_PASSWORD`
> - `CAT_SERVER_IP`：CAT 服务对外暴露之 host LAN IP（外部浏览器/远程客户端走此地址）
> - `CAT_CONTAINER_IP`：CAT 容器在 `infra-net` 上之静态 IP（监控身份，须落在 infra-net subnet 内）

## 0. 镜像构建（首次或 Dockerfile/jar 变更后）

官方 `meituaninc/cat:3.0.1` 内置 mysql-connector-java 5.1.20，不识别 MySQL 8 之 `serverTimezone` / `allowPublicKeyRetrieval` 等参数；c3p0 报 `CannotAcquireResourceException` 且吞掉真因。

直接换 8.x driver 又会触发 unidal DAL 与 `LocalDateTime` 反射类型不匹配（`required: java.util.Date, but: java.time.LocalDateTime`）。

故：用 `cat.Dockerfile` 灌入 5.1.49（最后 5.1 版，兼容 MySQL 8 之 `mysql_native_password` + 仍返 `java.sql.Timestamp`）。

```bash
cd ~/fyj-server/compose
ls cat.Dockerfile mysql-connector-java-5.1.49.jar    # 文件存在
docker compose -f cat.yml build cat
docker images | grep infra-cat                       # 应见 infra-cat:3.0.1-mysql8
```

## 1. 容器状态

```bash
cd ~/fyj-server/compose
docker compose -f cat.yml ps
```

期望 `Up`。镜像无内置 healthcheck，靠 HTTP 探测代替。

## 2. 启动日志

```bash
docker compose -f cat.yml logs --tail=200 cat | grep -iE "started|tomcat|error|caused by"
```

关键行：

- `Loading class com.mysql.jdbc.Driver. ... new driver class is com.mysql.cj.jdbc.Driver` → 5.1.49 driver 在路径上（deprecation warning 正常忽略）
- `Server startup in NNNN ms` → Tomcat 启动完成（5.1.49 下约 10s；若仍 80s+ 说明 c3p0 在重试）
- 不应见 `CannotAcquireResourceException` / `LocalDateTime` / `TcpSocketReceiver` lookup fail

## 3. 端口绑定

```bash
lsof -nP -iTCP:2281 -sTCP:LISTEN
lsof -nP -iTCP:2280 -sTCP:LISTEN
```

`cat.yml` 暴露 `0.0.0.0`，故应见 `*:2281` 与 `*:2280`。LAN 其他机器可达。

## 4. HTTP 探活

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:2281/cat
# 期望：200 或 302
```

浏览器访问 `http://127.0.0.1:2281/cat` 或 `http://<CAT_SERVER_IP>:2281/cat`，看到登录或首页 = 通过。
默认管理员账号：`admin / admin`。

## 5. 配置文件挂载

```bash
docker exec infra-cat ls /data/appdatas/cat/
# 期望见：client.xml、datasources.xml
```

- `client.xml` 由宿主 `${SERVER_ROOT}/infra/cat/conf/client.xml` bind mount，CAT 自监控 SDK 读
- `datasources.xml` 由宿主 `${SERVER_ROOT}/infra/cat/conf/datasources.xml` bind mount（**覆盖镜像内 entrypoint 之 sed 渲染产物**，便于调 `connection-timeout` / `useSSL=false` / `serverTimezone` 等）

> 注：cat.yml 之 `command:` 已 override 原 entrypoint，原 `datasources.sh` / `client.sh` 不再跑；
> `MYSQL_URL` / `SERVER_IP` 等 env 仅做兜底参考，实际生效靠两份手挂 xml。

```bash
docker exec infra-cat cat /data/appdatas/cat/datasources.xml | grep -E "url|user|driver"
```

确认：
- `<driver>com.mysql.jdbc.Driver</driver>`（CAT 用旧类名，5.1.49 与 8.x 都兼容）
- `<url>` 含 `useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai`

```bash
docker exec infra-cat cat /data/appdatas/cat/client.xml
```

确认 `<server ip="${CAT_CONTAINER_IP}" port="2280" http-port="8080"/>`，**不再是 127.0.0.1**（127.0.0.1 会触发 dashboard 红字告警「出问题CAT的服务端」）。

## 6. 数据库连通

```bash
set -a; source ~/fyj-server/compose/.env; set +a
docker exec -it infra-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SHOW DATABASES LIKE 'cat';
USE cat; SHOW TABLES;"
```

期望见 `app`、`alteration`、`config` 等表。

## 7. 日志目录落地

```bash
ls -la ~/fyj-server/infra/cat/logs/
docker exec infra-cat ls /data/applogs/cat/
```

启动后应陆续生成日志文件（`cat_YYYYMMDD.log`），宿主与容器两侧同步可见（bind mount）。

排查 c3p0 / DAL 反射等吞异常时直接读宿主 log 文件比 `docker logs` 完整：

```bash
tail -200 ~/fyj-server/infra/cat/logs/cat_$(date +%Y%m%d).log
```

## 8. 跨容器连通

CAT 容器内 HTTP 端口 = `8080`（宿主 2281 是映射后端口）。infra-net 内业务容器三种上报方式都通：

```bash
# 走 docker DNS（推荐，跨网段无关）
docker run --rm --network infra-net curlimages/curl \
  curl -s -o /dev/null -w "%{http_code}\n" http://infra-cat:8080/cat

# 走静态 IP
docker run --rm --network infra-net curlimages/curl \
  curl -s -o /dev/null -w "%{http_code}\n" http://${CAT_CONTAINER_IP}:8080/cat
```

TCP 上报口仍 2280：

```bash
docker run --rm --network infra-net busybox \
  sh -c "nc -zv infra-cat 2280"
```

## 9. 容器静态 IP 一致性

CAT 之 `NetworkInterfaceManager` 启动时扫 NIC 取首个非 loopback IPv4 作为「自身上报 IP」。
钉死 `CAT_CONTAINER_IP` 让此 IP 跨 recreate 稳定；同步在 `routerConfig` / `client.xml` 注册同 IP，dashboard 才不报「出问题CAT的服务端:[X]」。

```bash
docker inspect infra-cat | grep '"IPAddress"' | head -3
# 期望首个非空值 = CAT_CONTAINER_IP
```

```bash
docker compose -f cat.yml exec cat sh -c \
  'wget -qO- "http://127.0.0.1:8080/cat/s/router?domain=cat&op=json" 2>/dev/null | head -c 400'
```

返回 JSON 之 `routers` 字段含 `${CAT_CONTAINER_IP}:2280`。

## 10. routerConfig 一致性

CAT 自带「server cluster routing」配置，存于 MySQL `cat.config` 表，内容为 XML。须确保 4 处 IP 全部 = `CAT_CONTAINER_IP`：

- `<router-config backup-server="...">`
- `<default-server id="...">`
- `<server-group> <group-server id="...">`
- `<domain id="cat"> <group> <server id="...">`

UI 路径：右上 `Star` → 登录（`admin / admin`）→ Configs → Router Config，或直接：

```
http://<CAT_SERVER_IP>:2281/cat/s/config?op=routerConfigUpdate
```

或 SQL 查：

```bash
set -a; source ~/fyj-server/compose/.env; set +a
docker exec -it infra-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
USE cat;
SELECT content FROM config WHERE name='routerConfig'\G"
```

修改后点「重算路由」立刻生效；否则等 `Cat-ConfigSyncTask` 1 分钟轮询。

## 一键速查

```bash
cd ~/fyj-server/compose
docker compose -f cat.yml ps
curl -fs -o /dev/null -w "cat http: %{http_code}\n" http://127.0.0.1:2281/cat
docker inspect infra-cat | grep '"IPAddress"' | head -3
docker exec infra-cat ls /data/appdatas/cat/
```

## 排错

启动循环重启或 dashboard 异常，按概率序：

1. **`cat` 库不存在或 `Cat.sql` 未导入** → log 见 `Unknown database 'cat'` 或 `Table 'cat.xxx' doesn't exist`。
2. **MySQL 密码错配** → log 见 `Access denied for user 'root'`。校验 `.env` 之 `MYSQL_ROOT_PASSWORD` 与 `infra-mysql` 启动密码一致。
3. **driver 版本不对** → log 见 `CannotAcquireResourceException`（无下游 caused by）→ 5.1.20 与 MySQL 8 不兼容；rebuild 镜像并确认 `mysql-connector-java-5.1.49.jar` 在 build context。
4. **driver 太新** → log 见 `argument type mismatch ... required: java.util.Date, but: java.time.LocalDateTime` → 用 8.x driver 不兼容 unidal DAL，必须 5.1.49。
5. **`CAT_SERVER_IP` / `CAT_CONTAINER_IP` 未设** → compose 启动直接报 `need ... in .env`。
6. **`CAT_CONTAINER_IP` 不在 infra-net subnet 内 / 已被占用** → `docker compose up` 报 `Address already in use` 或 `invalid argument`。先 `docker network inspect infra-net | grep -A4 IPAM` 确认 subnet。
7. **`client.xml` / `datasources.xml` 路径是目录非文件**（首次 up 前未建文件，Docker 自动建占位目录）→ 删该目录，建文件，再 `up`。
8. **dashboard 红字「出问题CAT的服务端:[X]」** → routerConfig 4 处 IP 与容器实际 IP 未全部对齐；按 §10 修。
9. **2281/2280 端口被占** → `lsof -nP -iTCP:2281 -sTCP:LISTEN`，释放或改 `cat.yml` 端口映射。

详细日志：`~/fyj-server/infra/cat/logs/cat_$(date +%Y%m%d).log`（容器内 stack trace 完整版）。
