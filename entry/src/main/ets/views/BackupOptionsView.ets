import { common } from '@kit.AbilityKit';
import { LibrarySummary } from '../core/sync/LocalLibrary';
import { K_SYNC_DATA_VERSION, SyncManager } from '../core/sync/SyncManager';
import { BACKUP_DIR, BACKUP_FILE, WebDavBackup } from '../core/webdav/WebDavBackup';
import { ALL_SCOPE, BackupScope } from '../core/webdav/WebDavBackup';
import { K_WEBDAV_URL, K_WEBDAV_USER, WebDavSettings } from '../core/webdav/WebDavSettings';
import { HuaweiAccount, K_ACCOUNT_NAME, K_ACCOUNT_UID } from '../core/account/HuaweiAccount';
import { C_BG, C_CARD, C_FILL_SOFT, C_ICON_GREEN, C_RED, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK,
  F_ITEM, F_SECTION, F_SUB, R_CARD } from '../ui/Theme';
import { HintText } from '../ui/SettingWidgets';
import { I_CLOUD, I_PERSON, I_REFRESH, IconGlyph } from '../ui/Icons';

/**
 * 备份选项（由「其他设置」里的「数据」改名而来）
 *
 * 提供两条备份 / 恢复链路：
 *   1. 华为账号：登录（右上角 / 本页）后把音乐数据备份到使用者自己的华为云空间
 *      （端云文件协同，el2/cloud 目录自动同步；远端目录 music_backups/music_data_hm.mbak，
 *      旧名 lx_data_hw.lxmc 仅恢复时兼容），同时写一份本地端侧镜像兜底；
 *   2. WebDAV：与安卓版 lx-music-mobile 共享同一套账号与 Music Backup 目录。
 * 参与备份的数据一致：试听列表 / 收藏 / 歌单 / 不喜欢规则（由 LocalLibrary 提供）。
 */
@Component
export struct BackupOptionsView {
  /** 内容让出标题栏那一段（壳层传来的「状态栏 + 标题栏」）：见滚动内容里的顶部占位 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @StorageLink(K_ACCOUNT_UID) @Watch('refreshAccount') accountUid: string = '';
  @StorageLink(K_ACCOUNT_NAME) @Watch('refreshAccount') accountName: string = '';
  @StorageLink(K_WEBDAV_URL) @Watch('refresh') webdavUrl: string = '';
  @StorageLink(K_WEBDAV_USER) @Watch('refresh') webdavUser: string = '';
  @StorageLink(K_SYNC_DATA_VERSION) @Watch('refresh') dataVersion: number = 0;
  @State summaryText: string = '';
  @State hwStatus: string = '';
  @State hwBusy: boolean = false;
  @State webdavStatus: string = '';
  @State webdavBusy: boolean = false;
  // 备份内容勾选（默认全选；与 WebDavBackup.BackupScope 对应）
  @State scopePlayList: boolean = true;
  @State scopeLoveList: boolean = true;
  @State scopePlaylists: boolean = true;
  @State scopeDislike: boolean = true;
  @State scopeSources: boolean = true;

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    const library = SyncManager.getInstance().getLibrary();
    const summary: LibrarySummary = library.summary();
    this.summaryText = `试听列表 ${library.listData().defaultList.length} 首 · ` +
      `收藏 ${library.listData().loveList.length} 首 · 歌单 ${summary.playlists} 个`;
  }

  private refreshAccount(): void {
    // 登录态变化时清掉上一次的提示，避免旧文案误导
    this.hwStatus = '';
  }

  // ------------------------------------------------------------ 华为账号

  /** 按下方勾选组装备份范围 */
  private buildScope(): BackupScope {
    return {
      playList: this.scopePlayList,
      loveList: this.scopeLoveList,
      playlists: this.scopePlaylists,
      dislike: this.scopeDislike,
      sources: this.scopeSources,
    };
  }

  private hwBackup(): void {
    if (this.accountUid.length === 0) {
      this.hwStatus = '请先登录华为账号';
      return;
    }
    this.hwBusy = true;
    this.hwStatus = '正在备份到华为云空间…';
    const context: common.Context = getContext(this) as common.Context;
    // 整体超时兜底：底层链路（上传启动 + 任务等待）即使因 SDK 挂起永不返回，
    // 这里也强制复位 hwBusy 并提示失败，杜绝"备份中"永远卡死
    const timer: number = setTimeout(() => {
      this.hwBusy = false;
      this.hwStatus = '备份超时，请检查网络后重试';
    }, 120000);
    HuaweiAccount.getInstance().backup(context, this.buildScope()).then((result) => {
      clearTimeout(timer);
      this.hwStatus = result.message;
      this.hwBusy = false;
    }).catch((e: Error) => {
      clearTimeout(timer);
      this.hwStatus = `备份失败：${e.message}`;
      this.hwBusy = false;
    });
  }

