# 本地局域网开发服务器部署方案 — 初始版

> Mac（Intel i7 / 32G / 1T SSD）改造为本地独立开发服务器
> 底座：OrbStack + Docker Compose
> 中间件：MySQL、Redis、Kafka、Elasticsearch、Apollo、CAT
> 版本：init（首次部署），后续架构升级另起文件（如 `v2-xxx.md`）

## 目录结构

```
~/fyj-server/
├── init.md                  # 本文件
├── verify/                  # 各组件验证清单
│   ├── infra.md
│   ├── kafka.md
│   ├── es.md
│   ├── apollo.md
│   ├── cat.md
│   └── all.md
├── infra/                   # 中间件数据卷
│   ├── mysql/
│   │   ├── data/
│   │   ├── conf/
│   │   └── init/            # 初始化 SQL
│   ├── redis/
│   ├── kafka/
│   ├── es/
│   ├── apollo/
│   └── cat/
│       ├── conf/
│       └── logs/
├── apps/                    # 业务项目数据
├── compose/                 # 所有 docker-compose.yml
│   ├── infra.yml
│   ├── kafka.yml
│   ├── es.yml
│   ├── apollo.yml
│   └── cat.yml
└── scripts/                 # 备份/运维脚本
    └── backup.sh
```

## 设计原则

- **OrbStack** 替代 Docker Desktop，省内存、原生网络。
- **统一 `infra-net` 桥接网络**：业务容器加入即可用容器名访问中间件。
- **绑定挂载**优先于 Docker 命名卷：所有数据落 `~/fyj-server/` 下，便于备份/迁移/清理。
- **路径用 `${SERVER_ROOT}` 注入**：yml 内不写 `~`（Compose 不展开），由 shell env 或 `.env` 注入绝对路径。
- **密码强制**：MySQL、Redis、Apollo 全强密码，写入 `.env`，不进 yml、不进 git。
- **关自动更新检查**：避免遥测/外联。Mac 防火墙（Lulu）拦非必要出站。

## 路径约定

文档中三种写法各有上下文，不可混淆：

| 上下文 | 写法 | 谁解析 |
|---|---|---|
| 终端命令（mkdir / cd / docker compose -f） | `~/fyj-server/...` | shell 展开 `~` |
| Compose yml 内挂载/路径 | `${SERVER_ROOT}/...` | Compose 插值，**不展开 `~` 也不展开 `$HOME`** |
| `.env` 文件值 | `/Users/xxx/fyj-server`（绝对路径，字面字符串） | dotenv 读取，**不展开任何变量** |

`SERVER_ROOT` 注入两种推荐方式：

**方式 A：shell export（跨机移植）**

```bash
echo 'export SERVER_ROOT="$HOME/fyj-server"' >> ~/.zshrc
source ~/.zshrc
```

之后 `docker compose -f ~/fyj-server/compose/infra.yml up -d` 自动读取 `SERVER_ROOT`，无需 `.env` 写此项。

**方式 B：.env 字面绝对路径（机器固定）**

```dotenv
# compose/.env
SERVER_ROOT=/Users/fyj/fyj-server
TZ=Asia/Shanghai
MYSQL_ROOT_PASSWORD=请改成强密码至少16位
REDIS_PASSWORD=请改成强密码至少16位
```

> `.env` **不展开** `~` 或 `$HOME`，必须写绝对路径。完整字段见 `compose/.env.example`。

Compose 读取顺序：**shell env > `.env` 文件**。两者都设以 shell 为准。

## 资源预估

| 组件 | 内存 |
|------|------|
| ES | 2-4G |
| Kafka + Zookeeper | 1-2G |
| CAT | 1-2G |
| Apollo（三组件） | 1-2G |
| MySQL | 0.5-1G |
| Redis | 几百 M |
| **合计** | **~8-12G** |

32G 机器跑满中间件后，剩余 18-22G 可用于业务容器与开发工具。

## 部署阶段

### Phase 0：准备

```bash
sw_vers                # 系统版本，建议 13+
uname -m               # arm64 / x86_64
```

如已装 Docker Desktop，关闭其登录项启动，避免与 OrbStack 抢端口。

### Phase 1：装 OrbStack

```bash
brew install --cask orbstack
# 或 https://orbstack.dev/download

# 启动
open -a OrbStack
```

启动并完成引导，验证：

```bash
docker version
docker compose version
```

### Phase 2：建目录骨架

```bash
mkdir -p ~/fyj-server/{apps,compose,scripts}
mkdir -p ~/fyj-server/infra/{redis/data,kafka,apollo}
mkdir -p ~/fyj-server/infra/mysql/{data,conf,init}
mkdir -p ~/fyj-server/infra/es/data
mkdir -p ~/fyj-server/infra/cat/{conf,logs}
```

### Phase 3：注入 SERVER_ROOT 与配 .env

任选方式 A 或 B（见上文「路径约定」）。下方按方式 A 演示：

```bash
echo 'export SERVER_ROOT="$HOME/fyj-server"' >> ~/.zshrc
source ~/.zshrc
echo "$SERVER_ROOT"      # 应输出 /Users/<你>/fyj-server
```

