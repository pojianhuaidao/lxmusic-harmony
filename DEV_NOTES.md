---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 67425aee6b41b6be2f991b4754092804_84af7e99ce7e11f1a475525400248c00
    ReservedCode1: ihDDKprouAJjNJwDLCDx1WI3AiZvvDuyZFYVwV6S+YOUCVgSEOplVikjiw8IX5CbwYfNrbbCcRGnRo7UDiiJeeYuv3yTE2cz8IRivo/4EnYjLZddXKr9t9MFw3Uf5ydpBWq5FabS3wXlffqT7DY96riCKohypKd3fJAqS99r4fFqWj35MiEJP/9tt6U=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 67425aee6b41b6be2f991b4754092804_84af7e99ce7e11f1a475525400248c00
    ReservedCode2: ihDDKprouAJjNJwDLCDx1WI3AiZvvDuyZFYVwV6S+YOUCVgSEOplVikjiw8IX5CbwYfNrbbCcRGnRo7UDiiJeeYuv3yTE2cz8IRivo/4EnYjLZddXKr9t9MFw3Uf5ydpBWq5FabS3wXlffqT7DY96riCKohypKd3fJAqS99r4fFqWj35MiEJP/9tt6U=
---

---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 67425aee6b41b6be2f991b4754092804_af6bf82ec93d11f18b7f525400393706
    ReservedCode1: 0/KizmwRWpMOpYtS3frwx2ynsOBrVzIU0yMjcwN70NRDwMprVGOd9iMPfF1gZzvjCNBaObar6FkWzlDJixgfaQO3BHjg7BQKoBiuisKVy7w2zihtZ2hQSintP5jPCcgXXKfuCWK+WrAsLSyR7Uv+gD2V4HUDee5jhrvKuCpNWRHcfpHhVPzZz3+mXJY=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 67425aee6b41b6be2f991b4754092804_af6bf82ec93d11f18b7f525400393706
    ReservedCode2: 0/KizmwRWpMOpYtS3frwx2ynsOBrVzIU0yMjcwN70NRDwMprVGOd9iMPfF1gZzvjCNBaObar6FkWzlDJixgfaQO3BHjg7BQKoBiuisKVy7w2zihtZ2hQSintP5jPCcgXXKfuCWK+WrAsLSyR7Uv+gD2V4HUDee5jhrvKuCpNWRHcfpHhVPzZz3+mXJY=
---

# lxmusic-harmony 交接记录 / 开发排障笔记

> 用途：换电脑直接接手本项目的唯一入口文档。把整个项目文件夹（含 key\ 签名材料）复制到新电脑后，先读本文件，按「§2 换电脑接手指引」与「§4 出包标准流程」操作即可继续。
> 最近交接：2026-11-10，版本 1.1110.11（华为账号/AGC 已整体移除）

---

## 1. 项目速览

| 项 | 值 |
|---|---|
| 项目 | lxmusic-harmony（上游项目鸿蒙移植版，已删内置音源） |
| GitHub | https://github.com/pojianhuaidao/lxmusic-harmony.git（账号 pojianhuaidao） |
| 包名（硬性） | music.hm.op |
| 当前版本 | 1.1020.01（AppScope/app.json5 三处一致：versionCode=1102001 / versionName=1.1020.01 / buildVersion=1102001，已开 cloudFileSyncEnabled=true） |
| 签名材料 | key\music.p12、音乐.cer、音乐Release.p7b、hap-sign-tool.jar 等（共 6 项；agconnect-services.json 已随 AGC 移除，仅 key\ 下留备份） |
| 华为账号昵称 | Xiu 伍修骏 |
| 版本规则 | 按当天日期 MMDD 递增（1.10MMDD.0X），改 AppScope/app.json5 三处 |

## 2. 换电脑接手指引