  private hwRestore(): void {
    if (this.accountUid.length === 0) {
      this.hwStatus = '请先登录华为账号';
      return;
    }
    this.hwBusy = true;
    this.hwStatus = '正在从华为云空间恢复…';
    const context: common.Context = getContext(this) as common.Context;
    // 整体超时兜底：同 hwBackup，防止恢复链路挂起导致"恢复中"永远卡死
    const timer: number = setTimeout(() => {
      this.hwBusy = false;
      this.hwStatus = '恢复超时，请检查网络后重试';
    }, 120000);
    HuaweiAccount.getInstance().restore(context).then((result) => {
      clearTimeout(timer);
      this.hwStatus = result.message;
      if (result.ok) {
        SyncManager.getInstance().bumpDataVersion();
        this.refresh();
      }
      this.hwBusy = false;
    }).catch((e: Error) => {
      clearTimeout(timer);
      this.hwStatus = `恢复失败：${e.message}`;
      this.hwBusy = false;
    });
  }

  // ------------------------------------------------------------ WebDAV

  private webdavBackup(): void {
    const settings = WebDavSettings.getInstance();
    if (!settings.isConfigured()) {
      this.webdavStatus = '请先在「云音乐设置」里配置服务器地址与账号';
      return;
    }
    this.webdavBusy = true;
    this.webdavStatus = '正在备份…';
    const context: common.Context = getContext(this) as common.Context;
    WebDavBackup.getInstance().backup(settings.config(), context).then((result) => {
      this.webdavStatus = result.message;
      this.webdavBusy = false;
    }).catch((e: Error) => {
      this.webdavStatus = `备份失败：${e.message}`;
      this.webdavBusy = false;
    });
  }

  private webdavRestore(): void {
    const settings = WebDavSettings.getInstance();
    if (!settings.isConfigured()) {
      this.webdavStatus = '请先在「云音乐设置」里配置服务器地址与账号';
      return;
    }
    this.webdavBusy = true;
    this.webdavStatus = '正在恢复…';
    const context: common.Context = getContext(this) as common.Context;
    WebDavBackup.getInstance().restore(settings.config(), context).then((result) => {
      this.webdavStatus = result.message;
      if (result.ok) {
        SyncManager.getInstance().bumpDataVersion();
        this.refresh();
      }
      this.webdavBusy = false;
    }).catch((e: Error) => {
      this.webdavStatus = `恢复失败：${e.message}`;
      this.webdavBusy = false;
    });
  }

  // ------------------------------------------------------------ 界面

