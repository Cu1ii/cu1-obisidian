# 大 key 场景

业务场景中经常会有各种大 value 多 value 的情况, 比如:

1. 但是 string 类型 key 存在的 value 很大, 超过 1 MB
2. hash, set, zset, list 中存储的元素过多的元素, 超过 10 K
3. 一个集群存储了上亿的 key, Key 本身过多也带来了更多的空间占用

由于 redis 是单线程运行的, 如果一次操作的 value 很大会对整个 redis 的响应时间造成负面影响, 所以, **业务上能拆则拆**, 下面举几个典型的分拆方案.

## 1. string 类型大 key 处理方式

### 该对象需要每次都整存整取

- 可以尝试将对象分拆成几个 key-value
- 使用 multiGet 获取值, 这样分拆的意义在于分拆单次操作的压力, 将操作压力平摊到多个 redis 实例中, 降低对单个 redis 的 IO 影响和 CPU 的影响

### 该对象每次只需要存取部分数据

- 以像第一种做法一样, 分拆成几个 key-value, 也可以将这个存储在一个 hash 中, 没一个 field 代表一个具体的属性
- 使用 hget, hmget 来获取部分的 value 使用 hset, hmset 来更新部分属性

## 2. 集合类型大 key 处理方式

类似于场景一中过多第一个做法, 可以将这些元素分拆. 以 hash 为例, 原先的正常存取流程是 hget(hashKey, field); hset(hashKey, field, value)

现在, 固定一个桶的数量, 比如 10000, 每次存取的时候, 先在本地计算 field 的 hash 值, 对 10000 取模, 确定了该 field 落在哪个 key 上. newHashKey = hashKey +(hash(field) % 10000); hset(newHashKey, field, value); hget(newHashKey, field)

set, zset, list 也可以类似上述做法. 但有些不适合的场景, 比如, 要保证 lpop 的数据的确是最早 push 到 list 中去的, 这个就需要一些附加的属性, 或者是在 key 的拼接上做一些工作 (比如 list 按照时间来分拆)

## 3. 大 bloomfilter 处理方式

使用 bitmap 或者布隆过滤器的场景, 往往是数据量极大的情况, 在这种情况下, bitmap 和布隆过滤器使用空间也就比较大, 比如用于公司 userId 匹配的布隆过滤器, 就需要 512 MB 的大小, 这对 Redis 来说绝对是大 value 了

![](image-01.png)

在这种场景下, 就需要对其进行拆分, 拆分为足够小的 bitmap, 比如将 512 MB 的大 bitmap 拆分为 1024 个 512 KB 的 bitmap. 不过拆分的时候需要注意, 要将每个值落在一个 bitmap 上. 有些业务只是把 bitmap 拆开, 但还是当做一个整体的 bitmap 来看, 所以一个 key 还是落在多个 bitmap 上, 这样就有可能导致一个 key 请求需要查询多个节点, 多个 bitmap. 如下图, 被请求的值被 hash 到多个 bitmap 上, 也就是 redis 的多个 key 上, 这些 key 还有可能在不同的节点上, 这样拆分显然**大大降低了查询的效率**.

因此我们所要做的是吧所有拆分后的 bitmap 当做独立的 bitmap, 然后**通过不同的 hash 将不同的 key 分配给不同的 bitmap 上, 而不是把所有的小 bitmap 当做一个整体**. 这样做后每次请求都只需要去 Redis 中一个 key 即可.

![](image-02.png)

## 4. Bloomfilter 拆分问题

通过 3 中拆分后, 相当于 bitmap 变小了, 会不会增加布隆过滤器的误判率? 实际上是不会的, 布隆过滤器的误判率是哈希函数个数 k, 结合元素个数 n, 一级 bitmap 大小 m 所决定的, 其约等于 $(1 - e^{-kn/m})^k$. 因此如果我们在第一步, 也就是分配 key 给不同的 bitmap 时, 能够尽可能均匀的拆分, 那么 ${n/m}$ 的值几乎是一样的, 误判率就不会改变. 具体的误判率推导可以参考: [wiki/Bloom_filter](https://en.wikipedia.org/wiki/Bloom_filter).

同时, 客户端也提供便利的 api (>= 2.3.4 版本), setBits/getBits 用于一次操作同一个 key 的多个 bit 值.

建议: k 取 13 个, 单个 bloomfilter 控制在 512 KB 以下

## 5. 过多的 key 处理方式

如果 key 的个数过多会带来更多的内存空间占用
- key 本身的占用
- 集群模式中, 服务端需要建立一些 slot2key 的映射关系, 这其中的指针占用的 key 多的情况下也是浪费巨大空间

这两个方面在 key 个数上亿的时候消耗内存十分明显 (Redis 3.2 及以下版本均存在这个问题, 4.0 有优化)

所以减少 key 的个数可以减少内存消耗, 可以参考的方案是转 hash 结构存储, 即原先是直接使用 Redis string 的结构粗出, 现在将多个 key 存储在一个 hash 结构中, 具体场景参考如下:

### 5.1 key 本身就有很强的相关性

比如多个 key 代表一个对象, 每个 key 是对象的一个属性, 这种可直接按照特定对象的特征来设置一个新 key -- hash 结构, 原先的 key 则作为这个新 hash 的 field.

举例说明:

原先存储的 3 个 key, `user.zhangsan-id = 123; user.zhangsan-age = 18; user.zhangsan-country = china;` 这三个 key 本身就具有很强的相关特征, 转成 hash 存储就像这样
`key = user:zhangsan field:id = 123; field:age = 18; field:country = china;` 即 Redis 中存储的是一个 `key: user:zhangsan` , 他有三个 field, 每个 field + key 就对应原先的一个 key

### 5.2 key 本身没有相关性

预估一下总量, 采取和上述第二种场景类似的方案, 预分一个固定的桶数量. 比如现在预估 key 的总数为 2 亿, 按照一个 hash 存储 100 个 field 来算, 需要 ${2 亿 / 100} = 200 W$ 个桶 (200 W 个 key 占用的空间很少, 2 亿可能有将近 20 G)

原先比如有 3 个 key, `user:123456789, user:1, user:2` 现在按照 200 W 固定桶分就是先计算出桶的序号, hash(123456789) % 200W, 这里最好保证这个 hash 算法是个整数, 否则需要调整下模除的规则.

这样计算出 3 个 key 的桶分别是 1, 2, 2. 所以存储的时候调用 API hset(key, field, value), 读取的时候使用 hget(key, fied);

注意两个地方:
1. hash 取模对负数的处理; 
2. 预分桶时, 一个 hash 中存储的值最好不要超过 512, 100 左右较为合适. 