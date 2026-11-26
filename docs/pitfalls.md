# 踩过的坑

按踩到的先后顺序记录。环境：OpenViking 0.5.x，单机 dev 模式。

## 1. 批量导入别用你日常对话的模型额度

导入时 OpenViking 会给每个目录、每个文件生成摘要，十几个导入任务会并发调用 VLM。如果它和你日常用的 AI 共用一个额度，额度会被打满，日常对话跟着被限流。

**做法**：摘要/记忆提取单独配一个网关或模型，便宜、快的模型就够用。

## 2. 只导入 `.md`

项目目录里常有大量 csv、pkl、sql、日志。全量导入会把原始数据送去摘要，又慢又没用。

**做法**：`ov add-resource <dir> --include "*.md" --ignore-dirs "node_modules,.git,dist,build"`

## 3. dev 模式下取消不了任务

dev 模式下 ROOT 调 `ov task cancel` 会报 `PERMISSION_DENIED`。重启服务也没用，任务存在持久化队列里，启动后会恢复执行。

**做法**：导入前先确认范围。真要中止，停服务后把 `data/` 目录移走，再起一个空库。

## 4. ingest 的 `paths` 填根目录

会话导入配置里的 `paths` 会被自动拼上 `*/*.jsonl`。写成 glob 会匹配 0 个会话，dry-run 显示 `0 sessions` 而不是报错。

```json
"paths": ["/path/to/sessions-root"]
```

## 5. dev 模式下 Admin API 不可用

想用 `PATCH /api/v1/admin/accounts/.../users/.../settings` 设记忆类型白名单，dev 模式会返回 `PERMISSION_DENIED`。

**做法**：写在 `ov.conf` 的 `server.user_config_defaults.memory_policy` 里，作为默认策略：

```json
"server": {
  "user_config_defaults": {
    "memory_policy": { "memory_types": ["profile", "events", "entities"] }
  }
}
```

注意：策略只影响之后的提交，已经提取出的记忆要手动删。

## 6. 云文档搜索接口有条数上限

按 owner 搜索「我创建的文档」时，结果恰好停在 200 条，很像被截断。

**做法**：用「遍历云盘目录」再拉一份完整清单对比。我这里两边只差 1 篇，200 是巧合，但不对比就不知道。

## 7. 拿不到「我编辑过的文件」

云文档 API 一般只给 owner 和修改时间，不给「谁编辑过」。按「最近打开过」筛会混进大量只读资料和无关内容。

**做法**：换个思路，选一篇能代表你工作的核心文档做种子，导入它引用的文档，再往下一层。范围可控、相关性高。

## 8. 表格别塞进一个文件

两万行的表格做成一个 Markdown，摘要和向量都会失真，检索命中不到具体那一段。

**做法**：按 500 行分块，每块重复表头，并写明「第 X–Y 行，共 N 行」。

## 9. 导入会留下上传缓存

每次 `add-resource` 都会把源目录打包放进 `data/temp/upload/`，任务完成后不会自动删。我这里一次全量导入留下了约 700MB。

**做法**：同步脚本最后等所有任务完成，再清空这个目录。

## 10. 自动提取的偏好记忆大量重复

从历史会话里提取出的偏好，常见同一主题的中英文两份，或者同一个人存在两个身份目录下。

**做法**：如果你已经有手写的规则/偏好体系，就别让 OpenViking 存偏好，见第 5 条。
