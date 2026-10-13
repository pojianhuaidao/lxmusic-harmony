import { K_HISTORY_VERSION, K_LIBRARY_VERSION, PlaySession } from '../core/player/PlaySession';
import { K_FAVORITE_IDS } from '../core/player/FavoriteIndex';
import { K_SYNC_DATA_VERSION, SyncManager } from '../core/sync/SyncManager';
import { K_LOCAL_VERSION, LocalMusic } from '../core/local/LocalMusic';
import { K_DOWNLOAD_VERSION, DownloadManager } from '../core/download/DownloadManager';
import { K_WEBDAV_VERSION, WebDavLibrary } from '../core/webdav/WebDavLibrary';
import { C_BG, C_CARD, C_CHEVRON, C_DIVIDER, C_ICON_CIRCLE, C_PRESSED, C_RED, C_RED_TINT,
  C_TEXT, C_TEXT_SUB, C_TEXT_WEAK, F_ITEM, F_SUB, R_CARD } from '../ui/Theme';
import { I_BRUSH, I_CACHE, I_CHEVRON_RIGHT, I_CLOCK, I_CLOUD, I_DISC, I_DOWNLOAD, I_FOLDER,
  I_HEART_FILLED, I_INFO, I_PERSON, I_REFRESH, I_VOLUME, IconGlyph } from '../ui/Icons';
import { TopFade } from '../ui/Widgets';

/**
 * 「我的」页那一排快捷入口
 *
 * 结构照华为音乐的「我的」：图标 + 名字 + 条数，点一下进对应的子页面（收藏进的是
 * 那张内置收藏歌单的详情）。顺序也照它：本地 / 最近播放 / 收藏 / 下载 / 云端。
 */
interface MineEntry {
  icon: Resource;
  label: string;
  action: string;
}

const ENTRIES: MineEntry[] = [
  { icon: I_FOLDER, label: '本地音乐', action: 'local' },
  { icon: I_CLOCK, label: '最近播放', action: 'history' },
  { icon: I_HEART_FILLED, label: '收藏', action: 'favorites' },
  { icon: I_DOWNLOAD, label: '下载管理', action: 'downloads' },
  { icon: I_CLOUD, label: '云端音乐', action: 'cloud' },
];

/** 设置卡：整行设置项（音源 / 同步 / 显示 / 关于） */
interface MineLink {
  icon: Resource;
  title: string;
  action: string;
}

/** 设置卡第 3 段：显示设置（原「外观」改名）/ 关于 */
const GROUP_SETTINGS_BOTTOM: MineLink[] = [
  { icon: I_BRUSH, title: '显示设置', action: 'appearance' },
  { icon: I_INFO, title: '关于', action: 'about' },
];

/** 设置卡网格（音源 / 同步 / 播放 / 缓存 / 下载 / 云音乐），图标在上、文字在下、一行两个（6 宫格 3 行） */
const GROUP_SETTINGS_GRID: MineLink[] = [
  { icon: I_DISC, title: '音源设置', action: 'source' },
  { icon: I_REFRESH, title: '同步设置', action: 'sync' },
  { icon: I_VOLUME, title: '播放设置', action: 'play' },
  { icon: I_CACHE, title: '缓存设置', action: 'cache' },
  { icon: I_DOWNLOAD, title: '下载设置', action: 'download' },
  { icon: I_PERSON, title: '云音乐设置', action: 'webdav' },
];

/**
 * 我的页
 *
 * 照华为音乐的「我的」重排：上面一排快捷入口（本地音乐 / 最近播放 / 收藏 / 下载管理 / 云端音乐），
 * 下面一张设置卡 —— 原设置页的入口整体搬了过来：
 *   - 第 1 段：音源设置 / 同步设置 / 播放设置 / 缓存设置 / 下载设置 / 云音乐设置（六宫格，图标在上、文字在下、一行两个）；
 *   - 第 2 段：显示设置（原「外观」改名）/ 关于。
 *
 * 右上角的华为账号登录入口由壳层（Index.ets）负责（标题栏人形钮），本页不再重复。
 * 歌单相关内容（自建歌单 / 收藏歌单 / 导入）已整体搬到「歌单」页（views/SongListView.ets）。
 */
