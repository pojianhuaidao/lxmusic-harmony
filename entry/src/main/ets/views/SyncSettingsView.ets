import { C_BG, C_CARD, C_DIVIDER, C_FILL_SOFT, C_ICON_GREEN, C_RED, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK, F_ITEM, F_SECTION, F_SUB, R_CARD } from '../ui/Theme';
import { I_PLUS, I_TRASH, IconGlyph } from '../ui/Icons';
import { LibrarySummary } from '../core/sync/LocalLibrary';
import { K_SYNC_DATA_VERSION, SyncManager } from '../core/sync/SyncManager';
import { BACKUP_DIR, BACKUP_FILE, WebDavBackup } from '../core/webdav/WebDavBackup';
import { K_WEBDAV_URL, K_WEBDAV_USER, WebDavSettings } from '../core/webdav/WebDavSettings';
import { dustBus, DustPoint, dustPointOf } from '../ui/Dust';

/**
 * 数据备份（WebDAV）
 *
 * 与安卓版（lx-music-mobile）对齐：备份到 WebDAV 服务器上的 `LX Backup` 目录，
 * 复用「WebDAV 云端音乐」的同一套账号（url / username / password），
 * 文件名加 hm 后缀（lx_data_hm.lxmc）与安卓版（lx_data.lxmc）区分。
 * 本地参与备份的数据（试听列表 / 我的收藏 / 歌单 / 不喜欢规则）摊开在这里。
 */
@Component
export struct SyncSettingsView {
  /** 内容让出标题栏那一段（壳层传来的「状态栏 + 标题栏」）：见滚动内容里的顶部占位 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @StorageLink(K_WEBDAV_URL) @Watch('onAccountChanged') webdavUrl: string = '';
  @StorageLink(K_WEBDAV_USER) @Watch('onAccountChanged') webdavUser: string = '';
  @StorageLink(K_SYNC_DATA_VERSION) @Watch('onDataChanged') dataVersion: number = 0;
  @State summaryText: string = '';
  @State backupStatus: string = '';
  @State busy: boolean = false;
  @State dislikeRules: string[] = [];
  /** 最近一次触摸点：删规则时在这里撒一把粒子（普通字段，不引起重绘） */
  private dustX: number = 0;
  private dustY: number = 0;
  @State newName: string = '';
  @State newSinger: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  onAccountChanged(): void {
    this.refresh();
  }

  onDataChanged(): void {
    this.refresh();
  }

  private refresh(): void {
    const library = SyncManager.getInstance().getLibrary();
    const summary: LibrarySummary = library.summary();
    this.summaryText = `试听列表 ${library.listData().defaultList.length} 首 · ` +
      `收藏 ${library.listData().loveList.length} 首 · 歌单 ${summary.playlists} 个`;
    this.dislikeRules = library.dislikeRuleList();
  }

