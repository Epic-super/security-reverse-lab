# ROADMAP · 从"没方向"到"有产出"

> 这份路线图的唯一目的：**让你每周打开这个仓库都知道该干什么、干完留下什么。**
> 节奏是 12 周，每周 4–6 小时。可以按自己基础加速，但**顺序别乱**。

---

## 为什么"没方向"

做逆向/挖洞的人最常见的三个坑：

| 症状 | 根因 | 解法 |
|---|---|---|
| 收藏了 200 篇教程，一篇没复现 | 没有**产出定义** | 每个主题必须留下一个 `notes.md` + 一个可运行脚本 |
| 学得很散，逆向和挖洞互不相干 | 按**知识分类**学，不是按**攻防链路**学 | 按 §1 的四阶段走，每阶段两个方向交叉 |
| 三个月后还在"入门" | 没有**外部倒逼** | 公开仓库 + 真实提交记录 = 天然 deadline |

---

## §0 · 第 0 周：把地基打好（必做，2 小时）

**目标**：一条能推代码的通道 + 一个干净的公开仓库。

- [x] 本地 SSH 密钥生成与 GitHub 账号绑定（见仓库根 README "通道"章节）
- [x] `git config user.email` 改成 noreply 形式
- [x] 个人资料里 Name 填 `FelixVec`，Bio 写清方向（reverse & security）
- [x] 开启 `Keep my email addresses private`
- [x] 建立本文档的目录结构
- [x] `git init` + 首次 push

**产出**：一个 100% 属于 `FelixVec` 的公开仓库，署名干净。

> 隐私要点见文末 §5。**先不要关联 Google 账号**，GitHub 的 OAuth 应用会展示你 Google 账号的头像和姓名；用 GitHub 自己的账号密码 + 2FA + passkey 就够，不漏真名。

---

## §1 · 阶段一（1–3 周）：静态分析基本功

**这一阶段只做一件事：看到任何二进制，能在 30 分钟内说清楚它做了什么。**

### 第 1 周：Windows PE 与静态分析

| 读 | 练 | 产出 |
|---|---|---|
| PE 头结构、节区、导入表、IAT | 用 `PE-bear` / `CFF Explorer` 拆一个自己装的软件 | `01-reverse/01-windows/01-pe-basics/README.md` |
| x86 汇编入门（够用就行） | IDA / Ghidra 走一遍 `strlen` 的调用 | 同上 `notes.md` |
| 字符串与交叉引用 | 从一个字符串反推调用点 | 同上 `artifacts/` 脚本 |

**推荐目标**：随便找个国产小工具（安装包、系统工具都行），把它的主流程函数列出来。

### 第 2 周：动态调试与 API 监控

| 读 | 练 | 产出 |
|---|---|---|
| x64dbg / WinDbg 基本操作 | 断在 `VirtualAlloc` / `CreateFile` | `01-reverse/01-windows/02-debugging/README.md` |
| API Hook 原理 | 用 Frida 打印目标进程的敏感 API 调用 | `01-reverse/01-windows/02-debugging/notes.md` |
| 内存dump与重建导入表 | dump 一个运行中的模块并让它能被静态工具打开 | `artifacts/dump_module.py` |

### 第 3 周：**交叉点：逆向一个真实校验逻辑**

这一步是整个路线的枢纽。找一个有 license 校验的公开小工具（自己开发的 demo、或 GitHub 上的开源示例），完整走一遍：

```
静态定位校验函数 → 动态断点看参数 → 还原算法 → 写一个 keygen（自用/自研demo）→ 写分析笔记
```

**产出**：`01-reverse/01-windows/03-license-check-analysis/`
- `README.md`：校验逻辑的完整还原（伪代码级）
- `artifacts/keygen.py`：算法实现
- `notes.md`：整个过程的判断依据和走过的弯路

> 这一篇写好了，你的技术叙事就成立了 —— 从"会用工具"变成"看得懂逻辑"。

---

## §2 · 阶段二（4–6 周）：移动端与协议

**目标：能完整处理一个 APK 或 IPA，并还原一个私有协议。**

### 第 4–5 周：Android 逆向

```
APK 解包 → apktool 反编译 → jadx 看 Java → smali 看细节
        → Frida 运行时 Hook（Java 层 + native 层）
        → 抓包看请求 → 定位签名/加密 → 还原
```

