# 验证：Elasticsearch

> 部署位置：`~/fyj-server/compose/es.yml`
> 容器名：`infra-es`

## 1. 容器状态

```bash
cd ~/fyj-server/compose
docker compose -f es.yml ps
```

期望 `Up (healthy)`。

## 2. 启动日志

```bash
docker compose -f es.yml logs --tail=80 es | grep -iE "started|error|cluster"
```

关键行：`started` + `cluster.name`。

## 3. 端口绑定

```bash
lsof -nP -iTCP:9200 -sTCP:LISTEN
```

应见 `127.0.0.1:9200`。

## 4. 版本与集群健康

```bash
curl -s http://127.0.0.1:9200 | head -20
curl -s http://127.0.0.1:9200/_cluster/health?pretty
```

`status` 单节点期望 `green` 或 `yellow`（yellow 因副本无处分配，本地正常）。

## 5. 节点信息

```bash
curl -s http://127.0.0.1:9200/_cat/nodes?v
curl -s http://127.0.0.1:9200/_cat/indices?v
```

## 6. 写入/查询测试

```bash
curl -s -XPOST http://127.0.0.1:9200/verify/_doc -H 'Content-Type: application/json' \
  -d '{"msg":"hello","ts":"2026-06-12"}'

curl -s 'http://127.0.0.1:9200/verify/_search?pretty'
```

清理：

```bash
curl -s -XDELETE http://127.0.0.1:9200/verify
```

## 7. 跨容器连通

```bash
docker run --rm --network infra-net curlimages/curl \
  curl -s http://infra-es:9200/_cluster/health?pretty
```

## 8. 数据目录落地

```bash
ls -la ~/fyj-server/infra/es/data/ | head
```

应见 `nodes/` 子目录。

## 9. JVM 堆内存

```bash
docker exec infra-es bash -c 'cat /proc/1/cmdline | tr "\0" " " ; echo' | tr ' ' '\n' | grep -E "^-Xm[sx]"
```

确认 yml 里 `ES_JAVA_OPTS=-Xms2g -Xmx2g` 真生效。

## 一键速查

```bash
cd ~/fyj-server/compose
docker compose -f es.yml ps
curl -fs http://127.0.0.1:9200/_cluster/health | python3 -m json.tool
```

> 启用安全（xpack.security.enabled=true）后，curl 需带 `-u elastic:<密码>`。本方案默认开发环境关闭安全模块。
