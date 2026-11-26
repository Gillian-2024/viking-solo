# 云文档导出器

同步脚本不关心你用哪家云文档、用什么工具导出，只要求导出器满足下面的约定。

## 接口约定

导出器是一个可执行脚本，按子命令调用：

| 子命令 | 输入 | 输出 |
|---|---|---|
| `list-owned` | 无 | 把你本人创建的文档清单写到 `owned_list`（JSON 数组，每项含 `id`、`type`、`title`） |
| `export-docs` | `owned_list` | 每篇文档写成一个 `.md` 到 `~/.openviking/cloud/docs/` |
| `export-tables` | `owned_list` | 每张表写到 `~/.openviking/cloud/docs/tables/<表名>/part_NNN.md` |
| `export-refs <depth> <id>...` | 种子文档 id | 第 N 层引用写到 `~/.openviking/cloud/refs/l<N>/`，下一层种子写到 `l<N>_next.json` |

## 输出格式

每个 `.md` 开头带 frontmatter，便于增量判断和溯源：

```markdown
---
source: cloud
type: docx            # docx / sheet / bitable / slides
id: <文档 id>
title: <标题>
modified_time: <ISO 时间>
---

<正文 Markdown>
```

表格分块额外带 `section` 和 `rows: 1-500 of 20621`。

## 建议的实现要点

- **增量**：把 `id -> modified_time` 存进一个状态文件，没变的文档跳过
- **表格**：整表读完再切块，每块重复表头；空行丢弃
- **引用展开**：用正则从正文里提取文档链接；知识库节点先解析成实际文档 id；已导入过的跳过，避免重复
- **校验 200 条上限**：如果平台搜索接口有条数上限，用目录遍历再拉一份清单对比

## 飞书用户

可以不写导出器，直接用 OpenViking 官方的飞书直连：

```bash
ov add-resource "https://<你的租户>.feishu.cn/docx/<doc_id>" --to viking://resources/cloud/<name>
```

需要在 `ov.conf` 配应用凭证，或在 `args` 里传 user token。支持 docx、wiki、sheets、多维表格、云盘目录，并可设定时同步。详见 OpenViking 资源管理文档。
