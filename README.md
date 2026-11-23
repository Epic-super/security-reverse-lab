# FelixVec · Reverse & Security Notes

> 一个把**逆向分析**和**漏洞挖掘**并排放的公开笔记本。
> 目标：让每一次挖洞、每一个脱壳、每一个复现都留下**可检索、可复用、可复现**的沉淀。

[![repo](https://img.shields.io/badge/repo-FelixVec%2FFelixVec--notes-blue)](https://github.com/FelixVec)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
![lang](https://img.shields.io/badge/content-CN%2FEN-lightgrey)

---

## 0. 三十秒看懂这个仓库在干嘛

```
01-reverse/    逆向工程      —— 静态分析 / 动态调试 / 脱壳 / 协议还原 / 补丁分析
02-pentest/    漏洞挖掘      —— Web / 移动端 / 二进制 / 云上，通用方法论与真实案例
03-labs/       靶场实践      —— Vulnhub / HTB / 自建靶场，环境与解题记录
04-tools/      工具箱        —— 自研脚本、逆向辅助、自动化小工具
05-writeups/   完整复盘      —— 一题一文，从信息收集到利用的完整链路
06-notes/      零散笔记      —— 技巧、坑点、冷知识
```

**核心原则：逆向和挖洞是一件事的两面。**
- 挖洞需要逆向（绕过客户端校验、分析 APK/EXE 的安全逻辑）
- 逆向需要挖洞视角（找的从来不是"怎么跑起来"，而是"哪里可以被操纵"）

所以本仓库不做"教程堆砌"，只做**一条能走通的路径**：见 [ROADMAP.md](./ROADMAP.md)。

---

## 1. 目录结构详解

### `01-reverse/` 逆向工程

| 目录 | 放什么 | 典型产出 |
|---|---|---|
| `01-windows/` | PE 格式、加载器、驱动、Windows API  hooking | IDA 加载脚本、函数签名库 |
| `02-android/` | APK、DEX、Smali、Frida Hook、JNI | Frida 脚本模板、绕过记录 |
| `03-ios/` | Mach-O、Objective-C runtime、越狱检测 | 逆向笔记 |
| `04-unpack/` | 各类壳（NSIS/UPX/自研）的脱壳过程 | 脱壳脚本、内存 dump 流程 |
| `05-protocol/` | 私有协议还原、加密算法定位、签名算法 | Python 实现、请求构造器 |

每个子目录固定三件套：

```
<主题>/
├── README.md        # 结论先行：这个技术讲什么、什么时候用
├── notes.md         # 过程记录：踩过的坑、命令、关键判断
└── artifacts/       # 脚本、样本哈希、ida/py 辅助文件
```

### `02-pentest/` 漏洞挖掘

按**攻击面**而不是按漏洞类型分目录，因为挖洞时你面对的是"一个网站"而不是"一类漏洞"。

| 目录 | 覆盖 |
|---|---|
| `01-web/` | SQLi / XSS / SSRF / XXE / 反序列化 / 越权 / 逻辑 / 上传 / SSRF |
| `02-mobile/` | APK 越权、证书固定、Root/Frida 检测绕过、深层 API |
| `03-binary/` | 二进制里的隐藏接口、硬编码密钥、越狱检测、反调试 |
| `04-cloud/` | S3/存储桶权限、IAM 策略、容器逃逸、CI 配置泄露 |

### `03-labs/` 靶场

每个靶场一个目录，包含：
- `env.md` —— 怎么搭起来（Dockerfile / Vagrantfile / 虚拟机镜像说明）
- `walkthrough.md` —— 解题思路（自己写，别抄）
- `flag.md` —— 拿到 flag 的完整证据链

### `05-writeups/` 复盘

**这是最有价值的目录。** 一篇好的 writeup 结构固定：

```
1. 背景（目标是什么，为什么做）
2. 信息收集（怎么发现攻击面）
3. 漏洞分析（根因，附代码/请求/二进制证据）
4. 利用链（怎么从漏洞走到影响）
5. 修复建议（可落地的补丁，不是"建议做输入校验"）
6. 反思（我漏了什么，下次怎么更早发现）
```

---

## 2. 命名与提交规范

**分支：**

```
main            # 稳定内容，只放已验证的结论
feat/<topic>    # 新主题
lab/<ctf-name>  # 靶场解题
fix/<path>      # 修文档
```

**提交信息：**

```
[type](scope): 简短说明

type:  docs | rev | pentest | lab | tool | chore
scope: 01-reverse/02-android, 02-pentest/01-web/sqli ...
```

示例：

```
rev(01-reverse/02-android): Frida 绕过 root 检测的四种思路
pentest(02-pentest/01-web): JWT alg=none 与 kid 注入组合利用
lab(03-labs/01-vulnhub): DC-3 提权路径整理
```

**文件命名：**

```
<序号>-<主题>-<要点>.md
```

例：`02-frida-bypass-root-detect.md`、`01-sqli-time-based-blind.md`

---

## 3. 安全红线（自己定的规矩）

这个仓库会被搜索引擎收录，所以：

1. **不放任何真实目标站点的完整利用链**——用 `TARGET` / `example.com` / `lab.internal` 占位
2. **不放有效的 token、密码、cookie、API Key**——用 `<REDACTED>` 代替，并且提交前跑一遍扫描
3. **不放商业软件的完整破解包或注册码生成器**——写**分析思路**和**技术原理**，不写可直接滥用的成品
4. **CVE 复现写在自己的 lab 环境或公开靶场**——靶场地址写清楚，方便别人复现
5. **所有命令都写明前置环境**——避免读者在自己生产机器上误操作

> 这不是免责声明，是**让这个仓库能长期公开存在**的前提。公开的逆向/挖洞笔记，靠的是可复现和可验证，不是靠敏感度。

---

## 4. 本地使用

```bash
# 克隆（SSH 通道，见 README 的"通道"章节）
git clone git@github.com:FelixVec/FelixVec-notes.git

# 提交署名用 GitHub noreply 邮箱，避免把真实邮箱写进 commit
git config user.name  "FelixVec"
git config user.email "250156135+felixvec@users.noreply.github.com"

# 推送
git push origin main
```

---

## 5. 索引

- [ROADMAP.md](./ROADMAP.md) —— **先看这个**，12 周学习与产出路线
- [WEEKLY.md](./WEEKLY.md) —— 每周执行节奏，防止"又没方向"
- [CONTRIBUTING.md](./CONTRIBUTING.md) —— 怎么往里加东西
- [TEMPLATES/](./_templates/) —— writeup / 逆向笔记 / 靶场记录模板
- [**PROMPTS.md**](./_templates/PROMPTS.md) —— **把对话流水账变成小白能看懂、能复现的文章**
---

## 6. 写作流程（对话 → 文章）

```
对话流水账
   │
   ├─ 1. 起稿：fv-draft.ps1 -Type reverse|vuln|lab|writeup -Title "..."
   │      → 生成 README.md（正文骨架）+ notes.md（过程）+ artifacts/
   │
   ├─ 2. 让 AI 写：复制 _templates/PROMPTS.md 里对应方向的提示词，
   │      粘到「你当时做这件事的那个对话」里，连同你的过程一起
   │      → 它输出完整文章
   │
   ├─ 3. 审稿：复制「自检清单」提示词 + 文章正文，开新对话
   │      → 逐条挑毛病
   │
   ├─ 4. 修补：把审稿意见发回第 2 步的对话，让它改
   │
   └─ 5. 归档：文章进 README.md，过程留在 notes.md，脚本进 artifacts/
```

一键起稿：

```powershell
powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type reverse -Title "NSIS 壳脱壳过程"
powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type vuln    -Title "JWT kid injection"
powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type lab     -Title "DC-3"
powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type writeup -Title "first bounty report"
```

---

## 7. 单个对话 → 价值提炼（脱敏优先）

> 场景：你有一个做完就归档的对话，里面有方法、有原理、有弯路，
> 但也混着真实域名、真实 token、内部系统信息。

### 我该贴哪个提示词？

```
这次对话里有"真实的漏洞发现"吗？
│
├─ 有，而且是逆向出来的（客户端校验可绕过）
│    └─▶ 组合版 C · 混合
├─ 有，是服务端 / 接口 / 配置类的
│    └─▶ 组合版 A · 漏洞方向
├─ 没有漏洞，纯技术分析（脱壳 / 还原算法 / 还原协议）
│    └─▶ 组合版 B · 逆向方向
└─ 不确定 / 混合杂谈
     └─▶ 组合版 D · 通用
```

**全都在 [`_templates/PROMPT-combos.md`](./_templates/PROMPT-combos.md)**，
每个组合版都是**一整段可直接复制**的成品，不用自己拼。

| 组合版 | 覆盖 |
|---|---|
| **A · 漏洞方向** | 根因分析 / 最小复现请求 / 攻击面分段 / CVSS 理由 / 可落地修复 |
| **B · 逆向方向** | 地址三件套辨析 / 关键函数给证据 / **算法推导链** / 断点理由 / 工具局限 |
| **C · 混合** | 逆向出来的漏洞 —— 主线必须是漏洞，逆向只展开到"服务于可利用性" |
| **D · 通用** | 方向不确定时的兜底 |

### 三份提示词文件的分工

| 文件 | 定位 | 什么时候用 |
|---|---|---|
| [`PROMPT-combos.md`](./_templates/PROMPT-combos.md) | **组合成品**，一整段复制 | **日常主力** |
| [`PROMPT-single-dialog-summary.md`](./_templates/PROMPT-single-dialog-summary.md) | 单对话提炼 + 两个变体 | 变体 A（只要方法论）、变体 B（只脱敏不改内容） |
| [`PROMPTS.md`](./_templates/PROMPTS.md) | 完整提示词库 + 写作契约 + 审稿清单 | 多段对话合成一篇长文；发布前审稿 |

### 脱敏是硬门禁

所有组合版都内置了：

- 14 类信息的替换表（域名、IP、token、license/机器码、人名、公司、内部系统、
  文件路径用户名、数据库/表名、客户标识……）
- 「不确定算不算隐私就替换掉」的兜底规则
- **「⚠️ 需要我确认」清单** —— AI 拿不准的内容单独拎出来给你定夺，不擅自写进去
- 输出**替换对照表**，你能逐条复核改了什么
- 逆向类额外针对 license / 机器码 / 注册码生成算法做了专门约束

### 验证

```powershell
powershell -ExecutionPolicy Bypass -File fv-redact-scan.ps1
```

5 类检测：凭据 / 邮箱 / 内网 IP / 用户名路径 / 业务域名。已用假样本校准，当前仓库 **CLEAN**。

**完整流程见 [`_templates/REDACTION-WORKFLOW.md`](./_templates/REDACTION-WORKFLOW.md)** —— 三层门禁：
AI 写作时脱敏 → 本地扫描复核 → pre-commit 钩子拦截 → GitHub Actions 兜底。

> **扫描器认不出的**：身份线索、少见公司名、业务逻辑泄漏、截图里的信息、commit message。
> 这些靠**人工复核清单**。机器能查格式，查不出"这句话会不会暴露你"。