**产出**：`01-reverse/02-android/01-apk-deep-dive/`
- 一篇完整笔记：目标 APK 的关键类、native so 的加载、加密调用点
- `artifacts/frida/`：至少 3 个可复用 hook 模板（Java / native / 绕过检测）

### 第 6 周：私有协议还原

选一个你日常用的 App（自己的、或有 API 文档的公开服务），抓包分析：

```
参数构造 → 加密字段定位 → 算法还原 → 签名生成 → 用 Python 重放请求
```

**产出**：`01-reverse/05-protocol/<服务名>/`
- `README.md`：协议结构说明（字段表 + 时序）
- `artifacts/client.py`：纯 Python 实现，不依赖原 App

> 交叉点：**如果 App 接口存在越权/注入，那这就是一个漏洞**，顺手写进 `02-pentest/02-mobile/`。

---

## §3 · 阶段三（7–9 周）：漏洞挖掘实战

**目标：从"会打靶场"切换到"能交漏洞"。**

### 第 7 周：Web 漏洞方法论重建

不要按 OWASP Top 10 背，按**攻击面**过一遍：

```
信息收集 → 子域/端点枚举 → 认证点分析 → 授权点分析
       → 注入类(参数型/上下文型) → 业务逻辑 → 权限边界
```

每类都写一篇"**怎么找**"而不是"漏洞是什么"：

| 主题 | 产出文件 |
|---|---|
| 端点枚举 | `02-pentest/01-web/01-endpoint-enumeration/README.md` |
| 越权（水平/垂直） | `02-pentest/01-web/02-idor/README.md` |
| SQLi 实战 | `02-pentest/01-web/03-sqli/README.md` |
| SSRF 与云元数据 | `02-pentest/01-web/04-ssrf/README.md` |
| 反序列化 | `02-pentest/01-web/05-deserialization/README.md` |
| 业务逻辑漏洞 | `02-pentest/01-web/06-logic/README.md` |

每篇统一结构：**怎么发现 → 怎么验证 → 怎么提报告 → 怎么修**。

### 第 8 周：移动端与二进制测试面

- `02-pentest/02-mobile/`：APP 安全测试清单 + 一篇实战
- `02-pentest/03-binary/`：客户端本地校验的绕过思路 + 一篇实战

**这是逆向和挖洞的交汇点**：上一阶段你还原的校验逻辑，这里变成"这个校验能被绕过吗"。

### 第 9 周：一次真实漏洞提交流

去 HackerOne / Bugcrowd / 漏洞盒子，或自建靶场。目标：**走完一次完整提交流**。

```
选题 → 信息收集 → 复现 → 影响面评估 → 写报告 → 提交 → 跟进修复
```

**产出**：`05-writeups/01-first-real-report/`
（对外脱敏，内部保留完整复现步骤）

---

## §4 · 阶段四（10–12 周）：体系化沉淀

### 第 10 周：靶场串讲

在 `03-labs/` 里串讲 3–4 个经典靶场（Vulnhub / HTB），重点不是"通关"，而是**每个靶场练的是哪种能力**：

| 靶场 | 能力点 |
|---|---|
| DC-1 | 基础枚举 + Web 弱口令 + 提权 |
| DC-3 | 目录枚举 + 模板注入 + 提权 |
| Kioptrix | 漏洞利用链 + 权限提升 |
| HTB Machine | 综合 |

每个产出 `env.md` + `walkthrough.md`（自己写的）+ `flag.md`。

### 第 11 周：自建靶场

把你在公开靶场学到的技术，**自己复刻一个**出来。这是把"会做题"变成"懂原理"最快的办法。

```
Dockerfile 一键起 → 故意留一个 Web 漏洞 + 一个提权路径 → 自己打一遍 → 写 env.md
```

**产出**：`03-labs/03-selfhosted/<你的靶场名>/`

### 第 12 周：总结与对外输出

- 把 12 周的产出整理成 **3–5 篇对外的技术文章**（博客 / 知乎 / 公众号 / X）
- 每篇挑一个最硬的点：脱壳全过程、协议还原、完整利用链
- 更新本文件勾选完成度

---

## §5 · 隐私：不暴露真名与真实身份

