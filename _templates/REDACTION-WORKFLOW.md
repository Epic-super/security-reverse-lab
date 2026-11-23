# 脱敏检查流程

> **一句话**：文章写完 → 扫一遍 → 有问题就改 → 再扫 → 干净才提交。

---

## 三层门禁

```
┌─ 第 1 层：AI 写的时候主动脱敏  ← 主力
│   （组合版提示词内置替换表 + 兜底规则 + 确认清单）
│
├─ 第 2 层：fv-redact-scan.ps1  ← 复核
│   （本地扫，5 类检测，出文件:行号）
│
└─ 第 3 层：pre-commit 钩子 + GitHub Actions  ← 兜底
    （本地提交时自动拦截；推上去后 CI 再跑一遍）
```

**设计原则**：脱敏要在**写作时就做**，扫描只是复核。
因为扫描器只能识别**模式化**的泄漏（token 格式、邮箱、IP），识别不了：
- 一句"这是我朋友公司的项目"
- 一个真实但少见的公司名
- 一段暴露业务逻辑的接口路径

这些只有 AI 在写的时候主动替换才靠谱。

---

## 日常流程

### Step 1 · 写完文章

用组合版提示词产出文章后，文章在对话里或已存成 `.md`。

### Step 2 · 扫一遍

```powershell
cd D:\Desktop\FelixVec-Git
powershell -ExecutionPolicy Bypass -File .\fv-redact-scan.ps1
```

**干净时**：
```
scanning 17 files under D:\Desktop\FelixVec-Git

CLEAN -- nothing sensitive found.
```
退出码 `0`。

**有问题时**（示例，真实输出请以你实际扫到的为准）：

<!-- redact-scan:skip -->

```
scanning 18 files under D:\Desktop\FelixVec-Git

6 potential issue(s):

== external-host (2) ==
  .\02-pentest\_demo_leak.md:3  目标站点：https://admin.SAMPLE-DOMAIN.com/api/v2/ENDPOINT
  .\02-pentest\_demo_leak.md:7  我的邮箱：<REDACTED_EMAIL>

== private-ip (1) ==
  .\02-pentest\_demo_leak.md:4  内网地址：10.0.0.1

== credential (1) ==
  .\02-pentest\_demo_leak.md:5  Token：ghp_REDACTEDEXAMPLETOKEN000000000000

== email (1) ==
  .\02-pentest\_demo_leak.md:7  我的邮箱：<REDACTED_EMAIL>

== user-path (1) ==
  .\02-pentest\_demo_leak.md:8  本机路径：C:\Users\USER_HOME\Desktop\payload.exe
```

<!-- redact-scan:end -->

退出码 `1`。

### Step 3 · 按提示改

每条给的是 `文件:行号` + 内容片段。直接定位改掉：

| 类别 | 换成 |
|---|---|
| `credential` | `<REDACTED>` |
| `email` | `<REDACTED_EMAIL>` |
| `private-ip` | `TARGET_IP` |
| `user-path` | `USER_HOME` |
| `external-host` | `TARGET` / `TARGET_SUBDOMAIN` / `example.com` |

### Step 4 · 再扫，确认 CLEAN

### Step 5 · 提交（钩子自动再扫一遍）

```bash
git add -A
git commit -m "docs: ..."
```

钩子会自动跑扫描，**有问题直接拦下**：
```
pre-commit: BLOCKED -- sensitive content detected.
```

### Step 6 · 推送后 CI 再跑一遍

`.github/workflows/secret-scan.yml` 在 push 到 main 时执行同样的检查。

---

## 扫描器怎么工作的

### 扫什么

| 项目 | 说明 |
|---|---|
| 范围 | 递归目录下所有文件 |
| 排除 | `.git/` `node_modules/` `__pycache__/` `.venv/` |
| 大文件 | >5MB 跳过 |
| 二进制 | png/jpg/pdf/zip/exe/apk 等跳过 |
| 编码 | 强制 UTF-8 读（避免中文乱码导致漏判） |

