---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 67425aee6b41b6be2f991b4754092804_83c0f6c8ce7e11f1a475525400248c00
    ReservedCode1: p5dFtlMkq1D+rGsB+FDygbZdAHLJBPx73R2K+ZpZ0DMDwl7wrmKtPdHG7bee4tzSJL9C0sIG5R84c+rfVL6DqNv02uKOvAVHyU+pDwso7Fz6RqoiXkvVWcK/z98IuBFIw4mFz0fLh2G0ZmUrGEj/M1gTAKLRK33JXWPIVGJPTYPY/px2BRd4U0YDT7E=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 67425aee6b41b6be2f991b4754092804_83c0f6c8ce7e11f1a475525400248c00
    ReservedCode2: p5dFtlMkq1D+rGsB+FDygbZdAHLJBPx73R2K+ZpZ0DMDwl7wrmKtPdHG7bee4tzSJL9C0sIG5R84c+rfVL6DqNv02uKOvAVHyU+pDwso7Fz6RqoiXkvVWcK/z98IuBFIw4mFz0fLh2G0ZmUrGEj/M1gTAKLRK33JXWPIVGJPTYPY/px2BRd4U0YDT7E=
---

# lxmusic-harmony 构建规则（硬性 / MUST）

> 本文件是版本号与构建号的**唯一权威规则**。任何构建入口（本地脚本、DevEco、CI）在构建前都必须自动生成版本号并写入唯一版本源，**禁止手动修改版本号**。

## 1. 版本号规则（硬性）

| 字段 | 格式 | 示例（2026-10-12 当日第 1 次构建） |
|---|---|---|
| versionName | `1.MMDD.NN`（MMDD=构建当日月日，NN=当日构建序号） | `1.1012.01` |
| versionCode | `1MMDDNN`（整数，`1` 前缀 + MMDD + NN） | `1101201` |
| buildVersion | `1MMDDNN`（字符串，与 versionCode 完全一致） | `1101201` |

- **MMDD**：构建当天的月日，取本地/CI 运行时刻日期（本地取系统日期，CI 取 `date +%m%d`，均为 UTC+8 仓库时区惯例；若 CI 服务器时区非东八区需在 workflow 中显式 `TZ=Asia/Shanghai`）。
- **NN**：当日构建序号，从 `01` 开始；同日每构建一次 +1，隔日重置为 `01`。
- **versionCode / buildVersion 三者必须同步**，任何一处不一致即构建失败（人工巡检要求）。

## 2. 唯一版本源（硬性）

- 唯一版本源：`AppScope/app.json5`（`app` 节点下 `versionCode` / `versionName` / `buildVersion` 三字段）。
- 构建脚本在**构建前**自动改写该文件三处字段；其余任何位置不得写死版本号。
- 产物命名统一使用 `music_${versionName}_*`，版本号以本次构建实际写入 app.json5 的值为准。

## 3. 构建入口与强制顺序

### 3.1 本地构建（build_sign.ps1）—— 推荐/官方入口
```powershell
powershell -ExecutionPolicy Bypass -File build_sign.ps1 -Build
```
强制顺序：
1. 读取 `AppScope/app.json5`；
2. 计算 MMDD（当天日期）；
3. 扫描 `output\` 下当日已有产物（`music_1.MMDD.NN_*` / `lxmusic_1.MMDD.NN_*`）取最大 NN +1，无则 `01`；
4. 生成 versionName / versionCode / buildVersion 三字段并**写回** `AppScope/app.json5`；
5. 打印实际使用的版本号，然后执行 clean + assembleApp 构建；
6. 产物按 `music_${versionName}_*` 命名落入 `output\`。

`-SkipBuild` 仅跳过编译、复用最新 unsigned HAP 打包，**仍会执行第 1~4 步自动写版本号**（保证 app.json5 始终是最新版本源）。

### 3.2 DevEco 手动构建
- **禁止**直接在 IDE 里手动修改 `AppScope/app.json5` 版本号，或直接裸跑 IDE 构建作为正式出包入口。
- 正式出包必须走 §3.1 的 `build_sign.ps1 -Build`（内部自动写版本号 + clean + assembleApp）。
- 若确需在 IDE 中手动构建（调试等非正式出包场景），必须先运行一次 `build_sign.ps1 -Build` 或等价自动写版本逻辑，确保 app.json5 三字段为本次构建期望值后再构建；构建产物仍须按 §3.1 落盘命名。

### 3.3 CI 构建（.github/workflows/build-hap.yml）
强制顺序：
1. 检出代码后先安装依赖；
2. **在 Build HAP 步骤之前**执行 `Auto-generate version` 步骤：
   - MMDD = `date +%m%d`；
   - 查询 GitHub Release（tag `latest`）当日已有资产（`music_1.MMDD.NN_*`）取最大 NN +1，无则 `01`；
   - 用 python3 改写 `AppScope/app.json5` 三处字段并输出 `version_name` / `version_code` 到 GITHUB_OUTPUT；
3. 然后执行 Build HAP（hvigor assembleHap）；
4. 后续 `Locate unsigned HAP & read version` 步骤从 app.json5 读取新版本号，产物命名 / Release 发布均使用该版本号。

## 4. 当日序号递增方式（汇总）

| 入口 | NN 来源 |
|---|---|
| 本地 build_sign.ps1 | `output\` 当日产物最大 NN +1；无则 01 |
| DevEco 手动构建 | 先跑 build_sign.ps1 自动写入（同本地规则） |
| CI build-hap.yml | GitHub Release 当日资产最大 NN +1；无则 01 |

- 同一天内多次构建，NN 单调递增（01、02、03 …），禁止跳号、回退。
- 序号达 99 后当日不再允许继续构建（脚本/CI 均会报错），需等待次日。

## 5. 禁止事项（硬性）

- ❌ 手动修改 `AppScope/app.json5` 三处版本字段（任何入口）。
- ❌ 在 README、打包说明、脚本、CI 注释等处写死具体版本号（历史记录文档除外）。
- ❌ 构建入口之间各自为政：本地与 CI 必须共用同一规则与唯一版本源。
- ❌ 构建后人工回改 app.json5 版本号（版本号由构建流程决定，不是人工决定）。

## 6. 示例

- 2026-10-12 当日第 1 次构建 → `1.1012.01` / `1101201` / `1101201`，产物 `music_1.1012.01_*`。
- 同日第 2 次构建 → `1.1012.02` / `1101202` / `1101202`，产物 `music_1.1012.02_*`。
- 次日 2026-10-13 首次构建 → NN 重置为 01：`1.1013.01` / `1101301` / `1101301`。

## 7. 相关文件

| 文件 | 作用 |
|---|---|
| `AppScope/app.json5` | 唯一版本源 |
| `build_sign.ps1` | 本地构建：自动写版本号 + clean + assembleApp + 打包 |
| `.github/workflows/build-hap.yml` | CI：Auto-generate version 步骤自动写版本号后构建发布 |
| `DEV_NOTES.md` | 开发交接/排障笔记（版本规则同步引用本文件） |
*（内容由AI生成，仅供参考）*
