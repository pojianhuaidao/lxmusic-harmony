---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 67425aee6b41b6be2f991b4754092804_2b25d083baea11f1b172525400248c00
    ReservedCode1: oPpHODzmCLnrzXbS8hvaKc6cAheAyZcwfjLlv76++A24707YcUbJq6XXXfBeZM6eCzNmTqIXJIyA0E+bhpkvQ47lwb+2yHiITOICfroO3XB1o/uXBM1zKpIWfxf3tXNxDjQt7gtwTfanfKhNAVEJ7mhLgUzDF2Y7w4Q/armRZSutnhM0SyBsyi1zzxY=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 67425aee6b41b6be2f991b4754092804_2b25d083baea11f1b172525400248c00
    ReservedCode2: oPpHODzmCLnrzXbS8hvaKc6cAheAyZcwfjLlv76++A24707YcUbJq6XXXfBeZM6eCzNmTqIXJIyA0E+bhpkvQ47lwb+2yHiITOICfroO3XB1o/uXBM1zKpIWfxf3tXNxDjQt7gtwTfanfKhNAVEJ7mhLgUzDF2Y7w4Q/armRZSutnhM0SyBsyi1zzxY=
---

# 更新日志（CHANGELOG）

> 记录 lxmusic-harmony 的定制改造。格式：日期 + 改动项 + 涉及文件。

## 2026-10-23：三项修复（云备份 / 底部栏 UI / 备份命名统一）

### 1. 华为云备份"端云协同未就绪"修复
- 对齐隔壁 legado-harmony（爱·阅读）已实现的华为云空间端云协同范式排查修复：
  - AppScope/app.json5 的 cloudFileSyncEnabled 两工程均已是 true，无需改动；
  - `entry/src/main/module.json5` 补齐 legado 具备的两项关键配置：模块级 metadata
    `ohos.arkui.UIMaterial.state=enable`（系统沉浸光感材质开关）与
    `ohos.permission.GET_NETWORK_INFO` 权限（网络状态感知）；
  - `core/account/HuaweiAccount.ets`：ensureCloudDir 探针失败时先 `FileSync().start()`
    激活端云协同会话再重试探针，解决"未激活时 el2/cloud 目录任何写入都被拒 → 永远判定
    未就绪"的死锁（爱阅读范式为写文件后再 start()，本工程探针先于 start() 存在时序差）；
- 涉及：entry/src/main/module.json5、entry/src/main/ets/core/account/HuaweiAccount.ets

### 2. 主页底部栏胶囊不可见 / 底图遮挡
- `pages/Index.ets`：三个主 Tab 页内容 bottomInset 由 +108 增至 +168，让内容区完整避让
  底部悬浮栏与常驻迷你条，消除底图遮挡底部内容；
- tabBarGlass 大胶囊、收起态并排胶囊、常驻迷你条三处统一加深阴影（radius 18→24、
  offsetY 8→10、透明度 0.14→0.26）并追加 1.2vp 半透明白高光描边，深浅模式均能清晰
  看出胶囊轮廓；
- 配合 module.json5 的 UIMaterial 开关，毛玻璃材质在支持机型上真正渲染。
- 涉及：entry/src/main/ets/pages/Index.ets、entry/src/main/module.json5

### 3. 备份文件命名去"lx"统一为 music_data_hm.mbak
- WebDAV（`core/webdav/WebDavBackup.ets`）：BACKUP_FILE `lx_data_hm.lxmc` →
  `music_data_hm.mbak`；恢复逻辑新名优先、旧名 404 时兼容读取；
- 华为云（`core/account/HuaweiAccount.ets`）：BACKUP_FILE `lx_data_hw.lxmc` →
  `music_data_hm.mbak`；恢复云空间目录与本地镜像均新名优先、旧名兼容；
- 全项目检索清理 `lx_data` / `lxmc` 残留（DEV_NOTES.md、BackupOptionsView.ets 注释），
  CHANGELOG 历史条目保留原文不动。
- 涉及：entry/src/main/ets/core/webdav/WebDavBackup.ets、
  entry/src/main/ets/core/account/HuaweiAccount.ets、
  entry/src/main/ets/views/BackupOptionsView.ets、DEV_NOTES.md

## 2026-09-28：六项定制改造

