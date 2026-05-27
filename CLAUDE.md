# Claude 使用规则

## 文件操作

- **用户没有明确要求时，不得创建、修改或写入任何文件。** 只检索和汇报结果。
- **执行"恢复 / 回滚"类操作前（如 `git checkout --`、`git reset --hard`、`git restore`），必须先 `git diff` 检查未提交内容，确保不会把用户尚未提交的修改一起回滚掉。**

## 文档格式

- **强制遵从：** [chinese-copywriting-guidelines/README.zh-Hans.md](https://github.com/sparanoid/chinese-copywriting-guidelines/blob/master/README.zh-Hans.md)

## 事实准确性

- **所有结论必须基于现有资料（源码、文档、日志等），不得凭直觉推理或"想当然"给出确定性结论。** 不确定时，先查证，再回答。
- 对于技术事实（如阶段顺序、API 行为、版本差异等），优先查阅官方源码或文档，而非依赖内部知识或逻辑推导。
- **搜索无结果时，直接承认不了解或没有相关资料，不得自行编造。** 承认"不知道"比给出错误答案更负责任。

## 札记文件夹规则

- 对于 `note/碎碎念/札记/` 下的所有文章，**frontmatter 与写作规则统一遵循 `note/碎碎念/札记/template.md`**。
- 正文章节结构不做固定要求，按内容自由组织。 