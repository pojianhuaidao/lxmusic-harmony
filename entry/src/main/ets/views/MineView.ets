import { K_HISTORY_VERSION, K_LIBRARY_VERSION, PlaySession } from '../core/player/PlaySession';
import { K_FAVORITE_IDS } from '../core/player/FavoriteIndex';
import { K_SYNC_DATA_VERSION, SyncManager } from '../core/sync/SyncManager';
import { K_LOCAL_VERSION, LocalMusic } from '../core/local/LocalMusic';
import { K_DOWNLOAD_VERSION, DownloadManager } from '../core/download/DownloadManager';
import { K_WEBDAV_VERSION, WebDavLibrary } from '../core/webdav/WebDavLibrary';
import { C_BG, C_CARD, C_PRESSED, C_RED, C_RED_TINT,
  C_TEXT, C_TEXT_WEAK, F_SUB, R_CARD } from '../ui/Theme';
import { I_CLOCK, I_CLOUD, I_DOWNLOAD, I_FOLDER,
  I_HEART_FILLED, IconGlyph } from '../ui/Icons';
import { SectionTitle, TopFade } from '../ui/Widgets';
import { SourceSettingsView } from './SourceSettingsView';
import { PlaySettingsView } from './PlaySettingsView';
import { DownloadSettingsView } from './DownloadSettingsView';
import { CacheSettingsView } from './CacheSettingsView';
import { AppearanceSettingsView } from './AppearanceSettingsView';
import { BackupOptionsView } from './BackupOptionsView';
import { WebDavSettingsView } from './WebDavSettingsView';
import { AboutView } from './AboutView';

/** 底部栏收起/展开触发阈值（vp）：同方向累计滚动超过它才切换状态 */
const FOLD_THRESHOLD: number = 24;

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

/**
 * 设置区：原来那张「六宫格 + 显示/关于两行」的入口卡已经拆掉 ——
 * 现在把每一页设置按 embedded 模式直接摊在「我的」页里，从上往下一路读到底
 * （音源 / 播放 / 下载 / 缓存 / 显示 / 备份与恢复 / 云音乐 / 关于），不再点进子页面。
 */

/**
 * 我的页
 *
 * 照华为音乐的「我的」重排：上面一排快捷入口（本地音乐 / 最近播放 / 收藏 / 下载管理 / 云端音乐），
 * 下面一张设置卡 —— 原设置页的入口整体搬了过来：
 *   - 第 1 段：音源设置 / 同步设置 / 播放设置 / 缓存设置 / 下载设置 / 云音乐设置（六宫格，图标在上、文字在下、一行两个）；
 *   - 第 2 段：显示设置（原「外观」改名）/ 关于。
 *
 * 华为账号 / 华为云空间那条备份链路端侧跑不通，已整体移除（含壳层标题栏的人形钮），
 * 备份只剩 WebDAV 一条，见 views/BackupOptionsView.ets。
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
  /** 壳层底部栏收起/展开回调：内容下滑（offset 增大）传 true 收起，上滑传 false 展开 */
  onFoldChange: (folded: boolean) => void = () => {
  };
  /** 上次滚动偏移量 / 向下(收起)累计 / 向上(展开)累计：同方向累计超过阈值才回调一次 */
  private foldAccumDown: number = 0;
  private foldAccumUp: number = 0;

  /**
   * 把滚动增量上报给壳层：内容向上滚（手指上滑浏览，yOffset 为正）累计超过阈值 → 收起并排，
   * 内容向下滚（回顶，yOffset 为负）累计超过阈值 → 展开两行。
   *
   * 华为文档明确 onScroll 回调的 xOffset/yOffset 是「相对上一帧的增量」而非绝对偏移，
   * 所以这里直接消费增量即可（不要再用 lastFoldY 做差，那会把增量二次求差、永远≈0，
   * 导致下拉/上拉都触发不了收展）。同一方向连续累计，超过 FOLD_THRESHOLD vp 才回调一次；
   * 出现另一方向时立即清零对方累计 —— 轻微抖动、松手惯性回弹（几 vp）都不会误触。
   */
  private handleFoldScroll(delta: number): void {
    if (delta > 0) {
      this.foldAccumUp = 0;
      this.foldAccumDown += delta;
      if (this.foldAccumDown >= FOLD_THRESHOLD) {
        this.foldAccumDown = 0;
        this.onFoldChange(true);
      }
    } else if (delta < 0) {
      this.foldAccumDown = 0;
      this.foldAccumUp += -delta;
      if (this.foldAccumUp >= FOLD_THRESHOLD) {
        this.foldAccumUp = 0;
        this.onFoldChange(false);
      }
    }
  }
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

  /** 一个设置分区的标题（音源设置 / 播放设置 …「关于」） */
  @Builder
  sectionHead(text: string) {
    Row() {
      SectionTitle({ text: text })
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 6, bottom: 2 })
  }

  /**
   * 设置区（全部平铺，不点进子页面）
   *
   * 每一页设置都用 embedded 模式挂在这里：内层不要自己的 Scroll、不要顶部避让、
   * 左右留边交给本页统一给（否则会叠成双重内边距）。外层这一个 Scroll 管全部设置，
   * 列表跟着内容一路展开到底。
   */
  @Builder
  settingsFlat() {
    Column({ space: 6 }) {
      this.sectionHead('音源设置')
      SourceSettingsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('播放设置')
      PlaySettingsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('下载设置')
      DownloadSettingsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('缓存设置')
      CacheSettingsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('显示设置')
      AppearanceSettingsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('备份与恢复')
      BackupOptionsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('云音乐设置')
      WebDavSettingsView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')

    Column({ space: 6 }) {
      this.sectionHead('关于')
      AboutView({ embedded: true, topInset: 0, bottomInset: 0 })
    }
    .width('100%')
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
            this.settingsFlat()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: this.bottomInset + 16 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onScroll((_xOffset: number, yOffset: number) => {
          this.handleFoldScroll(yOffset);
        })
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
