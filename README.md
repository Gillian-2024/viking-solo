# viking-solo

单机专属工作知识库，不用每次开会话都给 AI 交代一遍背景，它都能自己找到～把本地项目、飞书文档和历史会话整理进本机 OpenViking，让 AI 每次对话自动召回你的工作上下文。

> Stop re-explaining yourself to AI: your docs, definitions and past decisions are recalled automatically.

viking-solo 是一套**单人、单机**的工作知识库搭法：把你本地的项目笔记、云文档和 Claude Code 历史会话整理进本机的 OpenViking，再通过 OpenViking 的 Claude Code 插件，让每次对话开始前自动召回相关上下文。

底座用的是**火山引擎开源的 [OpenViking](https://github.com/volcengine/OpenViking)**：面向 AI Agent 的上下文数据库，用 `viking://` 虚拟文件系统组织资料、记忆和技能，每层目录自动生成摘要，检索可以限定在某个子目录内。本仓库用的是它的开源自部署版（AGPLv3），没有用火山引擎的托管服务，数据全部留在本机。

viking-solo 不是一个新产品，而是在 OpenViking 之上的一组配置 + 脚本 + 踩坑记录，不修改 OpenViking 本身的代码。OpenViking 需要单独安装。

---

## 我在做什么

我是一名产品经理，日常大量用 Claude Code 写 PRD、跑数、做实验回收。痛点很具体：

- 资料散在三处：本地项目目录、云文档、过去几百轮 AI 会话
- 每开一个新会话，都要重新交代「我负责什么、这个口径是什么、上次怎么定的」
- AI 只能 grep 关键词，换个说法就找不到

目标：一个**只装我自己这部分**的知识库，跑在本机，每天自动更新，所有 Claude Code 会话共用。

## 我做了什么（真实效果）

| 项 | 规模 |
|---|---|
| 本地项目空间 | 15 个（只收 `.md`） |
| 个人记忆 / 技能文件 | 约 650 个 `.md` |
| 本人创建的云文档 | 约 200 篇（含表格，按 500 行分块全量导入） |
| 引用文档 | 以一篇核心文档为种子，向下展开 2 层引用 |
| 历史 AI 会话 | 141 个会话 / 6,569 条消息，提取出画像、事件、实体 |

检索验证：用 9 个真实问题测试，Top1 全部命中正确文档，相似度 0.81–0.90。

带来的增量：

- **云文档可检索**：不用再贴链接让 AI 一篇篇读
- **跨来源统一检索**：一次查询覆盖本地项目、记忆、云文档
- **语义检索**：换个说法也能找到
- **会话变经验**：历史会话里提取出「我负责什么」的画像，新会话启动自动注入
- **召回自动发生**：每次提问前插件自动检索，不依赖 AI 记得去查
- **每天自动更新**：定时增量同步

没解决的：召回内容可能过期（以当天同步为准），关键数字仍要回原文核对。

## 你想做，可以怎么做

### 架构

```
本地项目 .md ─┐
个人记忆 .md ─┤
云文档导出器 ──┼─> ov add-resource ──> OpenViking (127.0.0.1:1933)
AI 会话日志 ──┘      (每日增量)          ├─ embedding: 本地 Ollama bge-m3
                                          ├─ 摘要/记忆提取: 任意 OpenAI 兼容网关
                                          └─> Claude Code 插件：每次提问前自动召回
```

### 前置条件

- macOS（用 launchd 做自启和定时；Linux 可改 systemd）
- Python 3.10+、[uv](https://docs.astral.sh/uv/)、Node.js 18+
- [Ollama](https://ollama.com)
- 一个 OpenAI 兼容的 Chat Completions 接口，用于生成摘要和提取记忆

### 步骤

1. **装依赖**
   ```bash
   brew install ollama && brew services start ollama
   ollama pull bge-m3
   uv tool install openviking
   ```
2. **写配置**：复制 `config/ov.conf.example` 到 `~/.openviking/ov.conf`，填你的网关地址和模型名；API key 写进 `~/.openviking/llm.key`（`chmod 600`），不要写进配置文件
3. **自检**：`openviking-server doctor`
4. **常驻服务**：`scripts/install-launchd.sh` 会安装两个 launchd 任务——服务常驻、每日同步
5. **配置你的数据源**：复制 `config/sources.example.json` 到 `~/.openviking/sources.json`，列出要导入的目录和云文档种子
6. **首次导入**：`scripts/daily-sync.sh`
7. **接入 Claude Code**：按 OpenViking 官方文档安装 `openviking-memory` 插件，然后把 `config/ovcli.conf.example` 里的插件开关合并进 `~/.openviking/ovcli.conf`

### 云文档导出器

`exporters/` 定义了一个很薄的接口：**输入文档清单，输出带 frontmatter 的 Markdown**。同步脚本只依赖这个接口。

你需要按自己的云文档平台实现它，可选方式：

- 用平台开放 API 自己实现（参考 `exporters/README.md` 里的接口约定）
- 如果是飞书，也可以直接用 OpenViking 官方的飞书直连：`ov add-resource <飞书 URL>`，配合应用凭证或 user token，详见 OpenViking 资源管理文档

仓库里的导出逻辑保留了几个设计：

- **按修改时间增量导出**，没改的文档跳过
- **表格全量导出、按 500 行分块**，每块带表头和「第 X–Y 行，共 N 行」
- **按引用逐层展开**：给定种子文档，向下抓 N 层引用，去重

## 设计取舍

| 选择 | 原因 |
|---|---|
| 本地文件是原件，OpenViking 只做检索层 | 现有的 git、备份、手写规则不受影响；OpenViking 坏了也不丢数据 |
| 只导入 `.md` | 项目目录里的 csv/pkl/sql 是原始数据，送去摘要没意义还烧钱 |
| 插件关闭 auto-capture | 每轮自动写入会产生大量重复、互相矛盾的记忆；会话沉淀改由每日同步批量做 |
| 记忆类型只保留 profile / events / entities | 偏好类记忆最容易和你手写的规则打架，以手写规则为准 |
| 摘要模型不用你日常对话的那个额度 | 批量导入会并发调用，会把额度打满，连带日常使用被限流 |

## 踩过的坑

见 [docs/pitfalls.md](docs/pitfalls.md)。

## 目录

```
config/      配置模板（不含任何密钥）
scripts/     服务启动、每日同步、会话导入、launchd 安装
exporters/   云文档导出器接口与说明
docs/        踩坑记录
```

## 致谢

- [OpenViking](https://github.com/volcengine/OpenViking)：火山引擎开源的 AI Agent 上下文数据库，本方案的全部存储、检索、记忆提取和 Claude Code 插件都来自它。使用前请阅读其 [文档](https://docs.openviking.ai) 和许可证（主项目 AGPLv3）。
- [Ollama](https://ollama.com) 与 [BGE-M3](https://huggingface.co/BAAI/bge-m3)：本地 embedding。