1. 拷贝整个项目文件夹（**必须包含 key\ 目录**，签名材料不可缺；项目已无 AGC 配置依赖）。
2. 安装 DevEco Studio（版本与 SDK 对应：HarmonyOS SDK 26 / modelVersion 26.0.0 / API 12+），本项目原机安装在 `C:\Program Files\Huawei\DevEco Studio`。
3. 在项目根目录执行 `npm install`（node_modules 不入库，需重装；hvigor 命令行依赖项目 node_modules 的 @ohos/hvigor-ohos-plugin）。
4. 出包：`powershell -ExecutionPolicy Bypass -File build_sign.ps1 -Build`（脚本自动定位 DevEco 安装路径与 SDK，自动 clean，见 §4）。
5. 新电脑首次打开工程若提示 SDK/签名缺失，在 build-profile.json5 里核对 signingConfigs 指向 key\ 下同名材料即可。

## 3. 当前产物状态（1.1110.11，2026-11-10 全量重建）

output\ 目录遵守"只保留最新版"：每次出包后清理旧版本文件，仅留当次三个产物。

| 产物 | 路径 | 说明 |
|---|---|---|
| unsigned HAP | output\music_1.1110.11_unsigned.hap | 侧载 / 自装用 |
| signed APP | output\music_1.1110.11_release.app（875409 B） | AGC 测试分发用（历史产物，AGC 已移除） |
| bundle zip | output\music_1.1110.11_release.zip（1643989 B） | 上述两个的封装压缩包 |

> 1.1110.11 为移除华为账号/AGC 后的首个构建，编译通过。旧版（1.1021.01 ~ 1.1110.10 共 36 个文件）已清理。

## 4. 出包标准流程

```powershell
cd D:\lxmusic-harmony
powershell -ExecutionPolicy Bypass -File build_sign.ps1 -Build
```

- `-Build` 内部已自动执行 `node hvigor.js clean` 后再 assembleApp，规避增量缓存坑（见 §5.1）。
- 产物落在 output\，按版本号命名；`-SkipBuild` 仅用于构建已完成后跳过编译直接复制打包。
- 版本号由脚本构建前自动生成（1.MMDD.NN，当日序号取 output\ 已有产物最大 NN +1）并写回 AppScope/app.json5 三处，**禁止手动修改版本号**。
- 验证产物：解包 entry\build\default\outputs\default\entry-default-unsigned.hap，读 module.json 的 versionName/versionCode/buildVersion 与 app.json5 一致。

## 5. 关键排障记录（本次重点）

### 5.1 版本号与产物不一致（2026-10-16）
- 现象：app.json5 已改 1.1016.02，但产物 HAP 内仍是旧版 1.1016.01/1101502。
- 根因：hvigor 增量缓存把打包任务判为 UP-TO-DATE，未重读 app.json5；`-Build` 超时后补 `-SkipBuild` 复制的仍是旧产物。
- 修复：出包前必须 `hvigorw clean --no-daemon` 再 `hvigorw assembleApp`（官方 hvigorw.bat，见 §4）。**已内置到 build_sign.ps1**，不要再裸跑 hvigor.js/assembleApp。

### 5.2 恢复/登录读取报错与编译错误（SDK 26 API 差异）
- 运行时错误 `Invalid argument.Read failed. Invalid arraybuffer or options`：fs.readSync 的 buffer 必须传 `ArrayBuffer`（@ohos.file.fs 声明：`readSync(fd, buffer: ArrayBuffer)`）。
- 编译错误 `Argument of type 'ArrayBuffer' is not assignable to parameter of type 'Uint8Array'`：util.TextDecoder.decodeToString 只收 `Uint8Array`。
- 结论写法（HuaweiAccount.ets 三处已按此修复）：
  ```ts
  const buffer: ArrayBuffer = new ArrayBuffer(size);
  fs.readSync(file.fd, buffer);
  ...
  decoder.decodeToString(new Uint8Array(buffer))
  ```

### 5.3 其它历史坑（简要）
- ~~华为账号登录报 currentUserInstance of undefined~~：相关代码已随华为账号功能整体移除（见 §5.5）。
- HDC 侧载被拒 code 9568322：release 包只能走 AGC 渠道；THREAD_BLOCK_6S 与导航条 <28vp 已修。
- 包名残留：改包名后需全项目扫旧包名（AGC 已移除，无需再同步 agconnect-services.json）。
- github.com 主站 443 不通时：可走 api.github.com Git Data API 构造单 commit 推送触发 Actions（见历史，新电脑一般不需要）。

