# 验证：Kafka（KRaft 单节点）

> 部署位置：`~/fyj-server/compose/kafka.yml`
> 容器名：`infra-kafka`
> 模式：KRaft（无 Zookeeper），单节点同时为 broker + controller

## 1. 容器状态

```bash
cd ~/fyj-server/compose
docker compose -f kafka.yml ps
```

期望 `Up (healthy)`。

## 2. 启动日志

```bash
docker compose -f kafka.yml logs --tail=80 kafka | grep -iE "started|kafkaserver|error"
```

关键行：`[KafkaServer id=1] started` 或 `Kafka Server started`。

## 3. 端口绑定

```bash
lsof -nP -iTCP:9094 -sTCP:LISTEN
```

应见 `127.0.0.1:9094`。9092/9093 仅容器内监听，不暴露宿主。

## 4. 列 broker / topic（容器内）

```bash
docker exec -it infra-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092
docker exec -it infra-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## 5. 创建/读写测试 topic

```bash
docker exec -it infra-kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --topic verify-test --partitions 1 --replication-factor 1

# 生产
docker exec -i infra-kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic verify-test <<< 'hello'

# 消费（Ctrl+C 退出）
docker exec -it infra-kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic verify-test --from-beginning --max-messages 1
```

读到 `hello` = 通过。

清理：

```bash
docker exec -it infra-kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic verify-test
```

## 6. 跨容器连通

```bash
docker run --rm --network infra-net apache/kafka:4.3.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server infra-kafka:9092 | head -5
```

## 7. 宿主连通（EXTERNAL listener）

宿主开发工具走 `localhost:9094`，需装 kafka 客户端或直接用 docker 一次性容器：

```bash
docker run --rm apache/kafka:4.3.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server host.docker.internal:9094 | head -5
```

> OrbStack/Docker Desktop 的 `host.docker.internal` 指向宿主。

## 8. 网络归属

```bash
docker network inspect infra-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep infra-kafka
```

## 一键速查

```bash
cd ~/fyj-server/compose
docker compose -f kafka.yml ps
docker exec infra-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null && echo OK
```

> KRaft 单节点常见坑：`KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093` 中 `localhost` 指容器自身，不是宿主。`CLUSTER_ID` 首次启动写入 `meta.properties`，后续不能改，否则启动失败需删数据卷。
