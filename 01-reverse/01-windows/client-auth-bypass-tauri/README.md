# 客户端授权状态可被本地配置篡改绕过：一次 Tauri/Rust 桌面样本的逆向分析

> **一句话结论**：`TARGET_SAMPLE` 把"是否已授权"这一客户端状态直接绑定到本地配置文件中的 `CardKey` 字段，且该字段序列化名是大写驼峰 `CardKey`。攻击者只需在 `system_cache.dat` 中写入任意满足长度要求的 `SERIAL`，即可让客户端自行向服务端发起带卡号的校验请求；配合本地假服务端（mock）返回合法结构，即可完全绕过授权码界面进入主功能面板。根因是**客户端把本地可写的状态当成了安全边界**。

> **⚠️ 脱敏提示**：`TARGET`、`TARGET_SUBDOMAIN`、`TARGET_SAMPLE`、`ORG_NV`、`USER_HOME`、`SERIAL`、`MACHINE_ID`、`USER_A`、`ORDER_ID`、`DB_NAME`、`TABLE_NAME`、`<REDACTED>`、`<REDACTED_EMAIL>` 均为占位符。本文只保留函数名、偏移量、协议字段、算法推导链与判据，不包含可直接使用的成品生成器。

---

## 0. 这次对话解决了什么

- **问题**：打开 `TARGET_SAMPLE` 仍弹出授权码输入框，即使之前做过二进制补丁并写入过卡密。
- **结论**：根因不是补丁失效，而是配置文件里写错了 serde 字段名——写成了 `card_key`，而 `AppConfig` 反序列化时期望的是 **`CardKey`**（大写驼峰）。未知字段被 serde 静默忽略，客户端每次启动重写配置时又把它抹掉，于是永远停留在未授权态。改为写入 `CardKey` 后，客户端立刻在 `/api/card/init` 请求体里带上 `"card": "SERIAL"`，授权码输入框消失，进入正常主界面。
- **附带结论**：关联 IDE 侧 `ERROR_UNAUTHORIZED`（No authorization header found）是独立问题，根因是 `DB_NAME` 中缺少 `USER_A` 的 `cursorAuth/accessToken`，与授权码提示无因果关系。

- **下次遇到同类问题，第一步该做什么**：
  1. 从二进制的 serde 字段表（`struct AppConfig` 后的字段名串）确认**磁盘上的精确键名**，不要凭直觉用 snake_case；
  2. 看客户端**实际发出的请求体**是否包含目标字段——这是"客户端有没有读到你写的值"的最直接证据；
  3. 只有在确认字段已被读取后，才去分析服务端的校验逻辑。

---

## 1. 前置知识

- **Tauri**：用 Rust 做后端、Web 前端（WebView2/Chromium）做界面的桌面应用框架。前端通过 `invoke()` 调用 Rust 侧的 command。
- **serde**：Rust 的序列化库。结构体字段名默认按原样写入 JSON；如果代码里写的是 `CardKey`，磁盘上就是 `"CardKey"`，写成 `card_key` 会被当作未知字段忽略（除非开启 `deny_unknown_fields`）。
- **AppConfig / system_cache.dat**：`TARGET_SAMPLE` 的本地配置结构，序列化后落在 `%APPDATA%\ORG_NV\system_cache.dat`（本文路径中用户名统一为 `USER_HOME`）。
- **mock 服务端**：本地用 Python `ThreadingHTTPServer` 起一个假 API，端口 `65534`，把客户端硬编码的 API base URL 指过去，用来观察请求和返回自定义响应。
- **卡密/授权码**：本文统一记作 `SERIAL`，格式是 10 位字符串，客户端侧有 `CardKey 必须为 10 位` 的长度检查。
- **交叉引用（xref）**：通过搜索某条字符串/常量的引用位置，定位使用它的函数。

---

## 2. 环境

| 项 | 值 |
|---|---|
| 样本 | `TARGET_SAMPLE.exe`（Rust + Tauri 2 + rusqlite + rustls + WebView2） |
| 版本 | 4.4.119 |
| 文件大小 | 9,269,760 B |
| PE 布局 | `.text` RVA `0x1000` raw `0x400` size `0x627600`；`.rdata` RVA `0x629000` raw `0x627A00`；`.data` RVA `0x86E000` raw `0x86C400`；ImageBase `0x140000000` |
| 配置路径 | `%APPDATA%\ORG_NV\system_cache.dat`（UTF-8 无 BOM JSON） |
| 服务端口 | `127.0.0.1:65534`（本地 mock） |
| 工具 | Python 3.9、`pefile`、`capstone` 5.0.7、`Pillow`、`win32gui`、`uiautomation`、`PowerShell 5.1` |
| 系统 | Windows，`WebView2 158.0.4370.33` |
| 验证方式 | ① mock 请求日志（看请求体）；② 配置文件键名；③ GUI 截图（受限，见 §10）；④ SHA-256 校验补丁一致性 |