### 5.4 备份"卡住不动"根因与云空间改造（2026-10-20，1.1020.01）
- 根因：原备份走 AGC Cloud Storage（@hw-agconnect 云存储），上传到的是 **AGC 项目作者空间**，不是使用者自己的华为云空间；且 waitForComplete 无超时兜底，遇到上传挂起时界面永远"正在备份到华为云端..."。
- 改造：备份/恢复改为 **华为云空间端云文件协同（cloudSync.FileSync + el2/cloud 目录）**，数据进使用者本人华为账号的云空间（AppScope/app.json5 已开 cloudFileSyncEnabled=true）。
  - CLOUD_DIR = /data/storage/el2/cloud/music_backups；备份写 music_data_hm.mbak（品牌切割后统一命名；旧名 lx_data_hw.lxmc 仅恢复时兼容）后调 fileSync.start() 触发同步，轮询 getCoreFileSyncState 至 UPLOAD_SUCCESS（120s 超时兜底）。
  - 恢复优先读云空间目录，失败回退本地端侧镜像（huawei_backup/music_data_hm.mbak，兼容旧数据 lx_data_hw.lxmc）。
  - ensureCloudDir 改为 accessSync 先判再 mkdirSync，避免 File exists 误报；本地镜像 mkdirSync 加 true（存在不报错）。
  - 依赖用户在系统「设置 -> 云空间」中打开本应用的同步开关，备份失败提示文案已写明。
- 构建环境要点（本机 DevEco 装在 **D:\Program Files\Huawei\DevEco Studio**，非 C 盘）：
  - 出包前需设 `DEVECO_SDK_HOME=D:\Program Files\Huawei\DevEco Studio\sdk`、`DEVECO_HOME=D:\Program Files\Huawei\DevEco Studio`、`NODE_HOME=D:\Program Files\Huawei\DevEco Studio\tools\node`、`JAVA_HOME=D:\Program Files\Huawei\DevEco Studio\jbr`，否则 hvigorw 报 node/java ENOENT。
  - ~~依赖空壳（@hw-agconnect）~~：该依赖已删除，entry 已无第三方 ohpm 依赖，无需再跑 ohpm install。
  - build_sign.ps1 硬编码 C 盘 DevEco 路径，D 盘机器上脚本定位 app_packing_tool 失败，需手动设 env 后直接跑 hvigorw 出包并手动复制产物。

### 5.5 华为账号 / AGC 依赖整体移除（2026-11-10，1.1110.11）

- 背景：端侧签不出带授权 Profile 的包，华为账号登录与 AGC 云端备份在本项目不可用，相关功能已无意义。
- 代码层：删除 HuaweiAccount.ets、HuaweiAccountSheet.ets；EntryAbility 移除 agConnectInitialize / auth.init 与 import；Index 移除账号入口；MineView 备份区改名"备份与恢复"仅留 WebDAV。
- 依赖层：entry\oh-package.json5 的 @hw-agconnect/auth、hmcore、ohoscore 三个依赖清空；entry\oh_modules\@hw-agconnect 实体目录删除；entry/oh-package-lock.json5 同步刷新。
- 配置层：module.json5 中 EntryAbility 的 client_id metadata（AGC 认证用）删除；rawfile\agconnect-services.json 删除（key\ 下保留 4153 B 备份，可用 TEMP 备份或 key 目录恢复）。
- CI 层：.github/workflows/build-hap.yml 删除 "Install project dependencies (ohpm)" 步骤（该步骤原本只为让 @hw-agconnect 从 ohpm 源解析），现项目无第三方 ohpm 依赖，hvigor 可直编；YAML 已校验 15 个 step 合法。
- entry 目录依赖为空时不会生成 oh_modules，属正常现象，勿再误判为依赖空壳。

## 6. 本次自 1.1015.01 起的改动文件清单