### 1. 应用名称与图标更名
- 全局替换旧名称为"听·音乐"（app.json5、entry string.json、DownloadManager.ets、Widgets.ets、AboutView.ets、PlayerView.ets、docs/DEFECTS.md 等 7 文件 13 处）。
- 应用图标更换：采用 Lucide（ISC 许可，免费可商用）music-4 音符图标，渲染生成鸿蒙 layered_image 前景图（AppScope 与 entry media 目录）、渐变背景图与 startIcon.png；原图标已备份。
- 涉及文件：AppScope/resources/base/media/、entry/src/main/resources/base/media/、各 string.json 等（git status 共 12 个文件）。

### 2. 项目主页/关于页链接改为用户地址
- `AboutView.ets`：REPO_URL 改为 https://github.com/pojianhuaidao/lxmusic-harmony，AUTHOR 改为对应作者名。
- `docs/UI_REPLICA.md` 相关描述同步更新。

### 3. 删除"帮助和反馈"入口与"用户反馈Q群"内容
- `AboutView.ets`：删除 QQ_GROUP（原 985841125）常量、Q群卡片、feedbackCard 组件及引用，清理未使用 import。
- `MineView.ets`：删除"帮助和反馈"入口行。
- `Index.ets`：移除导航到帮助页的分支。
- `Icons.ets`：移除仅被帮助页引用的图标。
- `docs/UI_REPLICA.md`：删除/改写相关描述。

### 4. 同步设置改造为 WebDAV 备份（对齐安卓版 lx-music-mobile）
- 对照安卓版 `lx-music-mobile`：备份目录 `Music Backup`、数据文件名 `lx_data.lxmc`、账号字段 `{server, username, password}`。
- 新增 `core/webdav/WebDavBackup.ets`：实现备份/恢复，复用现有 WebDavSettings（即外部"WebDav云端音乐"账号 {url, username, password}，与安卓共享同一登录体系）；备份目录对齐为 `Music Backup`，文件名 `lx_data_hm.lxmc`（加 hm 后缀区分安卓版）。
- `views/SyncSettingsView.ets`：由原 LX 协议同步设置页重写为 WebDAV 备份页（备份/恢复按钮 + 状态展示）。
- `core/sync/SyncManager.ets`：精简为门面（仅保留 LocalLibrary 初始化与数据版本号）。
- `core/sync/SyncStore.ets`：移除 LX 协议配置与密钥代码，保留音乐库与不喜欢规则存储。
- `EntryAbility.ets`：移除 onForeground 中 SyncManager.ensureConnected() 调用。
- `Index.ets`：移除 LX 同步方式选择弹窗（SyncModeSheet）全部引用。
- 删除协议文件：SyncClient.ets、SyncStatusText.ets、SyncGzip.ets、SyncModeSheet.ets；SyncTypes.ets 仅保留上游数据格式与 LOVE_LIST_NAME/DISLIKE 分隔符。
- 文档：docs/LX_SYNC.md 同步说明（如存在）。

### 5. 删除"登录音乐"功能及预留端口
- 现状核查："登录音乐"仅为一个入口卡片（导航到 'login' 页），无独立登录页/逻辑文件；全项目无 ServerSocket/端口监听实现（"预留端口"无代码实体）。
- `views/SettingsView.ets`：删除"登录音乐"入口卡片，更新相关注释。
- `docs/UI_REPLICA.md`：删除对应描述。
- 复查"登录音乐"全项目残留为 0。

### 6. 听书模块"发现"按钮（已实施）
- 评估结论：可行、工程量小（书源类型 / 沙箱 explore 动作 / BookEngine.explore() 均已就绪，仅缺 UI 入口）。
- `views/ListenView.ets`：三分段改四分段（书架 / 搜索 / **发现** / 书源），新增 PANE_EXPLORE 分段：
  - 发现书源筛选胶囊（仅列 canExplore 的源，多源时显示）；
  - 一级分类列表（`BookEngine.exploreCategories()` 解析 exploreUrl，支持 JSON 数组与"标题::地址"两种写法）；
  - 二级分类书单（`BookEngine.explore()` 走沙箱 ruleExplore，复用 BookRow 展示，点击进详情/书架）；
  - 空态处理：无支持发现的源 / 源无分类 / 分类无内容三种提示；加载中 LoadingProgress；分类与结果间"返回分类"导航。
  - 登录型书源（needLogin）仅作标识，本期不做书源登录（loginUrl 不执行），需登录的源（哔哩哔哩、喜马拉雅等）分类可能为空，已在空态文案提示。
- 未改动 core 层与沙箱（explore 链路原本就绪）。
- 详见：`output/听书模块增加发现按钮_工程量评估.md`（评估）与本条（实施）。

## 待办/未实施
- 书源登录（loginUrl 账号体系）独立评估、暂不实施。
*（内容由AI生成，仅供参考）*