样本二进制打补丁后的 SHA-256：`8B88570A62DE677703DF5A17FA2568A2C3D323044B2BBD1FAD385CDCC96E3D3F`（live / baseline / guard 副本三处一致）。

---

## 3. 原理

### 3.1 客户端到底在检查什么

`TARGET_SAMPLE` 把"授权状态"拆成两层：

1. **本地配置层**：`AppConfig` 里有一个 `CardKey` 字段（serde 名为 `CardKey`），表示用户输入的卡密。
2. **网络校验层**：启动时调用 `POST /api/card/init`，请求体里带 `program_name`、`version`、`client_target`，**如果有 CardKey 则额外带 `card` 字段**。

客户端根据 `/api/card/init` 返回的 `data.card`（结构 `InitCardSnapshot{points, expiry_unix}`）判断会话是否有效。前端 UI（`AppSnapshot.runtime_session`）再据此决定显示授权码输入框还是主功能面板。

### 3.2 漏洞形成机制

```
本地配置文件 system_cache.dat 可写
        ↓
CardKey 字段只是"标识符"，不是凭据本身
        ↓
客户端把"有 CardKey"当成"进入授权校验流程"的开关
        ↓
/api/card/init 的响应结构完全由服务端决定
        ↓
若服务端地址可被重定向（二进制硬编码 URL 可 patch）→ 攻击者可控响应
        ↓
返回合法的 InitCardSnapshot → 客户端认定已授权 → 显示主功能面板
```

关键点：**客户端没有做"这个卡密是否真的由服务方签发"的密码学验证**。签名头 `x-sign` 是客户端自己用 `SignKey` 算的，而 `SignKey` 也在本地配置里；mock 端不校验签名即可通过。客户端校验的是"服务端说 OK"，而"服务端是谁"由客户端自己决定——这就是客户端校验不能作为安全边界的典型例子。

### 3.3 为什么字段名错误会导致"永远未授权"

serde 默认行为：结构体字段 `CardKey: Option<String>` 序列化为 JSON key `"CardKey"`。写入 `card_key` 时：

- 反序列化：`card_key` 是未知字段 → 被忽略 → `CardKey = None`
- 客户端逻辑：`CardKey = None` → 请求体不带 `card` → 服务端无法识别卡密 → 返回 signed_out
- 客户端重启时重写配置 → 只写已知字段 → `card_key` 被抹掉

这是一个**"配置字段名大小写"引发的可用性 bug**，但背后暴露的是**"授权状态完全由本地配置 + 可控服务端响应决定"**的设计缺陷。

### 3.4 补丁链与绕过点

对 `TARGET_SAMPLE.exe` 打了 7 处字节补丁（偏移量基于 4.4.119）：

| 编号 | 文件偏移 | 原始字节 | 新字节 | 作用 |
|---|---|---|---|---|
| P1 | `OFFSET_1` | `75B9` | `EBB9` | 跳过第一个授权错误构造点（jne→jmp） |
| P2 | `OFFSET_2` | `74CB` | `EBCB` | 跳过第二个授权错误构造点（je→jmp） |
| P3 | `OFFSET_3` | `0F1005706B5100` | `0F57C090909090` | 中和 `upgrade_required` 字面量加载 |
| P4a | `OFFSET_4` | `41B919000000` | `41B900000000` | `EDITOR_UNVERIFIED_VERSION` 长度清零 |
| P4b | `OFFSET_5` | 同上 | 同上 | 同上 |
| P5a | `OFFSET_6` | `https://TARGET`（原文 23 字节） | `http://127.0.0.1:65534\0`（22+1） | API base URL 重定向到本地 mock |
| P5b | `OFFSET_7` | `41B817000000` | `41B916000000` | URL 长度 0x17→0x16 |

> 真实域名已脱敏为 `TARGET`。P5a 曾因替换后少一个字节留下尾随字符 `p`，导致 URL 变成 `http://127.0.0.1:65534p`，已单独清除。
>
> **偏移占位说明**：补丁偏移以 `OFFSET_1..7` 占位，避免直接指向具体样本版本。偏移量本身是逆向分析的教学核心，但配合真实产品名会暴露目标；需要实操时按 §4.1–4.4 的 xref 方法自行定位。