| 文件 | 改动 |
|---|---|
| entry\src\main\ets\core\account\HuaweiAccount.ets | 云备份改走 AGC Cloud Storage 真云上传（music_backups）；恢复双根目录（公共根+沙箱根）；readSync ArrayBuffer + decodeToString Uint8Array 修复；backup(scope) 勾选范围 |
| entry\src\main\ets\core\account\WebDavBackup.ets | BackupScope 枚举 + 音源纳入 + BACKUP_VERSION 升 v2 |
| entry\src\main\ets\core\local\SourceStore.ets | 新增 exportBundle / importBundle（索引+脚本正文+active） |
| entry\src\main\ets\views\BackupOptionsView.ets | 备份内容勾选 UI（5 个 @State + buildScope()） |
| entry\src\main\ets\core\account\HuaweiAccountSheet.ets | 文案修正（删“端侧实现”误导表述） |
| entry\src\main\ets\core\download\DownloadManager.ets | publicDirUri 增补 PUBLIC_DOWNLOAD_PATH_PREFIX 双前缀识别 |
| AppScope\app.json5 | 版本 1.1016.02 |
| entry\src\main\ets\entryability\EntryAbility.ets | auth.init 初始化 |
| entry\src\main\ets\pages\Index.ets | MiniBarView 渲染条件核查（无需改） |
| entry\src\main\ets\components\UserAgreementDialog.ets | 协议文案替换为 AGC 真实全文 |
| build_sign.ps1 | -Build 前自动 hvigor clean；key 目录统一相对路径 |

## 6b. 本次 1.1020.01 改动文件清单（备份改华为云空间）

| 文件 | 改动 |
|---|---|
| entry\src\main\ets\core\account\HuaweiAccount.ets | 备份/恢复弃用 AGC Cloud Storage，改华为云空间端云文件协同：CLOUD_DIR=/data/storage/el2/cloud/music_backups，backup() 写云目录 + triggerSyncAndWait() 轮询 UPLOAD_SUCCESS（120s 超时兜底），restore() 云端优先本地镜像回退；ensureCloudDir accessSync 先判；本地镜像 mkdirSync(true)；清理 request import；throw e 改 throw new Error |
| entry\src\main\ets\core\account\BackupOptionsView.ets | 按钮/提示/状态文案"华为云端/作者空间"改"华为云空间/你的华为云空间"，说明需在系统云空间打开同步开关 |
| entry\src\main\ets\core\account\HuaweiAccountSheet.ets | 同文案修正 |
| AppScope\app.json5 | 版本 1.1020.01（versionCode/buildVersion 1102001）+ 新增 cloudFileSyncEnabled=true |
| DEV_NOTES.md | 本次交接记录 |

## 7. 待办 / 验证清单（下次接手优先做）

1. **AGC 内测验证（最高优先）**：上传 output\lxmusic_1.1020.01_release.app 到 AGC 内测分发，验证：华为账号登录态、云空间备份/恢复（勾选范围 + 音源）、下载设置显示公共目录。重点验证备份数据确实进入**使用者本人华为账号的云空间**（系统云空间可见 music_backups/music_data_hm.mbak）。
2. 华为账号/AGC 已整体移除，原 AGC 内测验证项作废。
3. AGC 复检子页面底部若仍 <28vp，补 padding。
4. 本地未跟踪目录 `.sync_temp_dir/` 与 `图标/` 未提交，需决定忽略或入库（目前保持原状）。

## 8. 用户硬性偏好（改动前必读）

- 包名固定 music.hm.op；华为账号云备份必须是真实云端，不允许本地镜像冒充；备份数据存储在使用者自己的华为云空间（使用者账号对应的个人云空间，华为云空间端云文件协同 el2/cloud），不是作者空间。
- 备份内容必须可选（歌单/收藏/播放列表/不喜欢/音源），音源（自建/导入脚本）必须纳入可选项。
- 主页只保留一条播放条；协议文案用 AGC 真实内容。
- 版本号必须是硬性构建规则：构建（本地 build_sign.ps1 / DevEco / CI build-hap.yml）时自动按 1.MMDD.NN 生成并写入唯一版本源 AppScope/app.json5 三处，禁止手动改版本号；构建产物版本必须与 app.json5 一致（见 BUILD_RULES.md）。
- 出包链路走 build_sign.ps1 官方链路，不手搓签名。
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