### 检测哪 5 类

| 类别 | 规则 |
|---|---|
| `credential` | `ghp_` `github_pat_` `gho_` `AKIA` `AIza` `sk-` `-----BEGIN ... PRIVATE KEY-----` |
| `email` | 通用邮箱正则，排除 `example.com` / `noreply.github.com` / `git@github.com` / `<REDACTED>` / `@qq.com` |
| `private-ip` | `10.x` `172.16-31.x` `192.168.x` |
| `user-path` | `USER_HOME` |
| `external-host` | 域名形状 + 真实 TLD，排除白名单（github.com、owasp.org 等 15 个） |

### 白名单

扫描器会跳过这些已知安全的：
`example.com` `com.example.app` `github.com` `githubusercontent.com` `github.io`
`localhost` `w3.org` `apache.org` `gnu.org` `python.org` `nist.gov` `owasp.org`
`pentestmonkey.com` `portswigger.net` `readthedocs.io` `shields.io`

以及脱敏提示词模板本身（它故意包含敏感示例值）。

### 退出码

| 码 | 含义 |
|---|---|
| `0` | CLEAN |
| `1` | 有问题（钩子据此拦截提交） |

---

## 扫描器的盲区（重要）

**扫描器认不出这些，所以别把它当唯一防线：**

| 盲区 | 例子 |
|---|---|
| 身份线索 | "这是我朋友的公司"、"我之前那个项目" |
| 少见的公司名 | 不是常见 TLD 的自建域名 |
| 业务逻辑泄漏 | 接口路径 `/api/v2/内部审批/提现` 暴露业务 |
| 上下文中的真名 | "我同事张三负责这个模块" |
| 罕见格式的凭据 | 自建系统的 token 前缀 |
| 截图里的信息 | 终端截图、工具界面截图 |
| 提交信息本身 | commit message 里的域名/邮箱 |

**这些靠第 1 层（AI 写作时主动脱敏）+ 第 3 层（人工复核）解决。**

所以扫描器定位是**兜底**，不是主力。

---

## 人工复核清单（发布前必过）

```bash
# 1. 扫机器可识别的
powershell -ExecutionPolicy Bypass -File fv-redact-scan.ps1

# 2. 扫机器认不出的（凭据）
grep -rInE "(ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)" . --exclude-dir=.git

# 3. 邮箱
grep -rInE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" . --exclude-dir=.git

# 4. 内网 IP
grep -rInE "\b(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b" . --exclude-dir=.git

# 5. 业务域名
grep -rInE "https?://[a-z0-9.-]+\.(com|cn|net|io|top|xyz|cc|vip)" . --exclude-dir=.git
```

**然后用眼睛过一遍**：
- [ ] 读起来像"某个具体的人"？→ 抽象化
- [ ] 有截图吗？→ 里面的域名/用户名/IP 也要处理
- [ ] commit message 干净吗？
- [ ] 文件名里有敏感信息吗？（`公司名_分析.md`）
- [ ] GitHub profile 本身：Nickname / Bio / 头像 / 关联账号 / 邮箱设置 都不指向真实身份

---

## 常见场景速查

| 场景 | 怎么做 |
|---|---|
| 新写的文章 | AI 脱敏 → 扫描 → 提交（钩子再扫）→ 推（CI 再扫） |
| 补写老文章 | 先跑扫描看历史遗留，再逐个修 |
| 改单个文件 | `fv-redact-scan.ps1 -Path "D:\某目录"` 只扫指定目录 |
| 想跳过钩子 | `git commit --no-verify`（**只在确认安全时用**） |
| 扫描器误报 | 加进脚本第 57 行的白名单正则 |

---

## 一句话总结

> **AI 写的时候脱敏 → 机器扫一遍 → 钩子拦一道 → CI 再兜一道 → 最后用眼睛过一遍。**
> **机器能查格式，查不出"这句话会不会暴露你"。**