你说"怕关联 Google 账号暴露姓氏"，这个担心是对的。**结论：不要关联 Google。**

GitHub 的第三方 OAuth 授权页会显示该 Google 账号的**姓名和头像**，授权后这些信息会以 **OAuth 应用的公开 profile 形式展示在 GitHub 账号的关联列表里**（Settings → Applications → Connected accounts）。这是一个真实的**身份关联泄漏点**，很多人不知道。

### 该怎么做

| 项 | 设置 | 理由 |
|---|---|---|
| 关联账号 | **只留 GitHub 自己的密码**，不关联 Google/Apple | 避免 OAuth 暴露姓名与邮箱 |
| Profile Name | `FelixVec`（或 `Felix V.`） | 对外只暴露昵称 |
| Profile Email | **GitHub noreply**：`215370993+Epic-super@users.noreply.github.com` | commit 不带真邮箱 |
| Git config | 仓库内设 `user.email` = noreply | commit 历史不泄漏 |
| `Keep my email addresses private` | 开 | GitHub 不公开你的真实邮箱 |
| 2FA | 开（App + 硬件密钥） | 账号安全 |
| 登录方式 | Passkey 优先 | 不依赖第三方 |
| 头像 | 用生成的 avatar，不用真人照片 | 避免人脸关联 |
| 个人简介 | 只写技术方向，不写公司/城市/学校 | 减少归因面 |

### 更彻底的隔离（可选但推荐）

因为你的真实身份绑在 QQ 邮箱上，而 FelixVec 是"记录和分享漏洞/逆向知识"的账号 —— **这两个身份在真实世界里是有关联的**（同一台电脑、同一网络环境、同一支付方式）。GitHub 的风控主要看 IP 段、行为模式、设备指纹，所以：

1. **仓库内容里的每个 payload 目标用 `TARGET` / `example.com` 占位**，不要写真实站点域名 —— 这同时也是让笔记可公开的前提
2. **commit 用 noreply 邮箱**，且**不要在多个账号间复用同一 commit message 习惯**
3. **个人 profile 不要出现姓氏拼音、中文名、公司名**
4. **如果以后要接漏洞赏金**，用 FelixVec + 专门的邮箱（不要用 QQ 邮箱），赏金平台账号与 GitHub 可以不一致

### 关于 QQ 邮箱

GitHub 现在强制要求邮箱验证，且**不允许一个邮箱注册多个账号**。你原来的 Epic-super 已经占用了你的 QQ 主邮箱。所以 FelixVec **必须用另一个邮箱**。

推荐做法：**新注册一个专用邮箱**（任意一家邮箱服务商都行），只用于 FelixVec，绑 GitHub，然后：
- GitHub profile email 设为 noreply（对外）
- 账号验证邮箱设为这个专用邮箱（只收 GitHub 系统邮件）

> 如果一定要用 QQ 系：QQ 邮箱支持 `昵称@qq.com` 形式的**别名邮箱**（一个主号可带多个），可以用 `felixvec@qq.com` 这样的别名，绑定到 FelixVec 账号上 —— 这样对外完全看不到你的主号。

---

## §6 · 每周固定动作（防止"又没方向"）

固定下来，每周日花 30 分钟：

```
1. 打开本文件，看当前阶段还剩几项没勾
2. 更新仓库：本周的 notes.md + artifacts，commit + push
3. 更新仓库 README 的"最近更新"区
4. 在 Issues 里开一个下周的小任务
```

**每周只承诺一件事。** 一次列十条然后一条不动，是没方向的真正原因。

---

## §7 · 避坑清单

- ❌ 抄教程的**代码**然后说"我学过" —— ✅ 抄**思路**，自己重写一遍
- ❌ 追求工具数量 —— ✅ 一个工具吃透，胜过十个只会打开的
- ❌ 只看不动手 —— ✅ 每个知识点强制配一个可运行脚本
- ❌ 追求漏洞数量 —— ✅ 追求**深度**，一个 RCE 比十个信息泄露值钱
- ❌ 提交含密钥的代码 —— ✅ 提交前 `grep -rE "(ghp_|AKIA|-----BEGIN)" .`
- ❌ 一个人闷头 —— ✅ 公开仓库本身就是最好的反馈源

---

**下一步**：打开 §0 的清单，把通道验证跑通，然后从 §1 第 1 周开始。