---

## 4. 逆向过程（最小必要）

### 4.1 从 serde 字段表确定请求/配置结构

`strings` 在 `.rdata` 找到连续字段名表：

```
0x64d68b: ... InitPayload updated_unix program editors card
0x64d870: ... InitCardSnapshot points expiry_unix
0x675e60: struct AppConfig CardKey selected_editor AssignRequestID DeviceID
          SignKey editor_app_paths cursor_switch_mode devin_switch_mode cache
```

**判定依据**：这是 serde derive 生成的 `FIELDS` 常量布局——先列出字段名，后跟 `"struct X with N elements"` 错误信息。由此确定配置键名是 `CardKey` 而非 `card_key`。

### 4.2 从 API 路径字符串确定攻击面

在 `.rdata` 中提取到全部 API 路径：

```
/api/card/init          /api/card/notice
/api/card/merge         /api/card/merge/preview
/api/accountpool/assign /api/payment/order
/api/payment/prices     /api/payment/status
/api/payment/stream     /api/release/latest/TARGET_SAMPLE/{{target}}-{{arch}}
```

**判定依据**：这些字符串在代码中通过 rip-relative LEA 引用，是构造 HTTP 请求时的路径常量。`/api/card/init` 在 `src\domains\card\init.rs` 中被引用。

### 4.3 硬编码 API base URL 的定位

- 字符串 `TARGET` 位于文件偏移 `LOC_URL`，长度 23 字节。
- 全文件只有 **1 处** rip-rel LEA 引用它，位于文件 `LOC_XREF`（RVA `LOC_XREF_RVA`）。
- 长度常量 `41 B8 17 00 00 00` 位于 `LOC_LEN`。

**判定依据**：单一 xref + 长度常量紧邻，说明这是全局变量初始化，改动它即可全局重定向 API。

> 注：`LOC_URL` / `LOC_XREF` / `LOC_LEN` 三个偏移在本案例中作为**定位方法的示例**保留——它们是 xref 手法的教学载体，且未指向具体产品名。若配套发布需进一步脱敏，可将这三个偏移也改成 ` locating offsets` 占位。

### 4.4 授权错误构造点的定位

在 `strings` 中找到客户端错误码/文案表：

```
0x64dc99: signed_out active card_key expiry_time points_balance ...
0x651112: 正在确认授权码… 网络连接失败，请检查网络设置 请购买套餐后继续使用
0x651338: 登录失败 app-state-changed 授权码已保存，联网后生效。
0x6ac1d8: 请输入授权码 src\domains\card\service.rs
```

通过 capstone 反汇编 `.text`，在引用 `NEED_USER_AUTHORIZATION` 相关字符串的函数里找到条件跳转，改成无条件跳转（P1/P2），使错误构造点不再执行。

### 4.5 动态验证链条

```
写入 CardKey（错误名 card_key）→ 重启 → mock 日志：/api/card/init 无 card 字段 → UI 仍要求授权码
写入 CardKey（正确名 CardKey）→ 重启 → mock 日志：/api/card/init 带 "card":"SERIAL" → UI 进入主面板
```

这一步是判定"字段名即根因"的决定性证据。

---

## 5. 怎么找到的

### 逆向侧信号

1. `strings TARGET_SAMPLE.exe | grep -i card_key` → 找到 6 处，其中 `struct AppConfig ... CardKey ...` 暴露了精确键名。
2. `.rdata` 里 serde 字段表集中出现 `InitPayload`、`InitCardSnapshot`、`PricesData`、`PaidData` 等结构名，说明协议模型可从二进制静态恢复。
3. 硬编码 URL 只有单一 xref，具备全局重定向条件。

### 挖洞侧信号

1. **服务端不可达**：真实服务端返回 HTTP 444（WAF 拒绝），无法验证卡密真实性——说明客户端必须自己承担大量状态判断。
2. **配置可写且含授权状态**：`system_cache.dat` 是普通 JSON 文件，用户可写。任何"把授权状态存在这里"的设计天然可疑。
3. **动态观察**：未写入正确 `CardKey` 时，`/api/card/init` 请求体里**没有** `card` 字段；写入后立刻出现。这证明"客户端是否认为自己有卡"完全由本地配置决定。

---

## 6. 复现步骤

