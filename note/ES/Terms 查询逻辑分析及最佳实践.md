---
title: Terms查询逻辑分析及最佳实践
tags:
  - ES
  - Elasticsearch
  - terms查询
  - 查询优化
created: 2026-07-13
---
## 一、背景

使用 terms 查询 keyword 类型的字段在某些情况下会变得非常耗时，甚至会导致集群负载急剧升高发生故障。

## 二、查询逻辑

terms 的查询在不同的情况下和不同的集群版本下会走不同的逻辑。

### 2.1 ES7（7.10 版本）

在 ES7 中，如果 terms query 中的 term 个数小于等于 **16**，那么该查询会直接被 Lucene 重写为 boolean query。

在查询的流程中，当查询到某个具体段时，Lucene 会根据该段的信息进一步重写：如果该段的 term set（term 词典）包含的 term 和 terms 查询中的 term 的交集的个数小于等于 **16**，则会被重写为 boolean query。

如果未被重写，则该查询会迭代所有的 term 的倒排，将对应的文档 id 构建为一个 bitset，参与后续的查询。

这两种查询方式各有优点，可以参考以下分析：

#### 重写的原因分析（引用）

##### 为什么未达到阈值使用 BooleanQuery 的方式做文档号的收集

- 最多只有 16 个（默认阈值 `BOOLEAN_REWRITE_TERM_COUNT_THRESHOLD`，见文章《索引文件的读取（九）之 tim&&tip》）term 的文档信息作为 `DisiPriorityQueue` 的元素进行堆的排序，内存开销、排序开销很低。
- 避免匹配了少量 term 仍可能会占用较大内存存储文档号的问题。例如 term 对应的文档号的数值差值很大，使用 `FixedBitSet` 存储会有无用的内存开销。内存开销取决于段中的文档总数，而 `docBuffer[]` 的数组是固定，大小为一个 block（索引文件 `.doc` 中的 block）中包含的文档数量，默认值为 128。

##### 为什么达到阈值后不使用 BooleanQuery 的方式做文档号的收集

- 达到阈值后，term 的数量无法确定，`DisiPriorityQueue` 的排序、内存开销取决于 term 的数量。
- 每个 term 都会生成一个 `TermQuery` 作为 `BooleanQuery` 的子查询，导致更容易抛出 `TooManyClauses` 的异常。`BooleanQuery` 所能包含的子查询数量是有上限限制的，取决于 `BooleanQuery` 中的 `maxClauseCount` 参数，默认值为 1024。
- 当满足查询的 term 的数量较大时，通过 `FixedBitSet` 对象只记录文档号，相比通过 `BooleanQuery` 的方式（使用 `PostingsEnum` 对象存储，每个 term 都有自己的 `PostingsEnum` 对象）会占用更少的内存。在获取到满足查询的文档号集合之前（堆排序），`PostingsEnum` 对象会常驻内存，它至少包含了文档号的信息以及其他信息（在以后介绍索引文件 `.doc` 的读取的文章中会展开介绍）；而在 `TermRangeQuery` 中，我们只关心文档号，使用 `FixedBitSet` 对象存储文档号的期间，也会获取每一个 term 对应的 `PostingsEnum` 对象，但当获取了 term 对应的文档号集合之后，该对象能及时释放。

引用自：[《索引文件的读取（十一）之 tim&&tip（Lucene 8.4.0）》](https://amazingkoala.com.cn/Lucene/Search/2020/0819/%E7%B4%A2%E5%BC%95%E6%96%87%E4%BB%B6%E7%9A%84%E8%AF%BB%E5%8F%96%EF%BC%88%E5%8D%81%E4%B8%80%EF%BC%89%E4%B9%8Btim%26%26tip/)。

#### 手动转为 boolean + should + term 的适用场景

在实际的使用过程中，我们发现这个 **16** 的阈值不能适应所有的情况。在 terms 的个数不超过 **1024**（boolean query 的子语句个数限制）的前提下，在遇到以下情况时，我们可以考虑手动请求转化为 `boolean + should + term` 情况。因为 term query 会默认打分，所以需要将转化后的请求再放入 boolean query 的 filter 中，避免引入额外的打分逻辑。

1. 如果一个 terms 查询会命中大量的文档（不考虑其他筛选条件，只考虑 terms 查询本身，比如会命中索引中 90% 的文档）。文档太多如果走默认逻辑则构建 bitset 会非常耗时而且占用大量 CPU 和内存。
2. 整个查询中有其他的筛选条件可以极大缩小召回的文档集，整个请求召回的文档数很少。因为 boolean query 可以很好地和其他查询条件配合，如果其他查询条件可以极大减少查询范围，则可以借助倒排链的优化加快查询。

### 2.2 ES5（5.6 版本）

ES5 与 ES7 的区别在于在 ES 阶段有一次重写。

如果该 terms query 在 filter context 中（该查询在 boolean query 中的 filter 语句中，或者该查询的父查询在 filter 语句中），则和 ES7 相同。

如果该 terms query 不在 filter context 中（比如该查询在 boolean query 的 must 或 should 语句中），则该 terms query 会直接被重写为 boolean query，此时会走 `boolean + term` 的打分逻辑。

如果在 ES5 升 7 之后发现 ES7 的性能下降，则可能是因为在这种情况下将查询重写为 boolean query 性能会更好，可以考虑手动将该 terms query 转为 `boolean + should` 的方式实现，为避免额外的打分可以放入 boolean query 的 filter 中。

## 三、最佳实践

1. 如果一个 terms 查询会命中大量的文档（不考虑其他筛选条件，只考虑 terms 查询本身，比如会命中索引中 90% 的文档或者上千万文档），强烈建议手动转化为 `boolean-should` 查询并放置于 boolean filter 中，或者分多次查询，每次查询保持 terms 在 16 个以下。

   需要注意的是，如果将 should 语句直接和其他 boolean 语句组合，需要设置 `minShouldMatch` 为 1。

   原语句：
   ```json
   {
     "query": {
       "bool": {
         "must": [
           {
             "terms": {
               "field": [
                 "1",
                 "2",
                 "3",
                 "4",
                 "5",
                 "6",
                 "7",
                 "8",
                 "9",
                 "10",
                 "11",
                 "12",
                 "13",
                 "14",
                 "15",
                 "16",
                 "17",
                 "18",
                 "19",
                 "20",
                 "21",
                 "22"
               ]
             }
           }
         ]
       }
     }
   }
   ```

   转化之后的 boolean 语句：

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
                 // ...
               ]
             }
           }
         ]
       }
     }
   }
   ```

2. 如果在整个查询语句中存在着筛选力度更大的其他 query（即命中的文档数很少），整个请求召回的文档数很少，则可以考虑手动转化为 `boolean-should` 查询并放置于 boolean filter 中。

3. 如果这些 terms 对应文档集的补集很小而且业务场景中该字段是有限的枚举类型，可以考虑用 `must not + terms` 反向查询。

4. terms 的个数超过了 1024 或者没有以上的情况，可以考虑直接使用 terms query。手动转为 boolean query 可能会超过 boolean query 的子语句上限（1024）导致查询报错，也可能会导致占用更多的内存，影响查询性能。
