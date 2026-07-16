---
title: ES慢查询过多治理《最佳实践》
tags:
  - ES
  - Elasticsearch
  - 慢查询
  - 性能优化
created: 2026-07-13
---
## 一、业务查询逻辑

1. **terms 查询非 keyword 字段类型**，建议使用 multi-fields，增加 keyword 类型查，或者重建索引，字段类型改为 keyword，线上大部分慢查询都是因为这个问题导致的。
2. **terms size 过大**，会严重影响查询效率，建议 terms 大小控制在 1000 以内，超过 1k 的，需要更大集群规模来满足查询容量，容量不足会严重影响 CPU 负载，甚至是查挂集群。
3. **wildcard 通配符、fuzzy 模糊、reg 正则、prefix 匹配查询**，使用分词查询代替模糊、通配符查询。
4. **深页查询**，`from + size` 过大，并且配置了 `max_result_window`。
5. **多层聚合查询**，聚合查询 size 越大性能越差。
6. **nested 嵌套查询**。
7. **聚合、排序查询使用了 keyword 字段**，会大大增加查询耗时，建议使用 multi-fields，增加数值型类型查。
8. **业务应用客户端频繁创建线程池**。
9. **使用别名查询**，命中 shards 特别多，导致查询量过大。
10. **单条文档存的字段，或者字段的内容特别大**，查询返回的结果巨大，根据需要查询返回的字段，指定 include or exclude 字段配置，减少传输量，减少序列化消耗的计算资源，以提升查询速度。

## 二、索引配置

1. ES7 默认没有显式配置 `refresh_interval`，长期写入后第一次查询都会强制 flush 索引，增加查询耗时，导致第一次查询耗时增加。
2. 分片数量过多，建议读写使用路由功能（ES 单节点存储的分片数两个条件：1. 总数小于 1000；2. 根据内存大小，1GB 内存最多 20 个分片，根据实际 data 节点数量累加）。
3. 索引可拆分的尽量拆分，大索引段文件巨大，查询效率低。
4. 未配置定时关闭或删除索引任务，集群索引文档数过多，大量占用堆内存。
5. 未配置定时**合并段文件**任务，索引段文件数量过多，查询时大量占用 IO。
6. 分片数量尽量与 data 节点数量保持一致，均衡读写负载到各 data 节点。

## 三、硬件环境

1. 资源利用率过高，CPU、磁盘 IO、内存、磁盘空间不足，都会影响查询性能。
2. 宿主机硬件故障、宿主机隔离问题，都可能影响查询。
3. 跨北上访问，响应的结果越大延迟越高。
4. 查询流量过大，造成集群性能瓶颈，尽快限流，或者扩容。
5. **【高危】宿主机网卡丢包**，极具隐蔽性，注意通过“智能诊断——节点丢失”风险项排查！

> 小技巧：我们可以通过慢查询分析中的节点视图，来确认是不是个别机器性能问题导致的慢查。如下图，业务集群读写负载较高，混合使用了高性能机型以及普通 Hulk SSD 机型；磁盘 IO 性能相对较差的普通 Hulk SSD 的磁盘 `io.await`、慢日志数量明显比高性能机型多，因此推测是机器硬件导致的慢日志。

## 四、如何排查分析慢查

慢查询的原因多种多样，但是绝大部分都是容易定位到的：

- 如果 CPU 高，看火焰图，最好懂 Lucene；如果 CPU 没有跑满，慢查询可以从 slowlog 中找到。
- 如果 thread queue 堆积，可以看堆栈和 `hot_threads`（不能完全取代堆栈）。
- profile 适合分析纯计算层面各个阶段的代价，它主要展示 Lucene 的执行过程。

