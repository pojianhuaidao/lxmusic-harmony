import { common } from '@kit.AbilityKit';
import { LibrarySummary } from '../core/sync/LocalLibrary';
import { K_SYNC_DATA_VERSION, SyncManager } from '../core/sync/SyncManager';
import { BACKUP_DIR, BACKUP_FILE, WebDavBackup } from '../core/webdav/WebDavBackup';
import { ALL_SCOPE, BackupScope } from '../core/webdav/WebDavBackup';
import { K_WEBDAV_URL, K_WEBDAV_USER, WebDavSettings } from '../core/webdav/WebDavSettings';
import { C_BG, C_CARD, C_FILL_SOFT, C_ICON_GREEN, C_RED, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK,
  F_ITEM, F_SECTION, F_SUB, R_CARD } from '../ui/Theme';
import { HintText } from '../ui/SettingWidgets';
import { I_CLOUD, I_REFRESH, IconGlyph } from '../ui/Icons';

/**
 * 备份选项（由「其他设置」里的「数据」改名而来）
 *
 * 只保留 WebDAV 一条备份 / 恢复链路：与安卓版 lx-music-mobile 共享同一套账号与
 * Music Backup 目录（华为云空间那条链路端侧跑不通，已整体移除）。
 * 参与备份的数据一致：试听列表 / 收藏 / 歌单 / 不喜欢规则（由 LocalLibrary 提供）。
 */
@Component
export struct BackupOptionsView {
  /** 平铺模式：由「我的」页把这一页的设置直接展开，不要自成滚动页 */
  @Prop embedded: boolean = false;
  /** 内容让出标题栏那一段（壳层传来的「状态栏 + 标题栏」）：见滚动内容里的顶部占位 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @StorageLink(K_WEBDAV_URL) @Watch('refresh') webdavUrl: string = '';
  @StorageLink(K_WEBDAV_USER) @Watch('refresh') webdavUser: string = '';
  @StorageLink(K_SYNC_DATA_VERSION) @Watch('refresh') dataVersion: number = 0;
  @State summaryText: string = '';
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
    if (this.embedded) {
      // 平铺模式（「我的」页把每一页设置摊开）：不要自己的滚动与顶部避让，高度随内容长，
      // 滚动交给外层页面；左右留边也由外层统一给，免得两侧叠成双重内边距。
      this.body()
    } else {
      Column() {
        Scroll() {
          this.body()
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

  /** 页面主体（独立页 / 「我的」页平铺共用）：embedded 时不留顶部与左右留边 */
  @Builder
  body() {
    Column({ space: 14 }) {
      Column().height(this.embedded ? 0 : this.topInset + 6).width('100%')
      this.webdavCard()
      this.contentCard()
    }
    .width('100%')
    .padding({
      left: this.embedded ? 0 : 16,
      right: this.embedded ? 0 : 16,
      top: this.embedded ? 0 : 8,
      bottom: this.embedded ? 6 : this.bottomInset + 16,
    })
  }
}
