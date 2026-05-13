---
tags:
  - java
  - java17
  - record
  - 新特性
created: 2026-05-12
source: https://www.baeldung.com/java-record-keyword
---
# Java Record 关键字

## 概述

**Record** 是 Java 14 引入（预览特性），在 **Java 16 正式转正**、**Java 17 LTS** 包含的轻量级数据载体类。它本质上是不可变数据类的简洁声明方式，自动生成构造方法、`getter()`、`equals()`、`hashCode()` 和 `toString()`。

## 设计动机

传统上，编写一个纯数据载体类需要大量样板代码：

```java
// 传统方式 —— 大量样板代码
public class Person {
    private final String name;
    private final int age;

    public Person(String name, int age) {
        this.name = name;
        this.age = age;
    }

    public String getName() { return name; }
    public int getAge() { return age; }

    @Override
    public boolean equals(Object o) { ... }
    @Override
    public int hashCode() { ... }
    @Override
    public String toString() { ... }
}
```

Record 的目标是：**让数据只是数据** —— 用更少的代码表达同样的含义。

## 基本语法

```java
public record Person(String name, int age) { }
```

一行代码等价于上面几十行传统类 —— 它隐式提供了：
- 一个**全参构造方法**
- 每个组件的 **`accessor` 方法**（注意：不是传统 JavaBean 的 `getXxx()`，而是**与组件同名**的方法，如 `name()`、`age()`）
- `equals()` & `hashCode()` —— 基于所有组件字段
- `toString()` —— 格式为 `Person[name=xxx, age=xxx]`
- `final` 类 —— **不可被继承**
- 所有字段都是 `private final` —— **不可变**

### 使用示例

```java
Person p = new Person("John", 30);
System.out.println(p.name());   // 输出: John（注意不是 getName()）
System.out.println(p.age());    // 输出: 30
System.out.println(p);          // 输出: Person[name=John, age=30]

Person p2 = new Person("John", 30);
System.out.println(p.equals(p2)); // true —— 基于所有字段比较
```

## 核心特性详解

### 1. 紧凑型构造方法（Compact Constructor）

Record 允许在声明中添加**紧凑型构造方法** —— 无需重复参数列表，适用于参数校验或归一化：

```java
public record Person(String name, int age) {
    public Person {
        // 参数校验
        if (age < 0) {
            throw new IllegalArgumentException("年龄不能为负数");
        }
        // 参数归一化
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("姓名不能为空");
        }
        // name = name.trim();  // 紧凑构造中可以修改参数（最终会被赋值给字段）
    }
}
```

紧凑型构造方法中，参数变量（如 `name`、`age`）可以被修改，最终赋值给 `private final` 字段。

### 2. 自定义实例方法

Record 中也可以添加自定义方法：

```java
public record Person(String name, int age) {
    public String greeting() {
        return "Hello, I'm " + name() + ", " + age() + " years old.";
    }

    public boolean isAdult() {
        return age() >= 18;
    }
}
```

### 3. 静态成员

Record 可以包含静态字段、静态方法和静态常量：

```java
public record Person(String name, int age) {
    public static final int ADULT_AGE = 18;

    public static Person createAdult(String name) {
        return new Person(name, ADULT_AGE);
    }

    public static boolean isAdultAge(int age) {
        return age >= ADULT_AGE;
    }
}
```

### 4. 嵌套 Record

Record 可以嵌套在其他类中，也可以包含其他 Record：

```java
public record Address(String city, String street) { }

public record Person(String name, int age, Address address) { }

// 使用
Person p = new Person("John", 30, new Address("Beijing", "Chang'an Street"));
```

## 局限性

1. **不可继承** —— Record 隐式继承 `java.lang.Record`，不能扩展其他类，且本身被 `final` 修饰
2. **不能定义实例字段** —— 不能在 Record 中额外添加 `private final` 之外的实例字段（只能通过组件列表声明）
3. **字段是 final 的** —— 不可变，不能修改字段值
4. **不能声明 native 方法**
5. **不能是抽象类** —— 隐式为 final

## Record 与普通类的对比

| 特性 | Record | 普通类 |
|------|--------|--------|
| 样板代码 | 极少 | 较多 |
| 可变性 | 不可变（`final` 字段） | 可控 |
| 继承 | 不可继承/不可扩展 | 灵活 |
| equals/hashCode | 自动生成（基于所有组件） | 需手动实现 |
| getter 命名 | `fieldName()` | `getFieldName()`（约定） |
| 适用场景 | 数据载体/DTO/VO | 通用 |

## 实际应用场景

### DTO（数据传输对象）

```java
public record UserDTO(Long id, String username, String email) { }
```

### 多返回值

```java
public record SearchResult(List<Item> items, int totalCount) { }

public SearchResult searchItems(String query) {
    // ... 搜索逻辑
    return new SearchResult(items, count);
}
```

### 与 Lombok 的比较

Lombok 的 `@Data` / `@Value` 可以在传统类上实现类似效果，但 Record 是**语言原生**特性：
- 不需要额外依赖
- 编译器保证不可变性
- 模式匹配（Java 17+ 预览）和 `instanceof` 中的 deconstruction 模式天然支持 Record

```java
// Java 17+ 模式匹配与 Record 解构
if (obj instanceof Person(String name, int age)) {
    System.out.println("Name: " + name + ", Age: " + age);
}
```

## 总结

Java Record 为 **"只是想要携带数据的类"** 提供了最简洁的声明方式。它不是要替代普通类，而是为数据载体这一常见场景提供更好的语言级支持。配合 Java 17 的模式匹配等特性，Record 在代码简洁性和表达力上具有显著优势。

---

> 参考: [Baeldung - Java Record Keyword](https://www.baeldung.com/java-record-keyword)