  /** 图标 + 文字平铺的卡片标题行（与「播放设置」等设置页统一观感） */
  @Builder
  cardTitle(icon: Resource, title: string, trailing: string, trailingColor: ResourceColor = C_TEXT_WEAK) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(C_FILL_SOFT)
        IconGlyph({ symbol: icon, iconSize: 17, color: C_TEXT })
      }
      .width(30)
      .height(30)
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(C_TEXT)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(F_SUB)
          .fontColor(trailingColor)
      }
    }
    .width('100%')
  }


  /** 华为账号卡：登录态 + 备份 / 恢复操作 */
  @Builder
  huaweiCard() {
    Column({ space: 12 }) {
      this.cardTitle(I_PERSON, '华为账号', this.accountUid.length > 0 ? '已登录' : '未登录',
        this.accountUid.length > 0 ? C_ICON_GREEN : C_RED)

      if (this.accountUid.length > 0) {
        Text(`账号：${this.accountName.length > 0 ? this.accountName : '华为账号'}（${this.accountUid}）`)
          .fontSize(F_SUB)
          .fontColor(C_TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
        HintText({ text: '登录后按下方勾选，把试听列表 / 收藏 / 歌单 / 不喜欢规则 / 音源备份到你的华为云空间'
          + '，或随时恢复回来。请在系统「设置 - 云空间」打开本应用的同步开关，备份会自动同步到你的云空间；未开同步时会回退读取本地端侧镜像。' })
        Row({ space: 12 }) {
          Button('备份到华为云空间')
            .fontSize(F_ITEM)
            .height(40)
            .layoutWeight(1)
            .backgroundColor(C_RED)
            .enabled(!this.hwBusy)
            .onClick(() => {
              this.hwBackup();
            })
          Button('从华为云空间恢复')
            .fontSize(F_ITEM)
            .height(40)
            .layoutWeight(1)
            .backgroundColor(C_FILL_SOFT)
            .fontColor(C_TEXT)
            .enabled(!this.hwBusy)
            .onClick(() => {
              this.hwRestore();
            })
        }
        .width('100%')

        Text('退出登录')
          .fontSize(F_SUB)
          .fontColor(C_RED)
          .width('100%')
          .textAlign(TextAlign.End)
          .onClick(() => {
            HuaweiAccount.getInstance().logout();
            this.hwStatus = '';
          })
      } else {
        HintText({ text: '登录华为账号后，可把音乐数据备份到你的华为云空间，或随时恢复回来。' })
        HintText({ text: '登录入口在「我的」页右上角。' })
      }

      if (this.hwStatus.length > 0) {
        Text(this.hwStatus)
          .fontSize(F_SUB)
          .fontColor(this.hwStatus.startsWith('已') ? C_ICON_GREEN : C_TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** WebDAV 备份卡：沿用原「数据」里那套 WebDAV 备份能力 */
  @Builder
  webdavCard() {
    Column({ space: 12 }) {
      this.cardTitle(I_CLOUD, 'WebDAV 备份', this.webdavUrl.length > 0 ? '已配置' : '未配置',
        this.webdavUrl.length > 0 ? C_ICON_GREEN : C_RED)

      Text(`远端目录：${BACKUP_DIR} · 备份文件：${BACKUP_FILE}`)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .textAlign(TextAlign.Start)
      HintText({ text: '备份目录为 Music Backup，账号在「我的 - 云音乐设置」里配置。' })

      Row({ space: 12 }) {
        Button('立即备份')
          .fontSize(F_ITEM)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(C_RED)
          .enabled(!this.webdavBusy)
          .onClick(() => {
            this.webdavBackup();
          })
        Button('从备份恢复')
          .fontSize(F_ITEM)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(C_FILL_SOFT)
          .fontColor(C_TEXT)
          .enabled(!this.webdavBusy)
          .onClick(() => {
            this.webdavRestore();
          })
      }
      .width('100%')

      if (this.webdavStatus.length > 0) {
        Text(this.webdavStatus)
          .fontSize(F_SUB)
          .fontColor(this.webdavStatus.startsWith('已') ? C_ICON_GREEN : C_TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      HintText({ text: '恢复会用备份内容覆盖本机当前的试听列表 / 收藏 / 歌单 / 不喜欢规则，请谨慎操作。' })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** 备份内容卡 */
  @Builder
  contentCard() {
    Column({ space: 4 }) {
      this.cardTitle(I_REFRESH, '备份内容', this.summaryText)

      HintText({ text: '勾选要参与备份 / 恢复的项目；恢复时只覆盖勾选的类别，未勾选的保留本机现状。' })

      this.scopeRow('试听列表', '本机播放队列', this.scopePlayList, (v: boolean) => {
        this.scopePlayList = v;
      })
      this.scopeRow('收藏', '我喜欢的歌曲', this.scopeLoveList, (v: boolean) => {
        this.scopeLoveList = v;
      })
      this.scopeRow('歌单', '自建与收藏的歌单', this.scopePlaylists, (v: boolean) => {
        this.scopePlaylists = v;
      })
      this.scopeRow('不喜欢规则', '不喜欢的歌曲过滤', this.scopeDislike, (v: boolean) => {
        this.scopeDislike = v;
      })
      this.scopeRow('音源', '自建 / 导入的音源脚本', this.scopeSources, (v: boolean) => {
        this.scopeSources = v;
      })

      HintText({ text: '本地歌曲不会上传 —— 与安卓版一致，本地音乐（从设备导入的音频）只保留在本机。' })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** 单行勾选项 */
  @Builder
  scopeRow(label: string, desc: string, checked: boolean, onChange: (v: boolean) => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(F_ITEM)
        .fontColor(C_TEXT)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      Text(desc)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_WEAK)
      Checkbox({ name: label })
        .select(checked)
        .width(20)
        .height(20)
        .onChange((v: boolean) => {
          onChange(v);
        })
    }
    .width('100%')
    .height(38)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          Column().height(this.topInset + 6).width('100%')
          this.huaweiCard()
          this.webdavCard()
          this.contentCard()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.bottomInset + 16 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_BG)
  }
}