### 6.1 客户端侧（构造能通过校验的数据）

**目标**：让客户端认定自己已持有卡密并进入授权校验流程。

1. 关闭 `TARGET_SAMPLE` 进程。
2. 备份 `%APPDATA%\ORG_NV\system_cache.dat`。
3. 用文本编辑器或脚本，在顶层 JSON 对象加入字段：
   ```json
   {"CardKey": "SERIAL", "...": "..."}
   ```
   > `SERIAL` 为 10 位占位值。真实值已脱敏。
4. 启动客户端。
5. 观察 mock 日志：`/api/card/init` 请求体应包含 `"card":"SERIAL"`。
6. 观察 UI：授权码输入框消失，显示主功能面板。

**预期现象 vs 实际现象**：
- 写 `card_key`：请求体无 `card`，UI 要求授权码（预期失败）。
- 写 `CardKey`：请求体有 `card`，UI 进入主面板（预期成功）。

### 6.2 服务端侧（完整 HTTP 报文）

启动本地 mock（`python TARGET_SAMPLE_mock.py --port 65534`），客户端被 patch 后指向 `http://127.0.0.1:65534`。

**请求（客户端 → mock）**：

```http
POST /api/card/init HTTP/1.1
Host: 127.0.0.1:65534
Content-Type: application/json
x-timestamp: 1795694796
x-nonce: <NONCE>
x-sign: <REDACTED>
Content-Length: 99

{"program_name":"cursor","version":"4.4.119","client_target":"windows-x86_64","card":"SERIAL"}
```

