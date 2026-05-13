# 知识准备指南 — 顺序学习路线

> 共 25 节课，按依赖关系排序。每节课包含：目标 → 学习资料 → 动手练习 → 验收标准。
> 学完一节再进入下一节，不要跳课。

---

## 使用说明

- 每节课末尾的 **练习** 必须动手做完，光看不练等于没学
- 时间紧张时，跳过标注 `[可选]` 的资料
- 标注 `[项目直接相关]` 的资料与 T1–T80 任务一一对应，优先读
- 学完一节课在 `[ ]` 前打勾

---

## 第 1 课：.class 文件到底长什么样

**目标**：能用 `javap` 反编译任意类，看懂常量池、方法表、字节码指令三块内容。

**资料**：

1. `[必读]` [JVM Spec Chapter 4: The class File Format](https://docs.oracle.com/javase/specs/jvms/se21/html/jvms-4.html) — 读 4.1 节（ClassFile 结构）和 4.3 节（描述符），其余用到再查
2. `[必读]` 周志明《深入理解 Java 虚拟机》第 6 章 — 类文件结构，从 6.3.1 魔数开始读到 6.3.7 结束
3. `[项目直接相关]` 写一个简单的 Java 类（包含一个方法，方法里有 if/for），分别用以下命令反编译：
   ```bash
   javap -c -v ClassName          # 查看常量池 + 字节码指令
   javap -c ClassName             # 只看字节码指令
   javap -p ClassName             # 查看所有方法签名
   ```

**练习**：

```java
// 写这个类，然后用 javap -c -v 反编译它
public class Calc {
    public int add(int a, int b) {
        return a + b;
    }
}
```

回答三个问题：
- `add` 方法对应哪几条字节码指令？（提示：看 Code 属性）
- 常量池里 `add` 的方法描述符是什么？
- 如果把 `return a + b` 改成 `return a * b`，字节码会怎么变？

**验收**：能不看资料说出 class 文件由哪几部分组成（魔数、版本号、常量池、访问标志、类索引、字段表、方法表、属性表）。

**预计时间**：2h

---

## 第 2 课：JVM 怎么加载一个类

**目标**：理解类加载的三个阶段（加载 → 链接 → 初始化），能画出双亲委派模型的调用链。

**资料**：

1. `[必读]` 周志明《深入理解 Java 虚拟机》第 7 章 — 虚拟机类加载机制，读 7.2（类加载时机）和 7.3（类加载过程）
2. `[必读]` [Baeldung - Class Loaders in Java](https://www.baeldung.com/java-classloaders) — 双亲委派模型图解
3. `[项目直接相关]` [Spring Boot - Executable Jar Launcher 源码](https://github.com/spring-projects/spring-boot/blob/main/spring-boot-project/spring-boot-tools/spring-boot-loader/src/main/java/org/springframework/boot/loader/Launcher.java) — 只看这个文件的注释和 main 方法，知道 `LaunchedURLClassLoader` 是谁的子类
4. `[可选]` [InfoQ - JVM 类加载机制详解](https://www.infoq.cn/article/0PR7kHVrMSkJ0rXJXqid)

**练习**：

```java
// 打印自己的 ClassLoader 层级链
public class LoaderChain {
    public static void main(String[] args) {
        ClassLoader cl = LoaderChain.class.getClassLoader();
        while (cl != null) {
            System.out.println(cl.getClass().getName());
            cl = cl.getParent();
        }
        System.out.println("Bootstrap ClassLoader (null)");
    }
}
```

在三种环境下运行并对比输出：
- 命令行 `java LoaderChain`
- Spring Boot fat jar 中运行（在 main 方法里加这段代码）
- IDEA 中直接 run

**验收**：能画出 `Bootstrap → Platform/Ext → App → LaunchedURLClassLoader` 的继承链，解释为什么 Spring Boot 需要自定义 ClassLoader。

**预计时间**：2h

---

## 第 3 课：Instrumentation API — premain 与 redefineClasses

**目标**：写出一个能 attach 到目标进程并完成方法体替换的最小 Agent。

**资料**：

1. `[必读]` [java.lang.instrument 包文档](https://docs.oracle.com/en/java/javase/21/docs/api/java.instrument/java/lang/instrument/package-summary.html) — 从头读到 "Starting an Agent" 结束，10 分钟
2. `[必读]` [Instrumentation API 文档](https://docs.oracle.com/en/java/javase/21/docs/api/java.instrument/java/lang/instrument/Instrumentation.html) — 重点读 `redefineClasses`、`addTransformer`、`retransformClasses` 三个方法的 javadoc
3. `[必读]` [Baeldung - Guide to Java Instrumentation](https://www.baeldung.com/java-instrumentation) — 跟做 "Creating a Simple Agent" 和 "Redefining Classes" 两节
4. `[项目直接相关]` 阅读 `redefineClasses` javadoc 中的限制说明（在方法注释里），逐条对比 plan.md 第 2.2 节的限制表
5. `[可选]` [javassist 的 Instrumentation 教程](https://www.javassist.org/tutorial/tutorial2.html) — 了解另一种 API 风格，但不用于本项目

**练习**：
创建两个独立的 Maven 项目（不要放到 hot-deployment 里）：

**项目 A — 被 attach 的目标程序**：
```java
// MainApp.java
public class MainApp {
    public static void main(String[] args) throws Exception {
        Hello hello = new Hello();
        while (true) {
            System.out.println(hello.greet());
            Thread.sleep(2000);
        }
    }
}

// Hello.java — 会被热替换的类
public class Hello {
    public String greet() {
        return "Hello, World!";
    }
}
```

**项目 B — Agent jar**：
```java
// SimpleAgent.java
public class SimpleAgent {
    public static void premain(String args, Instrumentation inst) {
        System.out.println("[Agent] Loaded!");
    }
}
```

步骤：
1. 编译项目 A，正常运行，确认每 2 秒输出 "Hello, World!"
2. 编译项目 B，打包为 jar，MANIFEST.MF 指定 `Premain-Class: SimpleAgent`
3. 用 `-javaagent:agent.jar` 启动项目 A，确认 Agent 被加载
4. 进阶：修改 `Hello.java` 的 `greet()` 返回 "Hello, HotSwap!"，重新编译得到新的 `Hello.class`，在 Agent 的 premain 中调用 `inst.redefineClasses(new ClassDefinition(Hello.class, newBytes))` 完成热替换

**验收**：在终端看到输出从 "Hello, World!" 变成 "Hello, HotSwap!"，且没有重启 JVM。

**预计时间**：4h

---

## 第 4 课：redefineClasses 的边界实验（PoC-A 预演）

**目标**：亲手验证 `redefineClasses` 在哪些场景下成功、哪些场景下抛异常，获得一手数据而非背书结论。

**资料**：

1. `[必读]` [Instrumentation.redefineClasses 的 javadoc（Throws 部分）](https://docs.oracle.com/en/java/javase/21/docs/api/java.instrument/java/lang/instrument/Instrumentation.html#redefineClasses(java.lang.instrument.ClassDefinition...)) — 逐条读 `UnsupportedOperationException` 的触发条件
2. `[项目直接相关]` plan.md 第 6 节 Risk Register R1 项 — 理解为什么 PoC-A 的结果直接决定项目范围
3. `[可选]` [DCEVM 项目](https://github.com/HotswapProjects/DCEVM) — 了解一下 DCEVM 是怎么绕过标准 JDK 限制的（本项目不使用 DCEVM，但需要知道差距在哪）

**练习**：
在第 3 课的 Agent 项目基础上，逐一测试以下操作，记录结果（成功/失败 + 异常类型）：

```
目标类: TestTarget.java
public class TestTarget {
    private int counter = 0;
    public String hello() { return "hello"; }
}
```

| 实验 | 修改内容 | 结果 |
|------|---------|------|
| A | 修改 `hello()` 方法体返回 "hi" | |
| B | 新增 `public String bye()` 方法 | |
| C | 删除 `hello()` 方法 | |
| D | 新增 `private String name` 字段 | |
| E | 修改类实现 `Serializable` 接口 | |
| F | 修改 `hello()` 方法签名（增加参数） | |

在 **JDK 8、17、21** 上分别运行，记录差异。

**验收**：得到一份填满的表格，和 plan.md 2.2 节的结论一致。如果不一致，说明测试代码有问题或 JDK 行为有变化。

**预计时间**：3h

---

## 第 5 课：ASM 基础 — 读取和遍历 class 文件

**目标**：用 ASM 写一个 `ClassVisitor`，打印出任意类中所有方法的名字和描述符。

**资料**：

1. `[必读]` [ASM 官方指南 — 第 1 章：Introduction](https://asm.ow2.io/asm4-guide.pdf) — 第 1–8 页，理解 ASM 的整体架构和访问者模式
2. `[必读]` [ASM 官方指南 — 第 2 章：Classes](https://asm.ow2.io/asm4-guide.pdf) — 第 9–40 页，重点读 2.1（结构）、2.2（接口与组件）、2.3（生成类），先跳过 2.4（转换类）下一课再学
3. `[推荐工具]` 安装 IDEA 插件 [ASM Bytecode Viewer](https://plugins.jetbrains.com/plugin/10302-asm-bytecode-viewer)（或 ASM Bytecode Outline），写一段 Java 代码 → 右键 → Show Bytecode → 看 ASM 源码长什么样
4. `[可选]` [ASM 核心类 5 分钟速览](https://www.baeldung.com/java-asm) — Baeldung 的 ASM 入门文章

**练习**：
创建独立 Maven 项目，依赖 `org.ow2.asm:asm:9.7`：

```java
// 需求：读取一个 .class 文件，打印出：
//   - 类名
//   - 所有字段名 + 类型描述符
//   - 所有方法名 + 描述符
public class ClassPrinter extends ClassVisitor {
    public ClassPrinter() {
        super(ASM9);
    }

    @Override
    public void visit(int version, int access, String name, 
                      String signature, String superName, String[] interfaces) {
        System.out.println("Class: " + name);
        System.out.println("Super: " + superName);
    }

    @Override
    public FieldVisitor visitField(int access, String name, 
                                   String descriptor, String signature, Object value) {
        System.out.println("  Field: " + name + " " + descriptor);
        return null;  // 不需要深入字段内部
    }

    @Override
    public MethodVisitor visitMethod(int access, String name, 
                                     String descriptor, String signature, String[] exceptions) {
        System.out.println("  Method: " + name + " " + descriptor);
        return null;  // 不需要深入方法内部
    }
}

// 测试代码
public static void main(String[] args) throws Exception {
    ClassReader cr = new ClassReader("com.example.Hello");  // 读取你之前写的 Hello 类
    cr.accept(new ClassPrinter(), 0);
}
```

**验收**：运行 `ClassPrinter` 打印的输出和 `javap -p Hello` 一致。

**预计时间**：3h

---

## 第 6 课：ASM 进阶 — 修改字节码

**目标**：用 ASM 在方法的开头和结尾插入代码，输出修改后的字节码。

**资料**：

1. `[必读]` [ASM 官方指南 — 第 2.4 节：Transforming Classes](https://asm.ow2.io/asm4-guide.pdf) — 第 33–40 页，这是 ASM 最重要的部分
2. `[必读]` [ASM 官方指南 — 第 3 章：Methods](https://asm.ow2.io/asm4-guide.pdf) — 第 41–58 页，重点 3.1（结构）和 3.2（生成方法）
3. `[项目直接相关]` [ASM AdviceAdapter 使用示例](https://asm.ow2.io/asm4-guide.pdf) — 第 69–73 页（3.4 节），`AdviceAdapter` 是 PoC-B 的核心工具类
4. `[推荐工具]` 用 ASM Bytecode Viewer 插件写 `System.out.println("enter");`，看它生成什么 ASM 代码，复制到你的项目里

**练习**：
在上一课的 `ClassPrinter` 基础上改造：

```java
// 需求：给 Hello 类的 greet() 方法包裹上计时日志
// 修改前：
public class Hello {
    public String greet() {
        return "Hello, World!";
    }
}

// 修改后（等价效果）：
public class Hello {
    public String greet() {
        long start = System.nanoTime();
        try {
            return "Hello, World!";
        } finally {
            System.out.println("greet() took " + (System.nanoTime() - start) + " ns");
        }
    }
}
```

步骤：
1. 先自己用 Java 写好修改后的效果，javap 看字节码
2. 用 ASM 的 `AdviceAdapter` 实现 `onMethodEnter` 插入 `long start = System.nanoTime()`
3. 用 `onMethodExit`（注意区分正常返回和异常返回）插入 `println`
4. 把输出的字节码写回文件，用 `javap` 验证结果正确
5. 用自定义 ClassLoader 加载修改后的类，调用 `greet()` 看效果

**验收**：控制台输出 `greet() took xxxx ns`，且返回值仍然是 "Hello, World!"。

**预计时间**：4h

---

## 第 7 课：ClassFileTransformer — 加载时修改字节码

**目标**：在 `premain` 中注册 `ClassFileTransformer`，截获类加载事件并修改字节码。

**资料**：

1. `[必读]` [ClassFileTransformer 接口文档](https://docs.oracle.com/en/java/javase/21/docs/api/java.instrument/java/lang/instrument/ClassFileTransformer.html) — 只有 `transform` 一个方法，仔细读参数含义
2. `[必读]` Baeldung 文章 "Guide to Java Instrumentation" 中的 "Modifying Class Bytes" 章节 — 链接在第 3 课中
3. `[项目直接相关]` plan.md 第 4 节 PoC-B 描述 — 理解为什么需要 "把方法体委托到可替换容器"
4. `[可选]` [HotswapAgent 的 Plugin 注册机制](https://github.com/HotswapProjects/HotswapAgent/blob/master/hotswap-agent-core/src/main/java/org/hotswap/agent/HotswapAgent.java) — 看看成熟的商业级 Agent 是怎么注册 Transformer 的

**练习**：
把第 5–6 课的 ASM 代码移植到 Agent 中：

```java
public class TimingAgent {
    public static void premain(String args, Instrumentation inst) {
        inst.addTransformer(new TimingTransformer());
    }
}

public class TimingTransformer implements ClassFileTransformer {
    @Override
    public byte[] transform(ClassLoader loader, String className,
                            Class<?> classBeingRedefined, ProtectionDomain protectionDomain,
                            byte[] classfileBuffer) {
        // 1. 只处理 com.example 包下的类
        // 2. 用 ASM 给每个方法加计时（第 6 课的代码）
        // 3. 返回修改后的字节码
        // 注意：不要修改无法处理的类，返回 null 表示不修改
    }
}
```

用 `-javaagent:` 启动第 3 课的项目 A，观察项目 A 中所有方法是否都自动带上了计时日志。

**验收**：不需要修改项目 A 任何源码，启动后所有 `com.example` 包下的方法调用都自动输出耗时。

**预计时间**：3h

---

## 第 8 课：PoC-B 核心 — 方法体委托模式

**目标**：验证 Load-time Instrumentation 实现 L2 结构变更的可行性。这是整个项目最关键的技术实验。

**资料**：

1. `[必读]` plan.md 第 4 节 Phase 1 PoC-B 描述（plan.md 第 27 行）— 逐句理解验证目标
2. `[项目直接相关]` plan.md 第 6 节 Risk R1 — 如果这节验证失败，项目范围需要调整
3. `[必读]` 复习第 7 课的 `ClassFileTransformer` — 这次不是在方法头加日志，而是**把整个方法体替换为委托调用**
4. `[可选]` [ASM Core API 详解](https://www.baeldung.com/java-asm) — 重点看 Generator 部分

**核心思路**：

```
原始类：
public class Hello {
    public String greet() {
        return "Hello, World!";  // <- 这是原始方法体
    }
}

Transformer 修改后（首次加载时）：
public class Hello {
    private static MethodContainer container = new MethodContainer("greet", ...);

    public String greet() {
        // 修改后的方法体：委托给容器
        return (String) container.invoke(this, "greet", new Object[0]);
    }
}

热更新时只需要 replace MethodContainer 里的实现，Hello 类本身不用再 redefine
```

**练习**：

1. 设计 `MethodContainer` 类：
   ```java
   public class MethodContainer {
       // 存储每个方法的当前实现 —— 可以热替换这个 map 里的值
       private static final Map<String, MethodHandle> methodMap = new ConcurrentHashMap<>();

       public static Object invoke(Object target, String methodName, String desc, Object... args) {
           MethodHandle handle = methodMap.get(methodName);
           return handle.invoke(target, args);
       }

       public static void updateMethod(String methodName, MethodHandle newImpl) {
           methodMap.put(methodName, newImpl);
       }
   }
   ```

2. 写 `PocTransformer`（参考 plan.md T14）：
   - 对 `com.example` 包下的类，把每个非 static 方法的方法体替换为对 `MethodContainer.invoke()` 的调用
   - 注意：构造函数 `<init>` 不要修改

3. 验证：
   - 用这个 Transformer 启动一个示例程序
   - 记录启动时间（与不加 Transformer 对比，偏差应 < 20%）
   - 检查 Spring AOP / CGLIB 代理类是否受影响（用一个带 `@Transactional` 的 Service 测试）

**验收**：写 `doc/poc-report.md` 的 B 章节，给出明确结论：
- ✅ 可行（方案 X，启动耗时增加 Y%）
- ❌ 不可行（原因 Z）

**预计时间**：6h（这是整个 Phase 1 最耗时的一步）

---

## 第 9 课：Maven 多模块项目搭建

**目标**：从零搭建 `根 pom + common + agent + plugin` 四模块工程，能 `mvn clean install` 成功。

**资料**：

1. `[必读]` [Maven 官方 - Guide to Working with Multiple Modules](https://maven.apache.org/guides/mini/guide-multiple-modules-4.html)
2. `[必读]` [Maven Shade Plugin 文档](https://maven.apache.org/plugins/maven-shade-plugin/) — 读 "Usage" 和 "Examples" 两节
3. `[项目直接相关]` plan.md 第 3.2 节 — 每个模块的 pom.xml 配置要点
4. `[可选]` [Maven 多模块最佳实践](https://www.baeldung.com/maven-multi-module) — Baeldung 的教程，有完整代码示例

**练习**：
按以下步骤创建项目骨架（这是 T1–T8 的实现草稿）：

```bash
hot-deployment/
├── pom.xml                    # 根聚合器，packaging=pom
├── common/
│   ├── pom.xml                # source/target=1.8，零依赖
│   └── src/main/java/com/github/hotdeploy/common/
│       └── package-info.java
├── agent/
│   ├── pom.xml                # source/target=1.8，依赖 common + ASM
│   │                          # 配置 maven-shade-plugin 打 fat-jar
│   └── src/main/java/com/github/hotdeploy/agent/
│       └── package-info.java
└── plugin/
    ├── pom.xml                # source/target=17，依赖 common
    │                          # 配置 org.jetbrains.intellij 插件
    └── src/main/kotlin/com/github/hotdeploy/plugin/
        └── package-info.kt
```

关键点：
- 根 pom 的 `<dependencyManagement>` 集中声明 ASM 9.7、Groovy 4、Spock 2.x 版本
- agent 的 shade 插件配置必须包含 `Premain-Class` manifest
- plugin 的 `org.jetbrains.intellij` 插件 `ideaVersion` 设为 `2022.1.1`
- `mvn clean install` 从头编译通过，无报错、无警告

**验收**：`agent/target/` 下生成 fat-jar；`common/target/` 下生成 common.jar；`plugin/target/` 下生成插件包。

**预计时间**：3h

---

## 第 10 课：IntelliJ Platform SDK 基础

**目标**：理解 IDEA 插件的运行模型，能创建最小插件并在沙箱 IDEA 中运行。

**资料**：

1. `[必读]` [IntelliJ Platform SDK — Plugin Structure](https://plugins.jetbrains.com/docs/intellij/plugin-structure.html) — plugin.xml 的结构
2. `[必读]` [IntelliJ Platform SDK — Extension Points](https://plugins.jetbrains.com/docs/intellij/plugin-extension-points.html) — 什么是扩展点，怎么声明
3. `[必读]` [IntelliJ Platform SDK — Actions](https://plugins.jetbrains.com/docs/intellij/plugin-actions.html) — AnAction 的注册与实现
4. `[必读]` [IntelliJ Platform SDK — Threading Model](https://plugins.jetbrains.com/docs/intellij/threading-model.html) — EDT 规则，写错会导致 IDEA 卡死
5. `[必读]` [IntelliJ Platform SDK — Services](https://plugins.jetbrains.com/docs/intellij/plugin-services.html) — 应用级 / 项目级 Service
6. `[项目直接相关]` 打开 sample 项目：[JetBrains/intellij-sdk-code-samples](https://github.com/JetBrains/intellij-sdk-code-samples) 的 `action_basics` 示例

**练习**：
创建一个最小插件（可以在 hot-deployment/plugin 里做，也可以单独建项目）：

```kotlin
// 需求：在 IDEA 菜单栏加一个 "Hello" 按钮，点击后在状态栏显示 "Hello, HotUpdate!"

// 1. AnAction 实现
class HelloAction : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val statusBar = WindowManager.getInstance().getStatusBar(project)
        statusBar?.info = "Hello, HotUpdate!"
    }
}

// 2. plugin.xml 注册
// <actions>
//     <action id="HelloAction" class="com.github.hotdeploy.plugin.HelloAction"
//             text="Hello" description="Say hello">
//         <add-to-group group-id="MainMenu" anchor="last"/>
//     </action>
// </actions>
```

运行方式：在 IDEA 中右键 plugin 模块 → Run Plugin → 弹出沙箱 IDEA → 查看菜单栏 → 点击 Hello。

**验收**：沙箱 IDEA 状态栏显示 "Hello, HotUpdate!"，且没有报错。

**预计时间**：3h

---

## 第 11 课：Kotlin 速成 — IDEA 插件开发必备语法

**目标**：掌握 Kotlin 中写 IDEA 插件最高频使用的 10 个特性。

**资料**：

1. `[必读]` [Kotlin 官方文档 - Basic Syntax](https://kotlinlang.org/docs/basic-syntax.html)
2. `[必读]` [Kotlin 官方文档 - Null Safety](https://kotlinlang.org/docs/null-safety.html) — IDEA API 到处都是 null，这是最重要的 Kotlin 特性
3. `[必读]` [Kotlin 官方文档 - Data Classes](https://kotlinlang.org/docs/data-classes.html) — 本项目的 DTO/配置对象全用 data class
4. `[必读]` [Kotlin 官方文档 - Object Expressions & Declarations](https://kotlinlang.org/docs/object-declarations.html) — 单例 Service 用 `object`
5. `[必读]` [Kotlin 官方文档 - Extension Functions](https://kotlinlang.org/docs/extensions.html) — 给 IDEA 平台类加工具方法
6. `[必读]` [Kotlin 官方文档 - When Expression](https://kotlinlang.org/docs/control-flow.html#when-expression) — 状态机分支
7. `[可选]` [Kotlin Koans](https://play.kotlinlang.org/koans/overview) — 交互式练习，做完前 10 个即可

**练习**：
把以下 Java 代码翻译成 Kotlin（这是 T42 ClassChangeDetector 的雏形）：

```java
// Java 版
public class ChangeDetector {
    private final Map<String, Long> checksums = new HashMap<>();

    public boolean hasChanged(String className, long newChecksum) {
        Long old = checksums.get(className);
        if (old == null || old != newChecksum) {
            checksums.put(className, newChecksum);
            return true;
        }
        return false;
    }

    public List<String> getUnchangedClasses() {
        return checksums.entrySet().stream()
            .filter(e -> e.getValue() != -1L)
            .map(Map.Entry::getKey)
            .collect(Collectors.toList());
    }
}
```

翻译要点：
- `Map<String, Long>` → `MutableMap<String, Long>`
- null 检查 → `old == null` → `?:` 或 `let`
- Stream → `filter` + `map` （Kotlin 的集合扩展函数）
- 测试：分别创建一个空的和有数据的 detector，验证 hasChanged 逻辑

**验收**：Kotlin 版代码编译通过，逻辑与原 Java 版一致。

**预计时间**：2h

---

## 第 12 课：IntelliJ VirtualFileListener — 文件变更监听

**目标**：在插件中注册文件监听器，捕获 `.java` 文件保存事件。

**资料**：

1. `[必读]` [IntelliJ Platform SDK — File System / Virtual File System](https://plugins.jetbrains.com/docs/intellij/virtual-file-system.html) — 理解 IDEA 的 VFS 模型
2. `[必读]` [VirtualFileListener 接口](https://github.com/JetBrains/intellij-community/blob/master/platform/core-api/src/com/intellij/openapi/vfs/VirtualFileListener.java) — 看源码中的方法签名，比读文档快
3. `[项目直接相关]` [IntelliJ Platform SDK — Listeners](https://plugins.jetbrains.com/docs/intellij/plugin-listeners.html) — 怎么注册 listener
4. `[示例]` intellij-sdk-code-samples 中的 `virtual_file_system` 示例

**练习**：
在第 10 课的最小插件基础上，添加文件监听：

```kotlin
// HotUpdateFileListener.kt
class HotUpdateFileListener : VirtualFileListener {
    override fun contentsChanged(event: VirtualFileEvent) {
        val file = event.file
        if (file.extension == "java") {
            println("[HotUpdate] File saved: ${file.path}")
        }
    }
}

// 在 plugin.xml 或通过代码注册：
// messageBus.connect().subscribe(VirtualFileManager.VFS_CHANGES, listener)
```

测试：在沙箱 IDEA 中创建一个 Java 文件 → 编辑 → Ctrl+S → 控制台打印文件名。

**验收**：每次保存 `.java` 文件都能看到日志输出。

**预计时间**：2h

---

## 第 13 课：IntelliJ CompilerManager — 触发增量编译

**目标**：在文件保存后触发 IDEA 的增量编译，获取输出 `.class` 文件路径。

**资料**：

1. `[必读]` [IntelliJ Platform SDK — CompilerManager](https://github.com/JetBrains/intellij-community/blob/master/platform/compiler-impl/src/com/intellij/compiler/CompilerManager.java) — 直接看源码，重点关注 `addCompilationStatusListener` 和 `compile` 方法
2. `[必读]` [IntelliJ CompileTask API](https://jetbrains.org/intellij/sdk/docs/tutorials/build_system/compilation_basics.html) — 编译后如何获取输出路径
3. `[项目直接相关]` task.md T31–T32 — 编译集成 Spock Spec 的测试思路
4. `[可选]` [IntelliJ Project Model 基础](https://plugins.jetbrains.com/docs/intellij/project-model.html) — 理解 Module / SourceRoot / OutputPath 的概念

**练习**：
```kotlin
// 获取当前项目的编译输出路径
fun getOutputPath(project: Project): String? {
    val compilerManager = CompilerManager.getInstance(project)
    // 获取所有模块的输出路径
    return ModuleManager.getInstance(project).modules
        .firstOrNull()
        ?.let { CompilerPaths.getModuleOutputPath(it, false) }
}

// 触发编译
fun triggerCompile(project: Project, file: VirtualFile) {
    CompilerManager.getInstance(project).compile(file, object : CompileStatusNotification {
        override fun finished(aborted: Boolean, errors: Int, warnings: Int, context: CompileContext) {
            if (!aborted && errors == 0) {
                // 编译成功，获取 .class 文件路径
                println("[HotUpdate] Compile success, output: ${getOutputPath(project)}")
            }
        }
    })
}
```

**验收**：修改一个 `.java` 文件 → 调用 `triggerCompile` → 在输出目录找到新生成的 `.class` 文件。

**预计时间**：2h

---

## 第 14 课：Spring Boot 进程检测

**目标**：通过 IDEA API 找到正在运行的 Spring Boot 进程的 PID 和主类。

**资料**：

1. `[必读]` [IntelliJ RunManager API](https://github.com/JetBrains/intellij-community/blob/master/platform/execution/src/com/intellij/execution/RunManager.java) — 源码，看 `getAllConfigurations()`、`getRunningProcesses()` 方法
2. `[必读]` [IntelliJ ExecutionManager API](https://github.com/JetBrains/intellij-community/blob/master/platform/platform-api/src/com/intellij/execution/ExecutionManager.java) — 获取正在运行的进程
3. `[项目直接相关]` plan.md 节 2.3 — 进程检测决策逻辑
4. `[参考]` [Spring Boot Run Configuration 源码](https://github.com/JetBrains/intellij-community/blob/master/plugins/spring/spring-boot/src/run/SpringBootRunConfiguration.java) — IDEA 的 Spring Boot 插件是怎么标识自己的 Run Configuration 的

**练习**：
```kotlin
// 扫描所有 Spring Boot 运行配置
fun detectSpringBootProcesses(project: Project): List<ProcessInfo> {
    val results = mutableListOf<ProcessInfo>()
    val runManager = RunManager.getInstance(project)

    for (config in runManager.allConfigurations) {
        // 检查是否是 Spring Boot 类型
        if (config.type.id.contains("spring.boot")) {
            val processHandler = /* 获取这个 config 对应的运行进程 */
            if (processHandler != null) {
                results.add(ProcessInfo(
                    pid = /* 获取 PID */,
                    mainClass = config.name,
                    processHandler = processHandler
                ))
            }
        }
    }
    return results
}

data class ProcessInfo(
    val pid: Long,
    val mainClass: String,
    val processHandler: ProcessHandler  // 或者其他获取 PID 的方式
)
```

注意：获取 PID 在不同 JDK 版本上的方式不同——`ProcessHandler` 可能有 `getProcess()` 或需要通过反射。

**验收**：能在沙箱 IDEA 中运行一个 Spring Boot 应用时，插件能正确识别并输出 PID。

**预计时间**：3h

---

## 第 15 课：TCP Socket 通信 — 长度前缀协议实现

**目标**：实现 4 字节大端长度头 + UTF-8 JSON 的编解码器。

**资料**：

1. `[必读]` [Java DataInputStream / DataOutputStream 文档](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/io/DataInputStream.html) — 注意 `readInt()` / `writeInt()` 就是大端序
2. `[必读]` [Oracle - All About Sockets](https://docs.oracle.com/javase/tutorial/networking/sockets/) — Socket 编程基础教程
3. `[必读]` [粘包/拆包问题解释](https://blog.csdn.net/zhangxinrun/article/details/6721495) — 理解为什么需要长度前缀
4. `[项目直接相关]` plan.md 节 2.2 通信时序图、task.md T23–T24
5. `[可选]` [Netty LengthFieldBasedFrameDecoder](https://netty.io/4.1/api/io/netty/handler/codec/LengthFieldBasedFrameDecoder.html) — 本项目不用 Netty（太重量级），但理解它的设计思路有助写出健壮的编解码

**练习**：
创建独立的 Maven 项目（或直接在 common 模块里写），实现两个类：

```java
// SocketProtocol.java — 对应 task.md T24
public class SocketProtocol {
    // 编码：对象 → 字节数组（序列化为 JSON → 计算长度 → 4字节头 + body）
    public static byte[] encode(Object message) throws IOException {
        byte[] json = new ObjectMapper().writeValueAsBytes(message);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        DataOutputStream dos = new DataOutputStream(bos);
        dos.writeInt(json.length);   // 4 字节大端长度
        dos.write(json);              // UTF-8 JSON Body
        return bos.toByteArray();
    }

    // 解码：字节数组 → 对象（读 4 字节长度 → 读 body → JSON 反序列化）
    public static <T> T decode(InputStream in, Class<T> type) throws IOException {
        DataInputStream dis = new DataInputStream(in);
        int length = dis.readInt();
        byte[] body = new byte[length];
        dis.readFully(body);
        return new ObjectMapper().readValue(body, type);
    }
}
```

测试（写 Spock 或 JUnit）：
- 空消息
- 正常消息 {"type": "PING"}
- 超长消息（1MB body）
- 恶意数据（长度头与实际不符 → 应抛异常）

**验收**：encode → decode 往返后对象内容一致；边界情况有异常处理。

**预计时间**：3h

---

## 第 16 课：Agent Socket Server — 多线程处理请求

**目标**：在 Agent 中启动 TCP Server，接收 Plugin 请求并正确调度。

**资料**：

1. `[必读]` [Java ServerSocket 文档](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/net/ServerSocket.html) — `accept()` 是阻塞的，必须在独立线程运行
2. `[必读]` [Java ExecutorService 文档](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/ExecutorService.html) — 用线程池处理并发连接
3. `[项目直接相关]` plan.md 节 2.4 Agent 启动与挂载流程图
4. `[项目直接相关]` task.md T25–T26

**练习**：
```java
// AgentSocketServer.java — 对应 task.md T26
public class AgentSocketServer {
    private final ServerSocket serverSocket;
    private final ExecutorService threadPool;
    private volatile boolean running = true;

    public AgentSocketServer(int port) throws IOException {
        this.serverSocket = new ServerSocket(port, 50, InetAddress.getLoopbackAddress());
        this.threadPool = Executors.newFixedThreadPool(4);
    }

    public int getPort() {
        return serverSocket.getLocalPort();
    }

    public void start() {
        new Thread(() -> {
            while (running) {
                try {
                    Socket client = serverSocket.accept();
                    threadPool.submit(() -> handleClient(client));
                } catch (IOException e) {
                    if (running) e.printStackTrace();
                }
            }
        }, "hotdeploy-agent-server").start();
    }

    private void handleClient(Socket client) {
        try (client) {
            Object request = SocketProtocol.decode(client.getInputStream(), Object.class);
            // 根据 request 类型分发到 RedefineDispatcher / ClassInjector / ...
            Object response = dispatch(request);
            client.getOutputStream().write(SocketProtocol.encode(response));
        } catch (Exception e) {
            // 捕获所有异常，不泄露到目标 JVM（task.md T61–T62 的要求）
            System.err.println("[HotDeploy] Error handling client: " + e.getMessage());
        }
    }

    public void stop() {
        running = false;
        threadPool.shutdownNow();
        // close serverSocket...
    }
}
```

测试：
- 用普通 Socket 客户端连接，发送 PING，收到 PONG
- 并发发送 10 个请求，都能正确响应
- Server 关闭后再连接，正确处理 IOException

**验收**：Server 在独立线程运行不阻塞 premain；并发请求正确响应；异常不泄露。

**预计时间**：3h

---

## 第 17 课：Plugin Socket Client — 异步通信不阻塞 EDT

**目标**：在 Plugin 侧实现 Socket 客户端，连接 Agent Server，所有操作异步执行。

**资料**：

1. `[必读]` [IntelliJ Platform SDK — Threading Model](https://plugins.jetbrains.com/docs/intellij/threading-model.html) — 再读一遍，EDT 规则是血的教训
2. `[必读]` `ApplicationManager.executeOnPooledThread` 的用法 — 看 IDEA 源码中的调用方式
3. `[项目直接相关]` task.md T27–T28
4. `[可选]` [CompletableFuture 异步编程](https://www.baeldung.com/java-completablefuture) — 用于处理异步响应

**练习**：
```kotlin
// PluginSocketClient.kt — 对应 task.md T28
class PluginSocketClient(private val host: String, private val port: Int) {

    fun sendRequest(request: RedefineRequest, callback: (RedefineResponse) -> Unit) {
        // 必须在后台线程执行，不能阻塞 EDT
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                val response = doSend(request)
                // 回到 EDT 更新 UI
                ApplicationManager.getApplication().invokeLater {
                    callback(response)
                }
            } catch (e: SocketTimeoutException) {
                // 超时重试 1 次
                try {
                    val response = doSend(request)
                    ApplicationManager.getApplication().invokeLater { callback(response) }
                } catch (e2: Exception) {
                    // 彻底失败，更新 UI 为红色
                    ApplicationManager.getApplication().invokeLater {
                        // 触发错误通知
                    }
                }
            } catch (e: ConnectException) {
                // Agent 未启动或端口不对
                ApplicationManager.getApplication().invokeLater {
                    // 状态栏显示 "未连接"
                }
            }
        }
    }

    private fun doSend(request: RedefineRequest): RedefineResponse {
        val socket = Socket()
        socket.connect(InetSocketAddress(host, port), 5000) // 5秒超时
        socket.use {
            it.getOutputStream().write(SocketProtocol.encode(request))
            return SocketProtocol.decode(it.getInputStream(), RedefineResponse::class.java)
        }
    }
}
```

**验收**：Plugin 发送请求期间，IDEA 主界面不卡顿；超时场景正确处理；失败重试 1 次。

**预计时间**：2h

---

## 第 18 课：端口发现机制

**目标**：Agent 启动后把端口号写入临时文件，Plugin 读取该文件获取连接地址。

**资料**：

1. `[必读]` [Java ProcessHandle API](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/ProcessHandle.html) — Java 9+ 获取当前进程 PID
2. `[项目直接相关]` task.md T35–T36
3. `[可选]` [JMX attach 机制的端口发现方式](https://docs.oracle.com/en/java/javase/21/docs/api/jdk.attach/com/sun/tools/attach/VirtualMachine.html) — JMX 用 `.attach_pid<pid>` 文件做端口发现，本项目类似

**练习**：
```java
// PortDiscovery.java — 对应 task.md T36
public class PortDiscovery {
    private static final String PORT_FILE_PREFIX = "/tmp/hotdeploy-";
    private static final String PORT_FILE_SUFFIX = ".port";

    // Agent 侧：写入端口
    public static void writePort(int port) {
        long pid = ProcessHandle.current().pid();
        Path path = Path.of(PORT_FILE_PREFIX + pid + PORT_FILE_SUFFIX);
        Files.writeString(path, String.valueOf(port));
        // 注册 shutdownHook 清理文件
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            try { Files.deleteIfExists(path); } catch (IOException ignored) {}
        }));
    }

    // Plugin 侧：读取端口
    public static int readPort(long pid) throws IOException {
        Path path = Path.of(PORT_FILE_PREFIX + pid + PORT_FILE_SUFFIX);
        return Integer.parseInt(Files.readString(path).trim());
    }

    // Plugin 侧：查找所有活跃 Agent
    public static List<Long> discoverAgentPids() throws IOException {
        try (var files = Files.newDirectoryStream(Path.of("/tmp"), "hotdeploy-*.port")) {
            List<Long> pids = new ArrayList<>();
            for (Path file : files) {
                String name = file.getFileName().toString();
                // 从文件名提取 PID
                String pidStr = name.replace("hotdeploy-", "").replace(".port", "");
                pids.add(Long.parseLong(pidStr));
            }
            return pids;
        }
    }
}
```

**验收**：Plugin 能发现所有正在运行的 Agent 进程；Agent 退出后端口文件被清理。

**预计时间**：1.5h

---

## 第 19 课：L1 方法体热替换 — 完整链路

**目标**：打通 Plugin 编译 → Socket 传输 → Agent redefine 的完整 L1 链路。

**资料**：

1. `[必读]` 复习第 3 课的 `redefineClasses` API
2. `[必读]` 复习第 15 课的 SocketProtocol 编解码
3. `[项目直接相关]` plan.md 第 2.2 节热更新时序图 — 对照时序图理解每一步
4. `[项目直接相关]` task.md T37–T38

**练习**：
整合之前写的所有代码：

1. Plugin 侧（用第 11–14、17 课的代码）：
   - 监听到 `.java` 保存 → 触发编译 → 读取 `.class` 字节 → Base64 编码
   - 构造 `RedefineRequest` 发送给 Agent

2. Agent 侧（用第 15–16、18 课的代码）：
   - 收到 `RedefineRequest` → Base64 解码 → 构造 `ClassDefinition` 数组
   - 调用 `Instrumentation.redefineClasses(classDefinitions)`
   - 捕获 `UnsupportedOperationException` → 返回失败响应

3. 端到端验证：
   ```java
   // Sample Spring Boot 项目中的 Controller
   @RestController
   public class HelloController {
       @GetMapping("/hello")
       public String hello() {
           return "Hello, v1";
       }
   }
   ```
   - 启动应用 + Agent → IDEA Run → Plugin 连接 Agent
   - 修改 `hello()` 返回 "Hello, v2" → Ctrl+S → 1 秒内 `curl /hello` 返回 "Hello, v2"

**验收**：修改方法体 → 保存 → HTTP 请求返回新结果，全程 < 2 秒。

**预计时间**：4h

---

## 第 20 课：新增类注入 — ClassLoader.defineClass()

**目标**：通过反射调用目标 ClassLoader 的 `defineClass` 方法，注入全新类。

**资料**：

1. `[必读]` [ClassLoader.defineClass 方法](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/ClassLoader.html#defineClass(java.lang.String,byte%5B%5D,int,int)) — 注意这是 `protected` 方法，必须通过反射调用
2. `[必读]` [Spring Boot LaunchedURLClassLoader 源码](https://github.com/spring-projects/spring-boot/blob/main/spring-boot-project/spring-boot-loader/src/main/java/org/springframework/boot/loader/LaunchedURLClassLoader.java) — 理解它的继承链，才能找到正确的 ClassLoader
3. `[项目直接相关]` task.md T39–T40
4. `[可选]` [Java 反射调用 protected 方法的注意事项](https://www.baeldung.com/java-reflection-access-private-methods) — `setAccessible(true)` 在 JDK 17+ 的行为变化

**练习**：
```java
// ClassInjector.java — 对应 task.md T40
public class ClassInjector {
    private static final Method defineClassMethod;

    static {
        try {
            defineClassMethod = ClassLoader.class.getDeclaredMethod(
                "defineClass", String.class, byte[].class, int.class, int.class);
            defineClassMethod.setAccessible(true);
        } catch (NoSuchMethodException e) {
            throw new RuntimeException(e);
        }
    }

    // 找到目标类的 ClassLoader（优先 Spring Boot 的，回退 AppClassLoader）
    public static ClassLoader findTargetClassLoader() {
        // 遍历当前线程的上下文 ClassLoader 链
        ClassLoader cl = Thread.currentThread().getContextClassLoader();
        while (cl != null) {
            if (cl.getClass().getName().contains("LaunchedURLClassLoader")) {
                return cl;
            }
            cl = cl.getParent();
        }
        return ClassLoader.getSystemClassLoader();
    }

    // 注入一个全新类
    public static Class<?> injectClass(String className, byte[] bytecode) {
        ClassLoader target = findTargetClassLoader();
        return (Class<?>) defineClassMethod.invoke(target, className, bytecode, 0, bytecode.length);
    }
}
```

测试：
- 写一个新的 `.class` 文件（编译得到的，不是 Agent 中已存在的类）
- 调用 `injectClass` → 反射调用该类的方法 → 确认能正常执行
- 在 Spring Boot 2.x 和 3.x 上分别测试（ClassLoader 不同）

**验收**：注入的新类可正常加载并调用；Spring Boot 2.x / 3.x 的 ClassLoader 探测都正确。

**预计时间**：3h

---

## 第 21 课：变更检测与 CRC 比对

**目标**：Plugin 侧维护类文件的 CRC 缓存，避免重复推送未变更的类。

**资料**：

1. `[必读]` [Java CRC32 API](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/zip/CRC32.html) — 计算校验和
2. `[项目直接相关]` task.md T41–T42
3. `[可选]` 也可以直接用文件的 `lastModified()` 时间戳做粗粒度比对

**练习**：
```kotlin
// ClassChangeDetector.kt — 对应 task.md T42
class ClassChangeDetector {
    private val checksums = ConcurrentHashMap<String, Long>()

    fun hasChanged(className: String, classBytes: ByteArray): Boolean {
        val crc = CRC32().also { it.update(classBytes) }.value
        val old = checksums.put(className, crc)
        return old == null || old != crc
    }

    fun getChangedClasses(compiledFiles: Map<String, ByteArray>): List<String> {
        return compiledFiles.entries
            .filter { (name, bytes) -> hasChanged(name, bytes) }
            .map { it.key }
    }
}
```

测试点：
- 相同内容保存两次 → 第二次 `hasChanged` 返回 false
- 修改方法体 → `hasChanged` 返回 true
- 类被删除后重新创建 → `hasChanged` 返回 true

**验收**：重复保存未修改的文件不会触发热更新推送。

**预计时间**：1.5h

---

## 第 22 课：Agent 参数自动注入 — RunConfigurationExtension

**目标**：在 Spring Boot 运行配置中自动追加 `-javaagent` 参数，用户无需手动配置。

**资料**：

1. `[必读]` [IntelliJ RunConfigurationExtension 文档](https://github.com/JetBrains/intellij-community/blob/master/platform/execution/src/com/intellij/execution/RunConfigurationExtension.java) — 直接看源码，重点关注 `updateJavaParameters` 方法
2. `[必读]` JavaParameters 类 — `addVMParameter("-javaagent:...")` 方法
3. `[项目直接相关]` task.md T43–T44
4. `[参考]` JRebel 插件的 RunConfigurationExtension 实现（如果有源码的话，或者参考 StackOverflow 上的讨论）

**练习**：
```kotlin
// HotUpdateRunConfigurationExtension.kt — 对应 task.md T44
class HotUpdateRunConfigurationExtension : RunConfigurationExtension() {

    override fun isApplicableFor(configurationType: ConfigurationType): Boolean {
        // 只对 Spring Boot 类型的运行配置生效
        return configurationType.id.contains("spring.boot")
    }

    override fun updateJavaParameters(
        configuration: RunnerAndConfigurationSettings,
        params: JavaParameters,
        runnerSettings: RunnerSettings?
    ) {
        // 检查用户是否关闭了自动注入（从 HotUpdateSettings 读取）
        if (!HotUpdateSettings.instance.autoInjectAgent) return

        // 找到 agent.jar 的绝对路径
        val agentJar = PathResolver.findAgentJar() ?: return
        params.vmParametersList.add("-javaagent:${agentJar.absolutePath}")
        params.vmParametersList.add("-Dhotdeploy.agent.port=0")
    }
}
```

测试：
- 在沙箱 IDEA 中创建一个 Spring Boot Run Configuration
- 点击 Run → 检查启动参数中是否自动包含 `-javaagent:...`
- 在 Settings 中关闭自动注入 → 再次 Run → 确认不包含该参数

**验收**：用户在 "Settings | Tools | Hot Update" 中开启自动注入后，所有 Spring Boot 启动配置自动追加 Agent 参数。

**预计时间**：2h

---

## 第 23 课：Spock 测试框架速成

**目标**：掌握 Spock 测试的核心语法，能写出 given/when/then 结构的测试用例。

**资料**：

1. `[必读]` [Spock 官方文档 — Introduction](https://spockframework.org/spock/docs/2.3/introduction.html) — 5 分钟读完
2. `[必读]` [Spock 官方文档 — Data Driven Testing](https://spockframework.org/spock/docs/2.3/data_driven_testing.html) — 本项目的参数化测试大量使用
3. `[必读]` [Spock 官方文档 — Interaction Based Testing](https://spockframework.org/spock/docs/2.3/interaction_based_testing.html) — Mock 和 Stub 的用法
4. `[必读]` 项目中已有的测试规范 `.claude/rules/shared/testing.md` — 项目特定的测试约定
5. `[推荐]` [Spock 数据驱动测试示例](https://www.baeldung.com/groovy-spock) — Baeldung 的 Groovy/Spock 教程

**练习**：
给第 15 课的 `SocketProtocol` 写 Spock 测试（对应 task.md T23）：

```groovy
class SocketProtocolSpec extends Specification {

    def "should encode and decode correctly"() {
        given:
        def request = new RedefineRequest(type: "REDEFINE_REQUEST", payload: [...])

        when:
        def bytes = SocketProtocol.encode(request)
        def decoded = SocketProtocol.decode(new ByteArrayInputStream(bytes), RedefineRequest.class)

        then:
        decoded.type == request.type
        decoded.payload.classes.size() == request.payload.classes.size()
    }

    def "should handle max message length"(int length) {
        given:
        def bigPayload = new byte[length]

        when:
        def bytes = SocketProtocol.encode(new Message(payload: bigPayload))
        def decoded = SocketProtocol.decode(new ByteArrayInputStream(bytes), Message.class)

        then:
        decoded.payload.length == length

        where:
        length << [1, 1024, 1024 * 1024]  // 1MB message
    }

    def "should throw when length header doesn't match"() {
        given:
        // 构造一个恶意数据包：长度头说 1000，但实际数据只有 5 字节
        def malformed = new byte[1005]
        ByteBuffer.wrap(malformed).putInt(0, 1000)

        when:
        SocketProtocol.decode(new ByteArrayInputStream(malformed), Object.class)

        then:
        thrown(IOException)
    }
}
```

**验收**：能写出带 `where:` 数据驱动和 Mock 交互验证的 Spock 测试。

**预计时间**：3h

---

## 第 24 课：IDEA 插件 UI 开发 — Toolbar / StatusBar / Balloon / ToolWindow

**目标**：实现插件 UI 四大组件，提供完整用户交互。

**资料**：

1. `[必读]` [IntelliJ Platform SDK — Toolbar / Action](https://plugins.jetbrains.com/docs/intellij/plugin-actions.html) — 注册到 MainToolbar
2. `[必读]` [IntelliJ Platform SDK — Status Bar Widgets](https://plugins.jetbrains.com/docs/intellij/status-bar-widgets.html) — 右下角状态栏组件
3. `[必读]` [IntelliJ Platform SDK — Notifications](https://plugins.jetbrains.com/docs/intellij/notifications.html) — Balloon 通知
4. `[必读]` [IntelliJ Platform SDK — Tool Windows](https://plugins.jetbrains.com/docs/intellij/tool-windows.html) — 历史记录面板
5. `[必读]` [IntelliJ Platform SDK — Settings / Persistence](https://plugins.jetbrains.com/docs/intellij/settings.html) — PersistentStateComponent + Configurable

**练习**：
按 task.md T49–T60 逐一实现（这是 Phase 4 的全部任务）：

| 组件 | 关键类 | 对应任务 |
|------|--------|---------|
| 工具栏按钮 | `HotUpdateAction : AnAction` | T50 |
| 状态栏 | `HotUpdateStatusBarWidget` | T52 |
| Balloon 通知 | `HotUpdateNotifier` | T54 |
| 工具窗口 | `HotUpdateToolWindowFactory` | T56 |
| 设置面板 | `HotUpdateConfigurable` | T60 |

状态流转设计（对应 plan.md 4.1 节）：
```
灰色(无变更) → 蓝色(有待推送) → 旋转(更新中) → 绿色✓(成功,2s后恢复灰色) → 红色✗(失败,点击打开Balloon)
```

**验收**：所有 UI 元素在沙箱 IDEA 中正常渲染，状态流转正确。

**预计时间**：6h（UI 开发调试比较耗时）

---

## 第 25 课：GitHub Actions CI/CD 与 Marketplace 发布

**目标**：配置 CI 自动构建，准备 Marketplace 发布物料。

**资料**：

1. `[必读]` [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions)
2. `[必读]` [IntelliJ Platform SDK — Plugin Signing](https://plugins.jetbrains.com/docs/intellij/plugin-signing.html) — 插件签名
3. `[必读]` [JetBrains Marketplace — Publishing](https://plugins.jetbrains.com/docs/marketplace/uploading-a-new-plugin.html) — 发布流程
4. `[必读]` [intellij-platform-gradle-plugin](https://github.com/JetBrains/intellij-platform-gradle-plugin) — 注意本项目使用 Maven，但 CI 脚本可以参考 Gradle 版的思路
5. `[项目直接相关]` task.md T69–T70、T79–T80

**练习**：
编写 `.github/workflows/ci.yml`（对应 task.md T70）：

```yaml
name: CI
on: [push, pull_request]
jobs:
  build:
    strategy:
      matrix:
        java: [8, 17, 21]     # 测试不同 JDK
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: ${{ matrix.java }}
          distribution: 'temurin'
      - run: mvn clean test -pl common,agent    # 先测 common + agent
      - run: mvn clean test -pl plugin           # 再测 plugin（需要 JDK 17+）
      - run: mvn clean package -DskipTests       # 打包
      - uses: actions/upload-artifact@v4
        with:
          name: plugin-${{ matrix.os }}-jdk${{ matrix.java }}
          path: plugin/build/distributions/*.zip
```

**验收**：GitHub Actions 全部绿勾；Release 时自动上传 plugin zip 和 agent jar。

**预计时间**：2h

---

## 学习进度追踪表

| 课 | 主题 | 预计时间 | 完成 |
|----|------|---------|------|
| 1 | .class 文件结构 | 2h | [ ] |
| 2 | JVM 类加载机制 | 2h | [ ] |
| 3 | Instrumentation API 上手 | 4h | [ ] |
| 4 | redefineClasses 边界实验 | 3h | [ ] |
| 5 | ASM 基础 — 读取 class | 3h | [ ] |
| 6 | ASM 进阶 — 修改字节码 | 4h | [ ] |
| 7 | ClassFileTransformer | 3h | [ ] |
| 8 | PoC-B 方法体委托 | 6h | [ ] |
| 9 | Maven 多模块搭建 | 3h | [ ] |
| 10 | IntelliJ Platform SDK 基础 | 3h | [ ] |
| 11 | Kotlin 速成 | 2h | [ ] |
| 12 | VirtualFileListener | 2h | [ ] |
| 13 | CompilerManager 增量编译 | 2h | [ ] |
| 14 | Spring Boot 进程检测 | 3h | [ ] |
| 15 | Socket 协议编解码 | 3h | [ ] |
| 16 | Agent Socket Server | 3h | [ ] |
| 17 | Plugin Socket Client | 2h | [ ] |
| 18 | 端口发现机制 | 1.5h | [ ] |
| 19 | L1 完整链路打通 | 4h | [ ] |
| 20 | 新增类注入 | 3h | [ ] |
| 21 | 变更检测 CRC 比对 | 1.5h | [ ] |
| 22 | Agent 参数自动注入 | 2h | [ ] |
| 23 | Spock 测试框架 | 3h | [ ] |
| 24 | IDEA 插件 UI 四大组件 | 6h | [ ] |
| 25 | CI/CD + Marketplace | 2h | [ ] |
| **合计** | | **~70h** | |

---

## 与 Task 的对应关系

学完某课后，就可以直接开始对应的 Task：

| 学完第 X 课 | 可做的 Task |
|------------|-------------|
| 第 1–2 课 | 理解 T9–T18 在做什么 |
| 第 3–4 课 | T9, T10, T11, T12（PoC-A） |
| 第 5–8 课 | T13, T14（PoC-B） |
| 第 9 课 | T1–T8（项目骨架搭建） |
| 第 10–11 课 | T28–T34 等所有 Plugin 侧任务的基础 |
| 第 12–14 课 | T29–T34（文件监听 + 编译 + 进程检测） |
| 第 15–18 课 | T19–T28, T35–T36（通信协议 + Server/Client） |
| 第 19–21 课 | T37–T42（核心热更新逻辑） |
| 第 22 课 | T43–T44（自动注入） |
| 第 23 课 | 所有奇数编号测试任务 |
| 第 24 课 | T49–T60（UI 全部） |
| 第 25 课 | T65–T80（测试/文档/发布） |
