# 🛠️ AI 规则同步系统配置 SOP (v5.5)

## 🤖 支持的 AI Agent


| Agent 名称 | 配置文件 | 作用说明 |
| :--- | :--- | :--- |
| **Claude Code** | `CLAUDE.md` | **核心指令文件**。使用 `@` 语法引导 Agent 深入检索规则目录。 |
| **Codex** | `AGENTS.md` | **引导文件**。强制 Codex 遵循 `CLAUDE.md` 中的所有定义。 |

---

## 📖 背景说明
本系统深度集成于 **skills-manager** 生态：
- **统一管理**：利用 `skills-manager` 集中化管理所有 AI 技能与规范。
- **核心逻辑**：通过软链接挂载全局规则，并在 `CLAUDE.md` 中通过语义化引用（`@目录`）强制 AI 扫描规则库。

---

## 第一步：环境准备
创建个人脚本存放目录。

```bash
mkdir -p \$HOME/.local/bin
```

---

## 第二步：创建 ck-init 初始化脚本
使用 `cat` 命令生成初始化工具。该工具将使用 `@` 语法在配置文件中引用规则路径。

```bash
# 写入脚本
cat << 'EOF' > $HOME/.local/bin/ck-init
#!/bin/bash
# 背景：基于 skills-manager 体系
DEFAULT_RULES="$HOME/.skills-manager/skills/rules"
GLOBAL_RULES="${1:-$DEFAULT_RULES}"
CLAUDE_DIR="./.claude/rules"
SHARED_DIR="$CLAUDE_DIR/shared"

if [ ! -d "$GLOBAL_RULES" ]; then
    echo "❌ 错误: 找不到源目录 $GLOBAL_RULES"
    echo "请确认已安装并配置 skills-manager。"
    exit 1
fi

# 1. 建立目录与软链接
mkdir -p "$SHARED_DIR"
ln -sf "$GLOBAL_RULES"/* "$SHARED_DIR/"
echo "✅ 已挂载来自 skills-manager 的规则"

# 2. 定义规则索引
RULE_INDEX="# 规则执行准则 (Rules Directive)
- **全局共享规范**: 必须参考并遵守 @./.claude/rules/shared/ 中的通用标准。
- **项目专属规范**: 必须参考并遵守 @./.claude/rules/ 下的所有项目规范文件。
- **冲突处理**: 若项目规范与全局规范冲突，以项目规范为准。"

# 3. 安全处理函数
process_claude() {
    local file="CLAUDE.md"
    [ ! -f "$file" ] && touch "$file"
    if ! grep -q "./.claude/rules/shared/" "$file" 2>/dev/null; then
        echo -e "\n$RULE_INDEX" >> "$file"
        echo "➕ 已在 $file 末尾追加 @ 路径索引"
    fi
}

process_agents() {
    local file="AGENTS.md"
    local AGENT_CONTENT="
# Codex 行为准则
- **核心原则**: 你必须严格遵守项目根目录下的 **CLAUDE.md** 文件中的所有指令与规范。
- **规则检索**: 在执行任务前，请先完整阅读 CLAUDE.md 及其引用的 @ 规则目录。"

    if [ ! -f "$file" ]; then
        echo -n "❓ 检测到 AGENTS.md 不存在，是否为 Codex 创建并关联 CLAUDE.md? [y/N]: "
        read -n 1 -r < /dev/tty
        echo
        [[ $REPLY =~ ^[Yy]$ ]] && touch "$file"
    fi
    
    if [ -f "$file" ]; then
        if ! grep -q "CLAUDE.md" "$file" 2>/dev/null; then
            echo -e "\n$AGENT_CONTENT" >> "$file"
            echo "➕ 已在 $file 中建立 CLAUDE.md 引用关联"
        fi
    fi
}

# 4. 执行同步逻辑
process_claude
process_agents

# 5. 配置 Git 忽略
if [ ! -f .gitignore ]; then touch .gitignore; fi
if ! grep -q ".claude/rules/shared/" .gitignore 2>/dev/null; then
    echo -e "\n# Rules Shared\n.claude/rules/shared/" >> .gitignore
    echo "✅ 已在 .gitignore 中忽略 shared 目录"
fi
echo "🚀 项目初始化完成！"
EOF

# 赋予执行权限
chmod +x $HOME/.local/bin/ck-init
```

---

## 第三步：设置脚本权限
确保脚本可直接调用。

```bash
chmod +x $HOME/.local/bin/ck-init
```

---

## 第四步：验证环境变量
确保系统 PATH 包含脚本路径。

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## 第五步：日常使用说明 
###  手动执行 Shell
- **场景**：在项目中直接运行。 
- **命令**： `ck-init`。  
### 环境清理 
```bash 
rm $HOME/.local/bin/ck-init 
```