把仓库 `compose/` 下所有 yml 与 `.env.example` 拷到 `~/fyj-server/compose/`：

```bash
cp /path/to/repo/server/compose/*.yml      ~/fyj-server/compose/
cp /path/to/repo/server/compose/.env.example ~/fyj-server/compose/.env
# chmod 600 ~/fyj-server/compose/.env
# 编辑 .env，填强密码
```

> `.env` 必须放 **执行 docker compose 命令的当前目录**。本方案统一在 `~/fyj-server/compose/` 下执行（见各 Phase）。

### Phase 4：建外部网络

```bash
docker network create infra-net
docker network ls | grep infra-net
```

### Phase 5：起 Infra（MySQL + Redis）

```bash
cd ~/fyj-server/compose
docker compose -f infra.yml up -d
docker compose -f infra.yml ps
```

→ 详细验证：[verify/infra.md](verify/infra.md)

### Phase 6：起 Kafka（KRaft 模式，单节点）

```bash
cd ~/fyj-server/compose
docker compose -f kafka.yml up -d
```

> Apache Kafka 3.5 起支持 KRaft（Kafka Raft）取代 Zookeeper，4.x 默认仅支持 KRaft。本方案单节点同时担任 broker + controller，**无 Zookeeper 服务**。

→ 详细验证：[verify/kafka.md](verify/kafka.md)

### Phase 7：起 ES

```bash
cd ~/fyj-server/compose
docker compose -f es.yml up -d
curl http://localhost:9200    # 看版本号即成功
```

→ 详细验证：[verify/es.md](verify/es.md)

### Phase 8：起 Apollo