@Component
export struct MineView {
  /** 内容起始偏移：让出透明标题栏那一段（状态栏 + 标题栏，由壳层算好） */
  @Prop topInset: number = 0;
  /** 内容底部要留出的空间：悬浮页签栏 + 手势条（由壳层算好） */
  @Prop bottomInset: number = 0;
  /** 去某个子页面（本地音乐 / 播放历史 / 下载 / 云端 / 音源 / 同步 / 播放 / 缓存 / 下载设置 / 云音乐 / 显示 / 关于），路由由壳层实现 */
  onNavigate: (action: string) => void = () => {
  };
  /** 内置那张收藏歌单（我的收藏）里的歌数 —— 快捷入口「收藏」下面那行数字 */
  @State favoriteCount: number = 0;
  @State localCount: number = 0;
  @State historyCount: number = 0;
  @State downloadCount: number = 0;
  @State cloudCount: number = 0;
  /**
   * 各个库的版本号：任何一个变了，卡片上的条数就重算一次
   *
   * 全部挂同一个 `refresh`：这一页的数据来自五个不同的模块（同步库 / 播放会话 /
   * 本地音乐 / 下载管理 / 云端曲库），谁变了都得重新读一遍，没必要各写一个分支。
   */
  @StorageLink(K_LIBRARY_VERSION) @Watch('refresh') libraryVersion: number = 0;
  @StorageLink(K_SYNC_DATA_VERSION) @Watch('refresh') syncVersion: number = 0;
  @StorageLink(K_HISTORY_VERSION) @Watch('refresh') historyVersion: number = 0;
  @StorageLink(K_FAVORITE_IDS) @Watch('refresh') favoriteIds: string[] = [];
  @StorageLink(K_LOCAL_VERSION) @Watch('refresh') localVersion: number = 0;
  @StorageLink(K_DOWNLOAD_VERSION) @Watch('refresh') downloadVersion: number = 0;
  @StorageLink(K_WEBDAV_VERSION) @Watch('refresh') webdavVersion: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    const library = SyncManager.getInstance().getLibrary();
    this.favoriteCount = library.favoritePlaylistSummary().count;
    this.localCount = LocalMusic.getInstance().songsForUi().length;
    this.historyCount = PlaySession.getInstance().history.length;
    this.downloadCount = DownloadManager.getInstance().list().length;
    this.cloudCount = WebDavLibrary.getInstance().songsForUi().length;
  }

  /** 快捷入口下面那行条数 */
  private countOf(action: string): number {
    if (action === 'local') {
      return this.localCount;
    }
    if (action === 'history') {
      return this.historyCount;
    }
    if (action === 'favorites') {
      return this.favoriteCount;
    }
    if (action === 'downloads') {
      return this.downloadCount;
    }
    return this.cloudCount;
  }

  // ------------------------------------------------------------ 界面

  /**
   * 快捷入口卡（照华为音乐那一排：图标在上面，名字与条数在下面）
   */
  @Builder
  quickCard() {
    Row() {
      ForEach(ENTRIES, (entry: MineEntry) => {
        Column({ space: 6 }) {
          Stack({ alignContent: Alignment.Center }) {
            // 图标底：淡红方块 + 红图形（与设置页的圆底色是同一套语汇，形状随这排入口改成圆角方）
            Column()
              .width(44)
              .height(44)
              .borderRadius(15)
              .backgroundColor(C_RED_TINT)
            IconGlyph({ symbol: entry.icon, iconSize: 23, color: C_RED })
          }
          .width(44)
          .height(44)

          Text(entry.label)
            .fontSize(F_SUB + 0.5)
            .fontColor(C_TEXT)
            .maxLines(1)
          Text(`${this.countOf(entry.action)}`)
            .fontSize(11)
            .fontColor(C_TEXT_WEAK)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .borderRadius(14)
        .stateStyles({
          normal: { .backgroundColor(Color.Transparent) },
          pressed: { .backgroundColor(C_PRESSED) },
        })
        .onClick(() => {
          this.onNavigate(entry.action);
        })
        .accessibilityText(`${entry.label}，共 ${this.countOf(entry.action)} 首`)
        .accessibilityLevel('yes')
      }, (entry: MineEntry) => entry.action)
    }
    .width('100%')
    .padding({ top: 16, bottom: 14 })
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** 设置卡里的一行：圆底图标 + 标题 + 右箭头（显示 / 关于 用） */
  @Builder
  linkRow(row: MineLink, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.6)
          .color(C_DIVIDER)
          .margin({ left: 61 })
      }

      Row({ space: 13 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor(C_ICON_CIRCLE)
          IconGlyph({ symbol: row.icon, iconSize: 20, color: C_TEXT })
        }
        .width(34)
        .height(34)

        Text(row.title)
          .fontSize(F_ITEM)
          .fontColor(C_TEXT)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        IconGlyph({ symbol: I_CHEVRON_RIGHT, iconSize: 18, color: C_CHEVRON })
          .accessibilityLevel('no')
      }
      .width('100%')
      .height(63)
      .padding({ left: 14, right: 14 })
      .stateStyles({
        normal: { .backgroundColor(Color.Transparent) },
        pressed: { .backgroundColor(C_PRESSED) },
      })
      .onClick(() => {
        this.onNavigate(row.action);
      })
      .accessibilityText(row.title)
      .accessibilityLevel('yes')
    }
    .width('100%')
  }

  /** 设置卡里的网格项：图标在上、文字在下（音源 / 同步 / 播放 / 缓存 / 下载 / 云音乐 用，一行两个） */
  @Builder
  gridItem(index: number) {
    Column({ space: 6 }) {
      IconGlyph({ symbol: GROUP_SETTINGS_GRID[index].icon, iconSize: 24, color: C_TEXT })
      Text(GROUP_SETTINGS_GRID[index].title)
        .fontSize(F_SUB + 0.5)
        .fontColor(C_TEXT)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(86)
    .justifyContent(FlexAlign.Center)
    .stateStyles({
      normal: { .backgroundColor(Color.Transparent) },
      pressed: { .backgroundColor(C_PRESSED) },
    })
    .onClick(() => {
      this.onNavigate(GROUP_SETTINGS_GRID[index].action);
    })
    .accessibilityText(GROUP_SETTINGS_GRID[index].title)
    .accessibilityLevel('yes')
  }

  /** 设置卡下面那行小字说明（与原来设置页同一套语汇） */
  @Builder
  hint(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor(C_TEXT_SUB)
      .width('100%')
      .padding({ left: 18, right: 4 })
      .textAlign(TextAlign.Start)
  }

  /**
   * 设置卡（原设置页的入口整体搬过来，一张卡三段）
   *
   *   第 1 段：音源设置 / 同步设置 / 播放设置 / 缓存设置 / 下载设置 / 云音乐设置
   *          （六宫格，图标在上、文字在下、一行两个）；
   *   第 2 段：显示设置（原「外观」）/ 关于。
   *
   * 原来的「搜索设置」已整体砍掉（连 Search 组件一起删），本卡不再有搜索框。
   */
  @Builder
  linksCard() {
    Column() {
      // ------------------------------------------------ 第 1 段：同步提示 + 设置六宫格
      this.hint('与洛雪同步服务连接后，试听列表 / 收藏 / 歌单 / 不喜欢的歌曲可与其它设备互通')

      Divider()
        .strokeWidth(0.6)
        .color(C_DIVIDER)
        .margin({ left: 14, right: 14 })

      Row() {
        this.gridItem(0)
        this.gridItem(1)
      }
      .width('100%')

      Row() {
        this.gridItem(2)
        this.gridItem(3)
      }
      .width('100%')

      Row() {
        this.gridItem(4)
        this.gridItem(5)
      }
      .width('100%')

      Divider()
        .strokeWidth(0.6)
        .color(C_DIVIDER)
        .margin({ left: 14, right: 14 })

      // ------------------------------------------------ 第 2 段：显示 / 关于
      this.linkRow(GROUP_SETTINGS_BOTTOM[0], false)
      this.linkRow(GROUP_SETTINGS_BOTTOM[1], true)
    }
    .width('100%')
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
    .clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll() {
          Column({ space: 14 }) {
            // 顶部占位：第一张卡落在透明标题栏下方，但它跟着内容一起滚走
            // （用容器内边距会把这一段裁在标题栏下缘，看着像「被顶栏挡住」）
            Column().height(this.topInset + 6).width('100%')

            this.quickCard()
            this.linksCard()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: this.bottomInset + 16 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .align(Alignment.Top)
        .width('100%')
      }
      .width('100%')
      .height('100%')

      // 顶栏渐隐：卡片从透明标题栏底下穿过时靠近顶部淡出，别顶穿「我的」两个字
      TopFade({ fadeHeight: this.topInset + 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_BG)
  }
}