> Profile 使用说明：[【转载-20240926】深入解密 Elasticsearch 查询优化：巧用 Profile 工具/API 提升性能](https://blog.csdn.net/laoyang360/article/details/141910044)

- 分布式层面可以通过 trace（ES7 支持）或者日志等来协助定位。

以下几个场景为通过 profile 工具分析慢查原因的几个经典案例：

### 场景一、使用非 keyword 类型进行 terms 查询

1. 通过慢查询模板，判断哪类查询语句造成了慢查。

进入慢查询分析页面，选择慢查类型第一的模板。

2. 定位到慢查语句后，通过查询性能分析，分析出查询中最耗时的部分。

打开查询性能分析页面，输入索引名、查询语句，点击查询，在返回的结果中展开具体内容：

> 如果是异常大查询，已经把集群查挂的，或者引起大量慢查询的查询，切勿执行，避免二次影响集群状态！

一层层点进去，查看耗时最高的模块，由此可以定位查询语句中最耗时的部分：

在这个 case 中，我们通过查看索引的配置，可以发现 `channels` 字段类型为 `integer`，非 keyword 字段 terms 查询性能差导致了慢查。

```json
{
  "mappings": {
    "properties": {
      "bizId": {
        "type": "long"
      },
      "cartInteract": {
        "type": "long"
      },
      "categoryIds": {
        "type": "long"
      },
      "channelPage": {
        "type": "long"
      },
      "channels": {
        "type": "integer"
      },
      "cityIds": {
        "type": "long"
      },
      "creator": {
        "type": "keyword"
      },
      "crmId": {
        "type": "long"
      },
      "ctime": {
        "type": "long"
      }
    }
  }
}
```

索引字段一旦创建，便无法修改（详细原因：[[ES 索引字段及主分片数修改]]），需要重建索引（业务不用改代码），或字段通过 multi-fields 增加新字段方式处理（需业务改代码，如新字段是 `channels.keyword`，查询字段也要改成 `channels.keyword`），详细用法参考：[[ES multi-field 最佳实践]]。

### 场景二：索引 nested 结构，平台打开索引页面慢

业务如发现如下 `"size": 0` 的慢查询语句，需要注意下索引结构中是否包含 nested 结构字段。目前为了精确统计 nested 结构下文档数量，会造成慢查。目前平台已经在改回不统计详细 nested 文档数量的统计方式，待上线后这些慢查会消失。

### 场景三：聚合查询慢查询

以下聚合查询，默认情况下耗时 **8s+**：

```json
{
  "aggs": {
    "maxLastUsedTimeAgg": {
      "max": {
        "field": "lastUsedTime"
      }
    },
    "uniqueKeyAgg": {
      "terms": {
        "field": "uniqueKey",
        "size": 10,
        "min_doc_count": 1,
        "shard_min_doc_count": 0,
        "show_term_doc_count_error": false,
        "order": [
          {
            "_count": "desc"
          },
          {
            "_term": "asc"
          }
        ]
      }
    }
  }
}
```

由于返回结果明显只有 1 个结果的，可以使用 map 方式（`"execution_hint": "map"`）构建聚合查询。添加该命令后，查询耗时变为 **2ms**，返回结果完全一致。

> 聚合查询中，应尽量对存在 doc values 的字段进行聚合，而数值型默认具备，`keyword` / `ip` / `flattened` 这 3 种类型也同样具备，`text` 默认不开启 doc values。
>
> 极少数需要对 text 字段进行聚合查询的场景（如下词云效果），则字段需要配置 `fielddata enable`。
>
> 详细说明可参考：[图解 Elasticsearch 的 Fielddata Cache 使用与优化](https://www.modb.pro/db/1826438082254614528)。

关于聚合查询构建方式更多详细说明，可见：[[ES keyword 字段 terms agg 性能问题]]。

### 场景四：排序使用数值字段，不要用默认的 `_id` 字段排序

业务索引如果有单独的 id 字段（数值类型），并且需要排序搜索的，使用该字段排序，不要用文档自带的 `_id` 排序。原因是前者在写入时默认配置 `doc_values`，查询时直接使用正排排序，执行效率较高；而文档默认 `_id` 字段属于索引 `meta_data` 数据，为 keyword 类型，无 `doc_values` 正排，因此排序、聚合效果较差。

举例：业务使用 `_id` 字段排序，`_id` 与 id 字段内容一样，id 字段为 long 类型。

使用默认 `_id` 查询，耗时 **200ms+**。

使用 id 查询，耗时在 **100ms 以内**，查询速度快了 1 倍以上。

### 场景五、索引过大，查询耗时高

terms 查询的索引文档数量越多，涉及到的倒排索引匹配的次数越多，查询的段文件越多，导致磁盘 IO 交互越频繁，最终导致查询耗时变高。

针对此类问题，我们建议业务重建索引，调整主分片数量（建议单位分片大小 `<50g`），或者将索引按诸如日期、id 哈希等方式拆分，减少索引、分片大小，以提升查询效率。

举例：

虽然 `userStatus` 字段已经是 keyword 类型了，但因为查询索引的文档数量过多，导致 `advance` 耗时高。

> ES 对 Advance 的解释如下[Search Profile API](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/search-profile)：大致意思为单位分片下的查询是串行执行的，文档数量越多，查询次数也就越多。
>
> `advance` is the "lower level" version of `next_doc`: it serves the same purpose of finding the next matching doc, but requires the calling query to perform extra tasks such as identifying and moving past skips, etc. However, not all queries can use `next_doc`, so `advance` is also timed for those queries.

索引大小 **200GB+**，文档数量 **4 亿条+**，主分片数量：1。

示例索引 `group_member`：`shards: 1 * 2`，`docs: 451309320`，`size: 204.5gb`。

### 场景六、通配符查询

通配符查询特别消耗 CPU，建议禁用 wildcard 模糊检索，对字段采用 n-gram 进行分词查询（对应 `termQuery`！），以提升查询性能。详细说明：Wildcard 的血泪史和解决办法。

在去除了 wildcard 查询后，资源利用率由原先的峰值 60%，下降至 15% 不到。原本机器配置 16C/64G/1200G * 48 台，8/21 第一次缩容 24 台，8/26 第二次缩容 12 台，总缩容 36 台，集群规模为原先的 25%

我们发现甚至有同学已经在做了 N-gram 分词后，仍使用 match 查询，这样会非常慢。改成 term 查询后，由原先的秒级耗时降低至几十毫秒级别，效果显著。

### 场景七、不合理的 terms 查询

单个 query 中设置了过多的 terms 字段，会严重影响查询性能。建议手动转化为 boolean-should 查询并放置于 boolean filter 中，也就是新建一个 boolean query，放到现有 boolean query 的 filter 里面。

详细说明请看：[[note/ES/Terms 查询逻辑分析及最佳实践|Terms 查询逻辑分析及最佳实践]]。

实例：

有问题的查询示例：在 `filter` 中直接使用 `terms`，例如 `actiontype` 包含大量取值：

```json
{
  "query": {
    "bool": {
      "filter": [
        {
          "term": {
            "userid": {
              "value": "782641830",
              "boost": 1.0
            }
          }
        },
        {
          "term": {
            "status": {
              "value": "0",
              "boost": 1.0
            }
          }
        },
        {
          "terms": {
            "actiontype": [
              "44",
              "45",
              "46",
              "47",
              "48",
              "49",
              "190"
              // ... 还有更多取值
            ]
          }
        }
      ]
    }
  }
}
```

优化后的查询：将多个 terms 条件改写为一个新的 `bool` 查询，将多个 `term` 放入 `should`，再把这个 bool 查询整体放到外层 `bool.filter` 中。

```json
{
  "query": {
    "bool": {
      "filter": [
        {
          "bool": {
            "should": [
              {
                "term": {
                  "field": {
                    "value": "1",
                    "boost": 1.0
                  }
                }
              },
              {
                "term": {
                  "field": {
                    "value": "2",
                    "boost": 1.0
                  }
                }
              }
              // ... 继续展开原 terms 中的其他取值
            ]
          }
        }
      ]
    }
  }
}
```

优化效果：

- 查询请求量从 **2k** 上升到 **27k**。
- 请求耗时由 **637ms** 降至 **12ms**。

### 场景八、must_not exists 查询

慢查询语法示例：

```json
{
  "bool": {
    "should": [
      {
        "term": {
          "has_special_pic_quality_score": {
            "value": 2,
            "boost": 1.0
          }
        }
      },
      {
        "bool": {
          "must_not": [
            {
              "exists": {
                "field": "has_special_pic_quality_score",
                "boost": 1.0
              }
            }
          ],
          "disable_coord": false,
          "adjust_pure_negative": true,
          "boost": 1.0
        }
      }
    ],
    "disable_coord": false
  }
}
```

以上查询中，`must_not exists` 查询在大索引中代价极高，`has_special_pic_quality_score_result` 字段的 exists 查询在海量数据中开销巨大。

解决方案：

- **添加默认值策略**：在写入时，为 `has_special_pic_quality_score_result` 字段设置默认值（如 0 或 -1），避免字段缺失。
- **使用额外标记字段**：添加一个布尔型字段 `has_quality_score_flag`，标记字段是否存在。
- **重建索引**：对历史数据补充默认值。

优化查询语法：

```json
// 优化后的查询（假设用 0 表示字段不存在）
{
  "bool": {
    "should": [
      { "term": { "has_special_pic_quality_score_result": 2 } },
      { "term": { "has_special_pic_quality_score_result": 0 } }
    ],
    "minimum_should_match": 1
  }
}
```
