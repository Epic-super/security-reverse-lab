# CONTRIBUTING

## 加什么

| 目录 | 收什么 | 不收什么 |
|---|---|---|
| `01-reverse/` | 分析笔记、可复用脚本、脱壳流程 | 商业软件的完整破解包、成品 keygen |
| `02-pentest/` | 方法论、真实案例（脱敏后）、测试清单 | 未授权目标的完整利用链、真实凭据 |
| `03-labs/` | 靶场环境与解题记录 | 直接复制他人 writeup |
| `04-tools/` | 自研脚本 | 第三方工具的破解版 |
| `05-writeups/` | 完整复盘 | 未脱敏的报告原文 |

## 硬性要求

1. **脱敏**：所有真实目标域名 → `TARGET` / `example.com` / `TARGET_IP`
2. **凭据**：任何 token / cookie / key / 密码 → `<REDACTED>`
3. **可复现**：写清楚前置环境，读者能照着跑
4. **结论先行**：README 开头就给结论，别让人猜
5. **有产物**：每个主题至少留一个可运行脚本或可核对的数据

## 提交流程

```bash
git checkout -b feat/<topic>
# 编辑、提交
git commit -m "rev(01-reverse/02-android): 描述"
git push origin feat/<topic>
```

## 提交前自检

```bash
# 敏感信息扫描（CI 也会跑）
grep -rInE "(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)" . \
  --exclude-dir=.git
```

任何一项命中就先处理再提交。

## 目录内固定结构

```
<主题>/
├── README.md      # 结论先行的主文档
├── notes.md       # 过程、坑点、命令
└── artifacts/     # 脚本、样本哈希、辅助文件
```

## 模板

新写笔记从 `_templates/` 复制：

- 逆向笔记 → `_templates/reverse-note.md`
- 漏洞分析 → `_templates/vuln-analysis.md`
- 靶场记录 → `_templates/lab-record.md`