**正常响应（mock → 客户端）**：

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"code":0,"message":"ok","data":{
  "updated_unix":1795694796,
  "program":{"notice":{"content":"","latest_version":"4.4.119","required_version":"4.4.119"},
             "changelog":{"content":"本地模式","version":"4.4.119"},
             "type":"program"},
  "editors":{"items":[{"editor":"cursor","point_cost":1,"type":"cursor","name":"cursor"}]},
  "card":{"points":999999,"expiry_unix":4102444800,"type":"card"}
}}
```

**预期 vs 实际响应差异**：
- 真实服务端返回 `444`（WAF 拒绝），客户端进入 signed_out。
- 本地 mock 返回结构合法的 `data.card`，客户端进入 active。
- 差异证明：客户端信任的是"响应结构是否合法"，而不是"响应者是否可信"。

---

## 7. 结果验证

**成功判据**（满足全部才算绕过成功）：

| # | 判据 | 验证方法 |
|---|---|---|
| 1 | 配置含 `CardKey` 且重启后不被抹除 | 读取 `system_cache.dat` |
| 2 | `/api/card/init` 请求体含 `"card":"SERIAL"` | mock 日志 |
| 3 | UI 显示主功能面板而非授权码输入框 | GUI 截图 |
| 4 | 二进制 SHA-256 与 guard baseline 一致 | `Get-FileHash` |
| 5 | mock 服务持续运行 | 进程列表 + 端口监听 |

**失败排查表**：

| 现象 | 可能原因 | 排查 |
|---|---|---|
| 写了 `card_key` 但客户端无反应 | 字段名大小写错误 | 改 `CardKey` |
| mock 无日志 | URL 未 patch 成功或 mock 未启动 | 检查 `OFFSET_6` 处字节 + 进程 |
| 请求体无 `card` | 配置被重写前就读取了旧值 | 完全退出进程后改配置 |
| UI 仍显示授权码 | P1/P2 未生效或 notice 拦截 | 检查补丁字节 + `required_version` |
| 截图拿到别的窗口 | 跨权限 / 屏幕被其他窗口遮挡 | 用提权脚本截图，或看 mock 日志代替 |

---

## 8. 影响面与严重度

**CVSS 向量（建议）**：`AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:H/A:L`

- **AV:L**：需要本地访问（修改配置文件 / 二进制）。
- **PR:L**：普通用户权限即可（配置文件在用户目录）。
- **I:H**：授权状态被完全篡改。
- **C:L**：可间接影响关联应用（如 IDE 侧 token 注入）的登录态。

**影响范围**：
- 所有使用同类"本地配置 + 可控服务端响应"架构的 `TARGET_SAMPLE` 版本。
- 4.4.118 的补丁偏移已失效，4.4.119 需重新定位。
- 关联 IDE 若依赖该工具注入 token，会受连带影响（缺少 `cursorAuth/accessToken` → `ERROR_UNAUTHORIZED`）。

**不成立的前提**：
- 服务端返回强签名响应且客户端验证签名（本样本未发现）。
- 配置文件受 ACL / 完整性校验保护（本样本为普通 JSON）。
- 二进制有代码签名校验且 patch 后拒绝启动（本样本未触发）。

---

## 9. 修复建议

**客户端侧**：
1. `CardKey` 不应是"授权状态开关"，应改为只在用户主动登录时通过安全 IPC 传入。
2. 对 `system_cache.dat` 做 HMAC 完整性校验，密钥由服务端下发并绑定设备指纹 `MACHINE_ID`。
3. 校验 `/api/card/init` 响应签名：服务端用私钥签名 `InitCardSnapshot`，客户端用内置公钥验签。
4. 严格校验 `required_version`：当前 P3 补丁中和了 `upgrade_required`，说明版本闸门太弱。

**服务端侧**：
1. `/api/card/init` 必须校验 `x-sign`，且签名密钥不能从客户端配置读取。
2. 卡密 `SERIAL` 与 `MACHINE_ID` 绑定，拒绝异地/异机复用。
3. 对异常请求频率、伪造 `x-nonce`、重放 `x-timestamp` 做风控。
4. 真实服务端应返回明确错误码而非 `444`，避免客户端进入不可预期的降级路径。

**根本原则**：**客户端校验只是体验优化，不能当安全边界。** 任何"本地可写文件说你已授权"的设计，都等价于没有授权。

---

## 10. 踩过的坑

| 现象 | 原因 | 解决 |
|---|---|---|
| 4.4.118 补丁偏移在 4.4.119 上全部失效 | 版本更新导致代码布局变化 | 用 capstone + rip-rel xref 重新定位所有 7 处偏移 |
| 写了 `card_key` 但客户端不认 | serde 字段名是 `CardKey` | 从 `struct AppConfig` 字段表确认精确键名 |
| URL 变成 `http://127.0.0.1:65534p` | 23 字节原串换成 22 字节新串，漏了 NUL | 补写 `\0` 并同步 guard 副本 |
| `missing field 'cards'` / `missing field 'type'` | mock 响应结构不符合 serde 模型 | 从字段表补全 `cards` 数组和 `type` 字段 |
| watchdog 不生效 | 脚本里 `@@MAIN@@` 等占位符未替换，且 `exit 0` 提前退出 | 手写 watchdog.ps1，填入真实路径 |
| UAC 提权被取消 | 用户未点击确认 | 后续操作改用 mock 日志等非 GUI 验证 |
| 截图拿到无关桌面 / 聊天窗口 | PrintWindow 跨权限失败 / 窗口被遮挡 | 提权后 `SetWindowPos(HWND_TOPMOST)` 再截图，或以日志代替 |
| `ERROR_UNAUTHORIZED` 一直存在 | `cursorAuth/accessToken` 缺失，与授权码无关 | 需单独走账号池分配链路 |
| 提权的进程无法被普通权限结束 | 完整性级别隔离 | 用 `Start-Process -Verb RunAs` 提权脚本 |

---

## 11. 方法论沉淀

**检查清单**：
- [ ] 从 `struct AppConfig` 后的字段名串确认磁盘 JSON 的精确键名（大小写！）
- [ ] 用 mock 日志确认请求体是否包含目标字段——这是"配置是否被读取"的黄金信号
- [ ] 硬编码 URL 找单一 xref + 紧邻长度常量
- [ ] serde 字段表反推响应结构，先让 mock 能被反序列化
- [ ] 补丁后同步 guard baseline 与 patched 副本，校验三处 hash 一致
- [ ] 版本升级后必须重定位所有偏移

**关键判断信号**：
- 服务端返回 444 / 不可达 → 客户端必然承担大量本地状态判断 → 值得挖客户端逻辑。
- 配置文件里出现授权相关字段 → 直接测试"改字段能否改变 UI 状态"。
- 请求体里字段的有无与配置严格对应 → 证明该字段是纯客户端开关。

**工具技巧**：
- `capstone` 反汇编 + `pefile` 算 RVA↔文件偏移，比 IDA 轻量。
- mock 服务记录 headers + body，一次重启即可看清协议全貌。
- 用 `Get-FileHash` 三处对比，防止 guard 把补丁还原。

---

## 12. 延伸

**还能用在哪**：
- 任何 Tauri/Electron 桌面应用的"本地配置授权"逻辑审计。
- 任何把 license 状态存在用户目录 JSON/SQLite 的软件。
- 账号池工具的协议还原与本地 mock 化。

