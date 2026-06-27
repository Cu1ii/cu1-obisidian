# 验证：全栈一键自检

> 跑完全部 Phase 后做整体检查。各组件细节看 `infra.md` / `kafka.md` / `es.md` / `apollo.md` / `cat.md`。

## 1. 全部容器健康

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

应见 `infra-mysql` / `infra-redis` / `infra-kafka` / `infra-es` / `infra-apollo-config` / `infra-apollo-admin` / `infra-apollo-portal` / `infra-cat` 全部 `Up`，关键服务 `(healthy)`。

## 2. 网络归属

```bash
docker network inspect infra-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'
```

应列出所有 `infra-*` 容器。

## 3. 端口暴露面（必须全 127.0.0.1）

```bash
docker ps --format '{{.Names}}\t{{.Ports}}' | grep -v "127.0.0.1"
```

输出应**为空**（除 docker 内部端口）。出现 `0.0.0.0:` → 该容器 yml 端口未绑环回，立即整改。

## 4. 端到端速查

```bash
# MySQL
docker exec infra-mysql mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping

# Redis
docker exec infra-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping

# Kafka
docker exec infra-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null && echo "kafka OK"

# ES
curl -fs http://127.0.0.1:9200/_cluster/health >/dev/null && echo "es OK"

# Apollo
for p in 8070 8080 8090; do
  curl -fs "http://127.0.0.1:$p/health" >/dev/null && echo "apollo:$p OK" || echo "apollo:$p FAIL"
done

# CAT
curl -fs -o /dev/null -w "cat http: %{http_code}\n" http://127.0.0.1:2281/cat
```

全 OK = 整个 infra 栈就绪。

## 5. 资源占用

```bash
docker stats --no-stream --format \
  "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

总内存对照 `init.md` 资源预估表（~8-12G）。超出明显需排查。

## 6. 数据卷落地

```bash
du -sh ~/fyj-server/infra/*
```

每个中间件数据目录均应非 0。

## 7. 业务容器接入冒烟

新建临时容器加入 `infra-net`，测全部中间件可达：

```bash
docker run --rm -it --network infra-net alpine sh -c '
apk add --no-cache curl mysql-client redis bind-tools >/dev/null
nslookup infra-mysql
nslookup infra-redis
nslookup infra-kafka
nslookup infra-es
nslookup infra-apollo-config
nslookup infra-cat
'
```

每条 `nslookup` 都应解析到 infra-net 内 IP。