> 版本：**v2.5.1**（2025-03-14，截至本文档撰写时的最新稳定版）。如需升级请去 [apolloconfig/apollo releases](https://github.com/apolloconfig/apollo/releases) 看新 tag。

#### 8.1 下载官方 SQL

Apollo 仓库 SQL 路径：[scripts/sql/profiles](https://github.com/apolloconfig/apollo/tree/v2.5.1/scripts/sql/profiles)。v2.5.0 起 profile 目录改名，三套：

- `mysql-default` — 默认 utf8mb4，**本方案选这个**
- `mysql-database-not-specified` — 不指定 database 名，多租户用
- `h2-default` — H2 内存库，仅测试

```bash
APOLLO_REF=v2.5.1
SQL_BASE="https://raw.githubusercontent.com/apolloconfig/apollo/${APOLLO_REF}/scripts/sql/profiles/mysql-default"

cd ~/fyj-server/infra/mysql/init
curl -fsSL -o apolloconfigdb.sql "${SQL_BASE}/apolloconfigdb.sql"
curl -fsSL -o apolloportaldb.sql "${SQL_BASE}/apolloportaldb.sql"
ls -la apolloconfigdb.sql apolloportaldb.sql
```

#### 8.2 导入到 MySQL（本地 mysql-cli）

`/docker-entrypoint-initdb.d` 仅在 MySQL **数据目录为空**时首次启动自动执行。本方案 MySQL 已起，需手动导入。

**前置：装 mysql 客户端**

```bash
brew install mysql-client
# 让 mysql 命令进 PATH（zsh）
echo 'export PATH="/usr/local/opt/mysql-client/bin:$PATH"' >> ~/.zshrc   # Intel Mac
# 或 echo 'export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"' >> ~/.zshrc   # Apple Silicon
source ~/.zshrc
mysql --version
```

**导入**

`infra.yml` 已把 MySQL 端口绑定 `127.0.0.1:3306`，本机直连即可：

```bash
cd ~/fyj-server/compose
set -a; source .env; set +a       # 把 .env 注入当前 shell

# MYSQL_PWD 走环境变量，避免 -p<密码> 在 ps/历史里留明文
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h 127.0.0.1 -P 3306 -uroot \
  < ~/fyj-server/infra/mysql/init/apollo/apolloconfigdb.sql

MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h 127.0.0.1 -P 3306 -uroot \
  < ~/fyj-server/infra/mysql/init/apollo/apolloportaldb.sql
```

> 若 brew 装的 mysql-client 报 SSL 协议不匹配（`SSL connection error`），追加 `--ssl-mode=DISABLED`：本机回环连接，不影响安全。

> 若想走自动导入：先 `docker compose -f infra.yml down` → `rm -rf ~/fyj-server/infra/mysql/data/*` → 把 sql 放好 → 再 `up -d`。**会清空 MySQL 数据**，确认无业务数据再操作。

#### 8.3 验证导入

```bash
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h 127.0.0.1 -P 3306 -uroot -e "
SHOW DATABASES LIKE 'Apollo%';
SELECT COUNT(*) AS config_tables  FROM information_schema.tables WHERE table_schema='ApolloConfigDB';
SELECT COUNT(*) AS portal_tables  FROM information_schema.tables WHERE table_schema='ApolloPortalDB';
SELECT \`Key\`, \`Value\` FROM ApolloConfigDB.ServerConfig;
SELECT \`Key\`, \`Value\` FROM ApolloPortalDB.ServerConfig;
"
```

期望（v2.5.1）：

- `ApolloConfigDB` 19 张表
- `ApolloPortalDB` 18 张表
- `ApolloConfigDB.ServerConfig` 至少一条 `eureka.service.url`
- `ApolloPortalDB.ServerConfig` 至少一条 `apollo.portal.envs`

#### 8.4 改关键配置

Apollo 多组件互联走 Eureka，启动前必须把 `eureka.service.url` 改成容器名地址（默认是 localhost，跨容器不可达）：

```bash
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h 127.0.0.1 -P 3306 -uroot -e "
USE ApolloConfigDB;
UPDATE ServerConfig
SET    \`Value\`='http://infra-apollo-config:8080/eureka/'
WHERE  \`Key\`='eureka.service.url';

SELECT \`Key\`, \`Value\` FROM ServerConfig WHERE \`Key\`='eureka.service.url';
"
```

> Portal 多环境（DEV/FAT/UAT/PRO）地址通常通过 apollo-portal 容器的环境变量 `APOLLO_PORTAL_ENVS` 与 `<ENV>_META` 传递，**不改 SQL**。具体看 `apollo.yml` 的 environment 段。

#### 8.5 启动

```bash
cd ~/fyj-server/compose
docker compose -f apollo.yml up -d
docker compose -f apollo.yml ps
```

三组件冷启 1-2 分钟，等到 admin 注册进 Eureka，portal 才能正常显示集群。

访问 `http://localhost:8070`，默认账号 `apollo / admin`。登录后立即改密码（管理员 → 用户管理）。

→ 详细验证：[verify/apollo.md](verify/apollo.md)

### Phase 9：起 CAT

CAT 镜像需自行 build（参考 `Cu1ii/cat` 仓库 `Dockerfile`），或用社区镜像。

**初始化 SQL：** 仓库 `script/Cat.sql` → 放 `~/fyj-server/infra/mysql/init/` 或手动 source。

**配置文件：** 仓库 `docker/datasources.xml` 等 → 改库地址、密码 → 放 `~/fyj-server/infra/cat/conf/`。

```bash
cd ~/fyj-server/compose
docker compose -f cat.yml up -d
```

访问 `http://localhost:2281/cat`。

→ 详细验证：[verify/cat.md](verify/cat.md)

### Phase 10：备份

```bash
chmod +x ~/fyj-server/scripts/backup.sh
crontab -e
# 每日 03:00
0 3 * * * /Users/$USER/fyj-server/scripts/backup.sh >> /Users/$USER/fyj-server/scripts/backup.log 2>&1
```

### Phase 11：验证

各组件单独验证清单见 `verify/` 目录：

- [verify/infra.md](verify/infra.md) — MySQL + Redis
- [verify/kafka.md](verify/kafka.md) — Kafka + Zookeeper
- [verify/es.md](verify/es.md) — Elasticsearch
- [verify/apollo.md](verify/apollo.md) — Apollo 三组件
- [verify/cat.md](verify/cat.md) — CAT
- [verify/all.md](verify/all.md) — 全栈一键自检（端口暴露面/资源/网络/业务容器接入冒烟）

## 业务容器接入

新业务项目的 Compose 加上：

```yaml
networks:
  default:
    external:
      name: infra-net
```

容器内访问中间件：

- MySQL：`infra-mysql:3306`
- Redis：`infra-redis:6379`
- Kafka：`infra-kafka:9092`
- ES：`infra-es:9200`
- Apollo Config：`infra-apollo-config:8080`
- CAT：`infra-cat:2281`

宿主机端口能不暴露就不暴露，需要本地工具（如 Navicat）连时再加 `ports:`。

## 清理与迁移

**整体清理：**

```bash
cd ~/fyj-server/compose
docker compose -f cat.yml down
docker compose -f apollo.yml down
docker compose -f es.yml down
docker compose -f kafka.yml down
docker compose -f infra.yml down
rm -rf ~/fyj-server/                  # 数据连同走人
docker network rm infra-net
```

**迁移：**

```bash
# 旧机
tar czf fyj-server-snapshot.tar.gz ~/fyj-server/

# 新机
tar xzf fyj-server-snapshot.tar.gz -C ~/
echo 'export SERVER_ROOT="$HOME/fyj-server"' >> ~/.zshrc && source ~/.zshrc
docker network create infra-net
cd ~/fyj-server/compose
docker compose -f infra.yml up -d
# ...按 Phase 顺序启
```

## 安全检查清单

- [x] OrbStack 装好，Docker Desktop 已关。
- [x] `infra-net` 已创建。
- [ ] 所有密码已改强密码（MySQL/Redis/Apollo）。
- [ ] Mac 防火墙（Lulu/Little Snitch）拦截非必要外联。
- [ ] `~/fyj-server/` 纳入 Time Machine 或额外备份策略。
- [ ] cron 备份脚本生效，已验证产物。
- [ ] 中间件全部 healthy（`docker ps` 检查）。