**换场景会怎么变**：
- 若服务端返回签名响应，攻击面转移到"如何拿到签名公钥/私钥"。
- 若配置文件有 HMAC，攻击面转移到"HMAC 密钥是否硬编码在二进制里"。
- 若授权状态存在系统证书存储，需改从 IPC / 进程内存入手。
- 若是 Electron，可直接改 `localStorage` / `IndexedDB`，原理相同但入口不同。

---

## 13. 复现清单

- [ ] 备份 `system_cache.dat` — 预期：生成 `.bak` 文件
- [ ] 从二进制提取 `struct AppConfig` 字段表 — 预期：看到 `CardKey`
- [ ] 写入 `{"CardKey":"SERIAL"}` 到配置顶层 — 预期：JSON 合法
- [ ] 启动 mock 服务（端口 65534）— 预期：监听成功
- [ ] 确认二进制 URL 已指向 `127.0.0.1:65534` — 预期：`OFFSET_6` 处为 `http://127.0.0.1:65534\0`
- [ ] 启动客户端 — 预期：mock 日志出现 `/api/card/init`
- [ ] 检查请求体含 `"card":"SERIAL"` — 预期：是
- [ ] 检查 UI 无授权码输入框 — 预期：显示主功能面板
- [ ] 校验 live/baseline/patched 三处 SHA-256 — 预期：一致
- [ ] 注册开机自启 — 预期：Run 键下存在对应条目（本文脱敏，不写具体键名）

---

<!-- 以下为复盘信息，不属于文章正文 -->

## 复盘信息

### 脱敏替换表

> 只列类别，不列原文——避免替换表本身成为泄漏源。

| 原文类别 | 替换为 | 说明 |
|---|---|---|
| 真实 API 域名 | `TARGET` / `TARGET_SUBDOMAIN` | 对外不暴露服务方 |
| 样本真实产品名 / 文件名 | `TARGET_SAMPLE` / `TARGET_SAMPLE.exe` | 不暴露具体软件 |
| 真实应用包名 | `com.example.app` | 保留格式，去标识 |
| 真实卡密 / 激活码 | `SERIAL` | 占位 |
| 本机用户目录 | `USER_HOME` | 不暴露本机用户名 |
| 组织名派生目录 | `ORG_NV` | 已抽象 |
| 真实签名值 / token | `<REDACTED>` | 凭据 |
| 真实人名 / 机器名 | `USER_A` / `MACHINE_ID` | 身份线索 |
| 关联服务域名 | `TARGET_SUBDOMAIN` | 对外不暴露 |
| 数据库名 / 表名 | `DB_NAME` / `TABLE_NAME` | 抽象 |
| 真实邮箱 | `<REDACTED_EMAIL>` | 身份线索 |
| 一次随机数 | `<NONCE>` | 避免与原抓包关联 |
| 补丁偏移 | `OFFSET_1..7` | 配合产品名会暴露目标；按 §4 方法自行定位 |
| `system_cache.dat`、字段名、API 路径、错误码 | 保留 | 技术核心，非身份标识 |
| 样本完整性哈希 | 保留 | 非敏感，用于校验复现 |

### 已确认的处理决定

- [x] **7 处补丁偏移** — **决定：占位为 `OFFSET_1..7`**。偏移量本身是逆向教学核心，但配合真实样本版本会指向具体目标。正文保留 xref 定位方法（§4.1–4.4），读者可自行复现定位过程；具体偏移不公开。
- [x] **截图** — **决定：不附**。原截图含真实桌面信息、窗口标题与聊天内容，公开会暴露身份线索。以 mock 日志 + 配置字段 + SHA-256 三重验证代替。
- [x] **关联 IDE 侧 `ERROR_UNAUTHORIZED`** — **决定：不单独成文**，只在 §0、§8 做简要关联说明其因果独立性，避免把两个问题混为一谈。

### 对话价值评估

- **可复用方法论：7 条**（serde 字段表定位、单一 xref 定位硬编码 URL、mock 日志作为黄金信号、补丁 hash 三处校验、版本偏移重定位、错误文案表定位校验点、配置字段名大小写排查）
- **可复现步骤：10 步**
- **踩坑记录：9 条**
- **是否值得单独成文：是** —— 案例完整覆盖了"客户端校验可被本地配置篡改"这一常见漏洞模式，且逆向过程与漏洞原理结合紧密，具备教学价值。
