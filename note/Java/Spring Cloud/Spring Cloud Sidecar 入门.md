---
tags:
  - java
  - spring-cloud
  - sidecar
  - eureka
  - zuul
created: 2026-07-07
source: https://www.baeldung.com/spring-cloud-sidecar-intro
---
# Spring Cloud Sidecar 入门

## 文章主旨

Baeldung 这篇文章介绍的是 **Spring Cloud Netflix Sidecar**：如何把 Node.js 这类非 JVM 服务接入 Spring Cloud Netflix 体系，让它们也能被 Eureka 注册发现，并通过 Zuul 这类网关访问。

核心问题是：

> 如果系统里不只有 Spring Boot 服务，还有 Node.js、Python、Go 等服务，它们怎样加入 Spring Cloud 的服务发现、健康检查和网关路由体系？

Sidecar 的思路是：在非 JVM 服务旁边启动一个很小的 Spring Boot 应用。这个 Spring Boot 应用不承载业务逻辑，而是代表非 JVM 服务去完成 Spring Cloud 生态里的基础设施能力。

---

## 1. Sidecar 解决什么问题

Spring Cloud Netflix 原本主要服务于 JVM / Spring Boot 应用。Spring Boot 服务可以很自然地：

- 注册到 Eureka；
- 暴露 Actuator 健康检查；
- 被 Zuul / Ribbon 等组件发现和调用；
- 使用 Spring Cloud 的配置、监控和基础设施能力。

但非 JVM 服务通常没有这些能力。Sidecar 通过一个伴随进程补齐这部分能力：

- Sidecar 注册到 Eureka；
- Sidecar 暴露符合 Spring Cloud 预期的健康检查；
- Sidecar 把请求转发到本机或指定端口上的非 JVM 服务；
- Spring Cloud 体系中的其他服务看到的是一个普通的服务实例。

所以 Sidecar 本质上是一个 **适配层**，不是业务服务本身。

---

## 2. 示例架构

文章用一个 Node.js 服务作为示例。整体结构大致是：

```text
客户端
  |
  v
Zuul / Spring Cloud 路由
  |
  v
Sidecar Spring Boot 应用
  |
  v
Node.js 业务服务
```

同时还有一个 Eureka Server：

```text
Sidecar Spring Boot 应用 ---> Eureka Server
```

Node.js 服务自己不直接注册 Eureka。它只需要提供业务接口和健康检查接口；注册发现这件事由 Sidecar 完成。

---

## 3. Node.js 服务需要做什么

文章中的 Node.js 服务非常简单，重点不是 Node 本身，而是它需要提供两个能力：

1. 业务接口，比如返回 books 列表；
2. 健康检查接口，供 Sidecar 判断服务是否正常。

健康检查接口通常要返回类似下面的状态：

```json
{
  "status": "UP"
}
```

Sidecar 会通过配置中的 `sidecar.health-uri` 去访问这个接口。如果健康检查失败，Eureka 中对应服务实例的状态也会受到影响。

---

## 4. Sidecar Spring Boot 应用

Sidecar 应用本身是一个 Spring Boot 应用。文章的关键点是启用 Sidecar 支持：

```java
@SpringBootApplication
@EnableSidecar
public class SidecarApplication {
    public static void main(String[] args) {
        SpringApplication.run(SidecarApplication.class, args);
    }
}
```

`@EnableSidecar` 会把这个 Spring Boot 应用变成非 JVM 服务的代理入口，并让它参与 Spring Cloud Netflix 的服务发现和路由体系。

典型配置包含：

```yaml
spring:
  application:
    name: node-service

server:
  port: 5678

sidecar:
  port: 3000
  health-uri: http://localhost:3000/health

eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
```

含义：

- `spring.application.name`：Sidecar 在 Eureka 中注册的服务名，也就是非 JVM 服务对外呈现的服务名；
- `server.port`：Sidecar Spring Boot 应用自己的端口；
- `sidecar.port`：实际 Node.js 服务监听的端口；
- `sidecar.health-uri`：Node.js 服务的健康检查地址；
- `eureka.client.service-url.defaultZone`：Eureka Server 地址。

---

## 5. Eureka Server 的作用

文章还搭建了一个 Eureka Server，用于保存服务注册信息。

Sidecar 启动后，会把自己注册到 Eureka。其他 Spring Cloud 服务不需要知道背后是 Node.js，只需要从 Eureka 发现服务名，然后通过网关或客户端调用它。

也就是说，对调用方来说：

```text
node-service
```

看起来就像一个普通的 Spring Cloud 服务。

---

## 6. 请求链路

启动顺序通常是：

1. 启动 Eureka Server；
2. 启动 Node.js 服务；
3. 启动 Sidecar Spring Boot 应用；
4. 在 Eureka 控制台确认 `node-service` 已注册；
5. 通过 Spring Cloud 路由访问 Node.js 的业务接口。

请求进入 Sidecar 后，会被转发到配置的 `sidecar.port`，也就是实际的 Node.js 进程。

可以把 Sidecar 理解成：

> 对 Spring Cloud 说：“我是一个正常服务”；对 Node.js 服务说：“我帮你接入 Spring Cloud 基础设施。”

---

## 7. 这篇文章的价值

这篇文章适合用来理解三个点：

1. **Sidecar 模式**
   - 非 JVM 服务旁边放一个伴随进程；
   - 伴随进程处理注册发现、健康检查、路由等平台能力；
   - 业务服务只关注业务逻辑。

2. **Spring Cloud Netflix 的接入方式**
   - Eureka 负责服务发现；
   - Zuul / 路由层负责转发；
   - Sidecar 负责把非 JVM 服务包装成 Spring Cloud 可识别的服务。

3. **多语言微服务的兼容方案**
   - 系统不必强制所有服务都用 Java / Spring Boot；
   - 通过 Sidecar 可以把不同语言的服务统一纳入同一套服务治理体系。

---

## 8. 使用时要注意

这篇文章使用的是 Spring Cloud Netflix 体系里的 Sidecar、Eureka、Zuul 等组件。它很适合理解历史上的 Spring Cloud 微服务接入方式和 Sidecar 模式，但新项目是否继续采用这套方案，需要结合当前 Spring Cloud 版本和团队基础设施判断。

如果只是学习架构思想，重点应放在：

- Sidecar 为什么存在；
- 它代理了哪些平台能力；
- 非 JVM 服务需要暴露哪些最小接口；
- 服务发现和网关如何把它当作普通服务处理。

如果是新系统落地，可以进一步比较：

- Spring Cloud Gateway；
- Kubernetes Service / Ingress；
- Service Mesh；
- Dapr；
- 平台自带的健康检查和服务注册能力。

---

## 总结

Spring Cloud Sidecar 的核心是：**用一个 Spring Boot 伴随应用，把非 JVM 服务包装成 Spring Cloud 生态里的普通服务实例**。

它让 Node.js 等服务可以接入 Eureka、健康检查和路由体系，从而在多语言微服务架构中保持统一的服务治理模型。文章的示例虽然简单，但很好地展示了 Sidecar 模式的本质：业务进程不需要理解 Spring Cloud，旁边的 Sidecar 负责和平台对接。