  private async backupNow(): Promise<void> {
    const settings = WebDavSettings.getInstance();
    if (!settings.isConfigured()) {
      this.backupStatus = '请先在「WebDAV 云端音乐」里配置服务器地址与账号';
      return;
    }
    this.busy = true;
    this.backupStatus = '正在备份…';
    try {
      const result = await WebDavBackup.getInstance().backup(settings.config());
      this.backupStatus = result.message;
    } catch (e) {
      this.backupStatus = `备份失败：${(e as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  private async restoreNow(): Promise<void> {
    const settings = WebDavSettings.getInstance();
    if (!settings.isConfigured()) {
      this.backupStatus = '请先在「WebDAV 云端音乐」里配置服务器地址与账号';
      return;
    }
    this.busy = true;
    this.backupStatus = '正在恢复…';
    try {
      const result = await WebDavBackup.getInstance().restore(settings.config());
      this.backupStatus = result.message;
      if (result.ok) {
        SyncManager.getInstance().bumpDataVersion();
        this.refresh();
      }
    } catch (e) {
      this.backupStatus = `恢复失败：${(e as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  private addDislikeRule(): void {
    const name: string = this.newName.trim();
    const singer: string = this.newSinger.trim();
    if (name.length === 0 && singer.length === 0) {
      return;
    }
    SyncManager.getInstance().getLibrary().addDislike(name, singer);
    this.newName = '';
    this.newSinger = '';
    this.refresh();
  }

  private removeDislikeRule(rule: string): void {
    SyncManager.getInstance().getLibrary().removeDislikeRule(rule);
    // 删除给一点粒子飘散（在触摸点撒，不在支持的系统上自动不做）
    dustBus.spray(this.dustX, this.dustY);
    this.refresh();
  }

  private rememberTouch(event: TouchEvent): void {
    const point: DustPoint | null = dustPointOf(event);
    if (point !== null) {
      this.dustX = point.x;
      this.dustY = point.y;
    }
  }

  private clearDislikeRules(): void {
    SyncManager.getInstance().getLibrary().clearDislike();
    this.refresh();
  }

  @Builder
  sectionCard(title: string, subtitle: string) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(F_SECTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(C_TEXT)
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(F_SUB)
          .fontColor(C_TEXT_WEAK)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, bottom: 6 })
  }

  /** 账号卡：显示当前 WebDAV 账号状态（与「WebDAV 云端音乐」共用同一套账号） */
  @Builder
  accountCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('备份账号')
          .fontSize(F_SECTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_TEXT)
        Text(this.webdavUrl.length > 0 ? '已配置' : '未配置')
          .fontSize(F_SUB)
          .fontColor(this.webdavUrl.length > 0 ? C_ICON_GREEN : C_RED)
      }
      .width('100%')

      if (this.webdavUrl.length > 0) {
        Text(`服务器：${this.webdavUrl}`)
          .fontSize(F_SUB)
          .fontColor(C_TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
        Text(`账号：${this.webdavUser.length > 0 ? this.webdavUser : '匿名'}`)
          .fontSize(F_SUB)
          .fontColor(C_TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
      } else {
        Text('还没有配置 WebDAV 服务器。请先到「我的 - WebDAV 云端音乐」里填写服务器地址、用户名和密码，备份会复用同一套账号。')
          .fontSize(F_SUB)
          .fontColor(C_TEXT_SUB)
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

  /** 备份目标卡：说明与安卓版一致的目录与文件名规则 */
  @Builder
  targetCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('备份位置')
          .fontSize(F_SECTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_TEXT)
      }
      .width('100%')

      Text(`远端目录：${BACKUP_DIR}`)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text(`备份文件：${BACKUP_FILE}`)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text('与安卓版（lx-music-mobile）放在同一个 LX Backup 文件夹、共享同一套 WebDAV 账号；'
        + '文件名的 hm 后缀用于区分鸿蒙版，互不覆盖。')
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** 操作卡：备份 / 恢复按钮 + 状态文案 */
  @Builder
  opsCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button('立即备份')
          .fontSize(F_ITEM)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(C_RED)
          .enabled(!this.busy)
          .onClick(() => {
            void this.backupNow();
          })
        Button('从备份恢复')
          .fontSize(F_ITEM)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(C_FILL_SOFT)
          .fontColor(C_TEXT)
          .enabled(!this.busy)
          .onClick(() => {
            void this.restoreNow();
          })
      }
      .width('100%')

      if (this.backupStatus.length > 0) {
        Text(this.backupStatus)
          .fontSize(F_SUB)
          .fontColor(this.backupStatus.startsWith('已') ? C_ICON_GREEN : C_TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      Text('恢复会用备份内容覆盖本机当前的试听列表 / 收藏 / 歌单 / 不喜欢规则，请谨慎操作。')
        .fontSize(11.5)
        .fontColor(C_TEXT_WEAK)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** 同步内容卡：说明备份了哪些数据 */
  @Builder
  syncContentCard() {
    Column({ space: 6 }) {
      this.sectionCard('备份内容', this.summaryText)
      Text('试听列表 = 本机的播放队列；收藏、歌单与不喜欢的歌曲规则都会备份到云端。')
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .padding({ left: 4, right: 4 })
        .textAlign(TextAlign.Start)
      Text('注意：本地歌曲无法备份 —— 与安卓版一致，本地音乐（从设备导入的音频）'
        + '不会上传到 WebDAV，只保留在本机（详见 docs/LOCAL_MUSIC.md）。')
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .padding({ left: 4, right: 4 })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
  }

  @Builder
  dislikeCard() {
    Column() {
      Row({ space: 8 }) {
        Text('不喜欢的歌曲')
          .fontSize(F_SECTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_TEXT)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        if (this.dislikeRules.length > 0) {
          Text(`清空`)
            .fontSize(F_SUB)
            .fontColor(C_RED)
            .onClick(() => {
              this.clearDislikeRules();
            })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })

      if (this.dislikeRules.length === 0) {
        Text('暂无规则。规则来自备份恢复，也可以在下面手动添加。')
          .fontSize(F_SUB)
          .fontColor(C_TEXT_WEAK)
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 12 })
          .textAlign(TextAlign.Start)
      } else {
        ForEach(this.dislikeRules, (rule: string, index: number) => {
          Column() {
            Row({ space: 10 }) {
              Text(describeDislikeRule(rule))
                .fontSize(14)
                .fontColor(C_TEXT)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Start)
              IconGlyph({ symbol: I_TRASH, iconSize: 17, color: C_TEXT_WEAK })
                .onClick(() => {
                  this.removeDislikeRule(rule);
                })
                .onTouch((event: TouchEvent) => {
                  this.rememberTouch(event);
                })
            }
            .width('100%')
            .height(46)
            .padding({ left: 14, right: 14 })
            if (index < this.dislikeRules.length - 1) {
              Divider().strokeWidth(0.6).color(C_DIVIDER).margin({ left: 14 })
            }
          }
          .width('100%')
        }, (rule: string, index: number) => `${index}_${rule}`)
      }

      Divider().strokeWidth(0.6).color(C_DIVIDER).margin({ left: 14 })

      Row({ space: 8 }) {
        TextInput({ text: this.newName, placeholder: '歌名' })
          .placeholderColor(C_TEXT_WEAK)
          .placeholderFont({ size: 13 })
          .fontSize(13)
          .backgroundColor(C_FILL_SOFT)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.newName = value;
          })
        TextInput({ text: this.newSinger, placeholder: '歌手' })
          .placeholderColor(C_TEXT_WEAK)
          .placeholderFont({ size: 13 })
          .fontSize(13)
          .backgroundColor(C_FILL_SOFT)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.newSinger = value;
          })
        IconGlyph({ symbol: I_PLUS, iconSize: 20, color: C_RED })
          .onClick(() => {
            this.addDislikeRule();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 12 })
    }
    .width('100%')
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
    .clip(true)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 顶部占位：第一行落在透明标题栏下方，但它跟着内容一起滚走 —— 用容器内边距会把
          // 这一段内容裁在标题栏下边缘，看起来就"像被顶栏挡住"（首页就是这么做的）
          Column().height(this.topInset + 6).width('100%')
          this.accountCard()
          this.targetCard()
          this.opsCard()

          Column({ space: 6 }) {
            this.syncContentCard()
          }
          .width('100%')

          this.dislikeCard()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.bottomInset + 16 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_BG)
  }
}

/** '歌名@歌手' / '歌名' / '@歌手' 的展示形式 */
function describeDislikeRule(rule: string): string {
  const at: number = rule.indexOf('@');
  if (at < 0) {
    return `歌名：${rule}`;
  }
  const name: string = rule.substring(0, at);
  const singer: string = rule.substring(at + 1);
  if (name.length === 0) {
    return `歌手：${singer}`;
  }
  if (singer.length === 0) {
    return `歌名：${name}`;
  }
  return `${name} — ${singer}`;
}
