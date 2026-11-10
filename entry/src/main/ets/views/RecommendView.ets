import { LIST_PLATFORMS, LxBoardItem, LxPlaylistItem, LxSortItem, OnlineRoute, getBoards, getRecommendPlaylists, platformName, sortListOf } from '../core/music/MusicList';
import { C_BG, C_CHEVRON, C_ON_ACCENT, C_RED, C_RED_TINT, C_SEG_BG, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK,
  F_ITEM, F_SUB } from '../ui/Theme';
import { I_CHEVRON_DOWN, I_CHEVRON_RIGHT, I_MIC, IconGlyph } from '../ui/Icons';
import { CoverArt, SectionTitle, TopFade } from '../ui/Widgets';
import { HdsFlowLightBackground } from '../ui/Hds';
import { immersiveMaterialFor, thinGlass } from '../ui/Glass';
import { K_FLOW_LIGHT, K_MATERIAL_LEVEL } from '../core/settings/AppearanceSettings';

/** 底部栏收起/展开触发阈值（vp）：同方向累计滚动超过它才切换状态 */
const FOLD_THRESHOLD: number = 24;

/**
 * 顶部平台按钮（页内一排五个）
 *
 * 顺序按用户口径：TX / KW / KG / MG / WY —— 一个按钮对应一个平台的网页歌单页，
 * 点哪个就按那个平台的推荐歌单口径重拉一遍，和「隔壁多媒体」的音乐页是同一套用法。
 */
const R_TAB_SOURCES: string[] = ['tx', 'kw', 'kg', 'mg', 'wy'];
const R_TAB_LABELS: string[] = ['TX', 'KW', 'KG', 'MG', 'WY'];

/** 在线排行榜卡片（紧凑版：边长 64vp，约「两个图标」的量级，五字榜名两行放得下） */
@Component
struct RankCard {
  @Prop title: string = '';
  @Prop platform: string = '';
  @Prop colorA: string = '#7B6CF6';
  @Prop colorB: string = '#4E3FD6';
  onTap: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 渐变底：小卡片不再叠压暗层，靠圆角 + 白字保持辨识度
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 160, colors: [[this.colorA, 0.0], [this.colorB, 1.0]] })

      Column({ space: 2 }) {
        // 顶部：平台标（小圆点 + 平台名），一行 8fp，占高度很少
        Row({ space: 3 }) {
          Circle().width(7).height(7).fill('#FFFFFF').opacity(0.85)
          Text(this.platform)
            .fontSize(8.5)
            .fontColor('#CCFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Blank()

        // 榜名：两行以内（「抖音热歌榜」这类五字榜名正好两行放下）
        Text(this.title)
          .fontSize(11.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
          .lineHeight(14)
          .textShadow({ radius: 5, color: '#33000000', offsetX: 0, offsetY: 1 })

        Blank()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(12)
    .clip(true)
    .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 榜单卡片的配色（按榜单顺序循环取，同榜每次进入颜色不变） */
const BOARD_COLORS: string[][] = [
  ['#7B6CF6', '#4E3FD6'],
  ['#3FD07A', '#17A94F'],
  ['#FF7A59', '#E2432F'],
  ['#4FA8FF', '#1E6FD9'],
  ['#FFB13D', '#E0810F'],
  ['#F26DB4', '#C22C86'],
];

function boardColors(index: number): string[] {
  return BOARD_COLORS[index % BOARD_COLORS.length];
}

/** 榜单小卡尺寸（vp）：边长按「两个图标」量级给（64vp），五字榜名两行放得下 */
const BOARD_CARD_HEIGHT: number = 64;
/** 单张卡允许的最小宽度，用来算一行能放几个（列宽由 1fr 均分，通常略大于它） */
const BOARD_MIN_WIDTH: number = 72;
const BOARD_GAP: number = 8;

/** 空条目哨兵：数据源刷新期间框架可能按旧 totalCount 请求越界索引，返回空条目避免渲染 undefined */
const EMPTY_PLAYLIST_ITEM: LxPlaylistItem = {
  id: '',
  name: '',
  author: '',
  img: '',
  desc: '',
  playCount: '',
  total: 0,
  time: '',
  source: '',
};

/** 推荐歌单列表的懒加载数据源（一页 30 条、可继续上拉，用 LazyForEach 更稳） */
class PlaylistSource implements IDataSource {
  private items: LxPlaylistItem[] = [];
  private listeners: DataChangeListener[] = [];

  setItems(items: LxPlaylistItem[]): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): LxPlaylistItem {
    if (index < 0 || index >= this.items.length) {
      // 数据源刷新（setItems -> onDataReloaded）期间框架可能按旧 totalCount 请求旧索引
      return EMPTY_PLAYLIST_ITEM;
    }
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }
}

/**
 * 推荐来源的持久化键（放在 AppStorage 里，切页签回来还在）
 *
 * 导出给壳层用：「推荐来源」那个胶囊跟「搜索」钮一起搬进了标题栏 —— 沉浸光感只在
 * Navigation 标题栏 / 底部 TabBar 里生效（见 ui/Glass.ets 的开头说明），所以改这个值
 * 的人变成了壳层，本页只订阅它、变了就重新取数。
 */
export const K_RECOMMEND_SOURCE: string = 'recommend_source';

/**
 * 推荐页
 *
 * 对应上游的「歌单」页 + 「排行榜」页合起来的那块内容：
 *   顶部是来源（酷我 / 酷狗 / 咪咕 / QQ / 网易）与排序页签（最新 / 最热 / 推荐…），
 *   下面是该来源的在线榜单（横向卡片）和推荐歌单（列表）。
 *   点榜单卡片或歌单进「在线详情页」，在那里播放全部或挑某一首。
 *
 * 数据全部来自宿主内置的平台接口（core/music/MusicList.ets），不依赖导入的音源；
 * 音源只决定「这些歌能不能解析出播放链接」。
 */
@Component
export struct RecommendView {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  onOpenSearch: () => void = () => {
  };
  onOpenOnline: (route: OnlineRoute) => void = () => {
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
  /** 当前推荐来源，切走再回来保持上次选的平台（改值的是标题栏里那颗来源胶囊） */
  @StorageLink(K_RECOMMEND_SOURCE) @Watch('onPlatformChanged') platform: string = 'kw';
  /** 首页是否挂 HDS 背景流光（外观设置里可关，关掉就不挂这一层） */
  @StorageLink(K_FLOW_LIGHT) flowLight: boolean = true;
  /** 玻璃厚度档位（外观设置）：两个下拉框的玻璃跟着它变 */
  @StorageLink(K_MATERIAL_LEVEL) materialLevel: number = 0;
  @State sorts: LxSortItem[] = sortListOf('kw');
  @State sortIndex: number = 0;
  @State boards: LxBoardItem[] = [];
  /** 榜单网格的实测宽度（vp）：用来算一行放几个小卡，宽屏自动多排一列 */
  @State boardAreaWidth: number = 0;
  @State playlists: LxPlaylistItem[] = [];
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State error: string = '';
  @State page: number = 0;
  /** 某一页返回空 = 已经到底，别再用 onReachEnd 反复拉 */
  @State noMore: boolean = false;
  private playlistSource: PlaylistSource = new PlaylistSource();

  aboutToAppear(): void {
    this.sorts = sortListOf(this.platform);
    this.sortIndex = 0;
    if (this.playlists.length === 0) {
      void this.reload();
    }
  }

  private currentSortId(): string {
    if (this.sortIndex >= 0 && this.sortIndex < this.sorts.length) {
      return this.sorts[this.sortIndex].id;
    }
    return '';
  }

  /** 当前排序的名字（下拉框上显示的就是它） */
  private currentSortName(): string {
    if (this.sortIndex >= 0 && this.sortIndex < this.sorts.length) {
      return this.sorts[this.sortIndex].name;
    }
    return '';
  }

  /** 拉第一页（换来源、换排序、下拉刷新都走它） */
  private async reload(): Promise<void> {
    this.error = '';
    if (this.playlists.length === 0) {
      this.loading = true;
    }
    this.boards = getBoards(this.platform);
    try {
      const list: LxPlaylistItem[] =
        await getRecommendPlaylists(this.platform, this.currentSortId(), 1);
      this.playlists = list;
      this.playlistSource.setItems(this.playlists);
      this.page = 1;
      this.noMore = list.length === 0;
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  /** 上拉加载下一页 */
  private async loadMore(): Promise<void> {
    if (this.loading || this.loadingMore || this.noMore || this.error.length > 0) {
      return;
    }
    this.loadingMore = true;
    try {
      const list: LxPlaylistItem[] =
        await getRecommendPlaylists(this.platform, this.currentSortId(), this.page + 1);
      if (list.length === 0) {
        this.noMore = true;
        return;
      }
      this.playlists = this.playlists.concat(list);
      this.playlistSource.setItems(this.playlists);
      this.page = this.page + 1;
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.loadingMore = false;
    }
  }

  /**
   * 推荐来源变了（页内顶部 TX / KW / KG / MG / WY 五个按钮改的就是这个值）
   *
   * 按钮只负责写值，重置与重拉统一收在这里：不管是点按钮，还是外部改 AppStorage，
   * 甚至首次进入，都走同一套，不会出现两处逻辑各写一半。
   */
  private onPlatformChanged(): void {
    if (!LIST_PLATFORMS.includes(this.platform)) {
      return;
    }
    this.sorts = sortListOf(this.platform);
    this.sortIndex = 0;
    this.playlists = [];
    this.playlistSource.setItems(this.playlists);
    this.page = 0;
    this.noMore = false;
    void this.reload();
  }

  /** 点顶部平台按钮：写回共享的来源值，@Watch 会接着重拉第一页 */
  private switchPlatform(source: string): void {
    if (this.platform === source) {
      return;
    }
    this.platform = source;
  }

  private switchSort(index: number): void {
    if (index === this.sortIndex) {
      return;
    }
    this.sortIndex = index;
    this.playlists = [];
    this.playlistSource.setItems(this.playlists);
    this.page = 0;
    void this.reload();
  }

  /**
   * 榜单小卡每行几个：按可用宽度算（一张卡不小于 BOARD_MIN_WIDTH），至少 4 个，
   * 手机上一行 4 个、车机 / 平板更宽会自然变多；榜单多就自动换行全部铺开，不再横滑
   */
  private boardColumnCount(): number {
    if (this.boardAreaWidth <= 0) {
      return 4;
    }
    const count: number = Math.floor((this.boardAreaWidth + BOARD_GAP) / (BOARD_MIN_WIDTH + BOARD_GAP));
    return Math.max(4, count);
  }

  private boardColumnsTemplate(): string {
    let tpl: string = '';
    const cols: number = this.boardColumnCount();
    for (let i = 0; i < cols; i++) {
      tpl = tpl.length === 0 ? '1fr' : `${tpl} 1fr`;
    }
    return tpl;
  }

  private boardRows(): number {
    const cols: number = this.boardColumnCount();
    return Math.max(1, Math.ceil(this.boards.length / cols));
  }

  private boardRowsTemplate(): string {
    let tpl: string = '';
    const rows: number = this.boardRows();
    for (let i = 0; i < rows; i++) {
      tpl = tpl.length === 0 ? '1fr' : `${tpl} 1fr`;
    }
    return tpl;
  }

  private boardGridHeight(): number {
    const rows: number = this.boardRows();
    return rows * BOARD_CARD_HEIGHT + (rows - 1) * BOARD_GAP;
  }

  private openBoard(board: LxBoardItem): void {
    const route: OnlineRoute = {
      kind: 'board',
      source: board.source,
      id: board.bangid,
      name: board.name,
      cover: '',
    };
    this.onOpenOnline(route);
  }

  private openPlaylist(item: LxPlaylistItem): void {
    const route: OnlineRoute = {
      kind: 'playlist',
      source: item.source,
      id: item.id,
      name: item.name,
      cover: item.img,
    };
    this.onOpenOnline(route);
  }

  /** 歌单行第二行的说明：作者 · 播放量 · 曲目数（有谁显示谁） */
  private playlistMeta(item: LxPlaylistItem): string {
    const parts: string[] = [];
    if (item.author.length > 0) {
      parts.push(item.author);
    }
    if (item.playCount.length > 0) {
      parts.push(item.playCount);
    }
    if (item.total > 0) {
      parts.push(`${item.total} 首`);
    }
    return parts.join(' · ');
  }

  // ------------------------------------------------------------ 构建

  /**
   * 顶部平台按钮：TX / KW / KG / MG / WY 一排，等分宽度
   *
   * 对应各平台自己的网页歌单页，点哪个就按那个平台的口径重拉推荐；跟「隔壁多媒体」
   * 音乐页同一套用法。它固定在标题栏下方、不随内容滚走 —— 换平台是这一页最常用
   * 的动作，滚到一半想换平台不用先滚回顶部；顶部让出状态栏 + 标题栏（topInset）。
   */
  @Builder
  platformTabs() {
    Row({ space: 4 }) {
      ForEach(R_TAB_SOURCES, (source: string, index: number) => {
        Text(R_TAB_LABELS[index])
          .fontSize(13.5)
          .fontWeight(this.platform === source ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.platform === source ? C_ON_ACCENT : C_TEXT_SUB)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.platform === source ? C_RED : Color.Transparent)
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            this.switchPlatform(source);
          })
          .accessibilityText(`切换到${platformName(source)}`)
          .accessibilityLevel('yes')
      }, (source: string) => source)
    }
    .width('100%')
    .padding(3)
    .borderRadius(19)
    .backgroundColor(C_SEG_BG)
    .margin({ left: 16, right: 16, top: this.topInset + 6, bottom: 8 })
  }

  @Builder
  sortMenu() {
    Menu() {
      ForEach(this.sorts, (item: LxSortItem, index: number) => {
        MenuItem({ content: item.name })
          .onClick(() => {
            this.switchSort(index);
          })
      }, (item: LxSortItem, index: number) => `${index}_${item.id}`)
    }
  }

  @Builder
  playlistRow(item: LxPlaylistItem) {
    Row({ space: 12 }) {
      CoverArt({
        url: item.img,
        name: item.name,
        art: item.img.length === 0,
        boxSize: 58,
        radius: 14,
      })

      Column({ space: 5 }) {
        Text(item.name)
          .fontSize(F_ITEM)
          .fontColor(C_TEXT)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
        if (this.playlistMeta(item).length > 0) {
          Text(this.playlistMeta(item))
            .fontSize(F_SUB)
            // 作者 / 播放量这一行要用深一点的灰：底色本来就是浅灰，
            // 原来那档（C_TEXT_WEAK）压在上面几乎看不见
            .fontColor(C_TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      IconGlyph({ symbol: I_CHEVRON_RIGHT, iconSize: 17, color: C_CHEVRON })
    }
    .width('100%')
    .height(78)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.openPlaylist(item);
    })
  }

  @Builder
  statusBlock() {
    Column({ space: 10 }) {
      if (this.loading) {
        Text(`正在加载${platformName(this.platform)}的推荐…`)
          .fontSize(14.5)
          .fontColor(C_TEXT_SUB)
      } else if (this.error.length > 0) {
        Text(this.error)
          .fontSize(13.5)
          .fontColor(C_TEXT_SUB)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .padding({ left: 26, right: 26 })
        Text('点击重试')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_RED)
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(C_RED_TINT)
          .onClick(() => {
            void this.reload();
          })
      } else {
        Text('这个来源暂时没有推荐内容')
          .fontSize(14.5)
          .fontColor(C_TEXT_SUB)
      }
    }
    .width('100%')
    .padding({ left: 32, right: 32, top: 40, bottom: 30 })
  }

  build() {
    /**
     * 首页底色之上、内容之下铺一层 HDS 背景流光（着色器，10 秒一圈无限循环）。
     *
     * 底色必须留在这层 Stack 上：如果把不透明底色写在内容那一层，流光会被整片盖住，
     * 看上去就是「加了没效果」——这一点是这套光效唯一容易踩的坑。
     * 流光层本身铺满、不拦触摸，不影响原有布局与交互。
     */
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.flowLight) {
        HdsFlowLightBackground()
      }

      Column() {
      // 页头（大标题 + 搜索钮）在壳层的 HdsNavigation 标题栏里，见 pages/Index.ets 的
      // homeHeader：沉浸光感只在标题栏 / 底部 TabBar 里生效，留在内容区的话
      // systemMaterial 会被系统判定为 out of scope。本页只留平台按钮这一排在最上面，
      // 顶部让出 topInset（壳层传的是「状态栏 + 标题栏」那一段高度）。
      this.platformTabs()

      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 0 }) {
          if (this.boards.length > 0) {
            // -------------------------------------------- 在线榜单
            ListItem() {
              Row({ space: 8 }) {
                SectionTitle({ text: '在线榜单' })
                Text(platformName(this.platform))
                  .fontSize(12)
                  .fontColor(C_RED)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .borderRadius(9)
                  .backgroundColor(C_RED_TINT)
                Blank()
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 12 })
            }

            ListItem() {
              // 榜单卡改成 64vp 小方块、按列铺满：手机上每行 4 个（车机 / 平板更宽会更多），
              // 榜单有十几个就自动往下排满行，不再横向滑动——一眼全看完，比横滑大卡省事
              Grid() {
                ForEach(this.boards, (board: LxBoardItem, index: number) => {
                  GridItem() {
                    RankCard({
                      title: board.name,
                      platform: platformName(board.source),
                      colorA: boardColors(index)[0],
                      colorB: boardColors(index)[1],
                      onTap: () => {
                        this.openBoard(board);
                      },
                    })
                  }
                }, (board: LxBoardItem) => board.id)
              }
              .columnsTemplate(this.boardColumnsTemplate())
              .rowsTemplate(this.boardRowsTemplate())
              .columnsGap(BOARD_GAP)
              .rowsGap(BOARD_GAP)
              .width('100%')
              .height(this.boardGridHeight())
              .padding({ left: 16, right: 16 })
              .scrollBar(BarState.Off)
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                // 扣掉左右各 16 的内边距，得到真正能铺卡片的宽度
                const width: number = (newArea.width as number) - 32;
                if (width > 0 && Math.abs(width - this.boardAreaWidth) > 1) {
                  this.boardAreaWidth = width;
                }
              })
            }
          }

          // -------------------------------------------- 推荐歌单
          ListItem() {
            Row({ space: 8 }) {
              SectionTitle({ text: '推荐歌单' })
              Blank()
              if (this.loadingMore) {
                Text('加载中…')
                  .fontSize(12)
                  .fontColor(C_TEXT_WEAK)
              }
              /**
               * 排序（推荐 / 最热 / 最新 / 收藏 / 攀升…）
               *
               * 原来是标题下面另一排横滑胶囊，现在并到这一栏、靠右做成下拉框：
               * 它管的就是这一栏的内容，和标题挨在一起比单独占一行更好理解。
               * 各平台给了几个就用几个，只有一个时不显示（没什么可选的）。
               */
              if (this.sorts.length > 1) {
                Row({ space: 3 }) {
                  Text(this.currentSortName())
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(C_RED)
                    .maxLines(1)
                  IconGlyph({ symbol: I_CHEVRON_DOWN, iconSize: 13, color: C_RED })
                }
                .height(30)
                .padding({ left: 12, right: 8 })
                .attributeModifier(thinGlass(15, false, '', this.materialLevel))
                .systemMaterial(immersiveMaterialFor(this.materialLevel))
                .bindMenu(this.sortMenu())
                .accessibilityText(`排序：${this.currentSortName()}，点按切换`)
                .accessibilityLevel('yes')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: this.boards.length > 0 ? 22 : 4, bottom: 10 })
          }

          if (this.playlists.length === 0) {
            ListItem() {
              this.statusBlock()
            }
          } else {
            LazyForEach(this.playlistSource, (item: LxPlaylistItem) => {
              ListItem() {
                // 行与行之间不画分隔线：封面 + 两行字自己就能分开，多一条浅色横线
                // 在浅灰底上反而像一条白缝
                this.playlistRow((item === undefined || item === null) ? EMPTY_PLAYLIST_ITEM : item)
              }
            }, (item: LxPlaylistItem) => {
              // key 生成器同样可能收到已失效的 item，落到哨兵上防 undefined 访问
              const safe: LxPlaylistItem = (item === undefined || item === null) ? EMPTY_PLAYLIST_ITEM : item;
              return `${safe.id}_${safe.name}`;
            })

            if (this.error.length > 0) {
              ListItem() {
                Column({ space: 8 }) {
                  Text(this.error)
                    .fontSize(13)
                    .fontColor(C_TEXT_WEAK)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('点击重试')
                    .fontSize(13.5)
                    .fontColor(C_RED)
                    .onClick(() => {
                      this.error = '';
                      void this.loadMore();
                    })
                }
                .width('100%')
                .padding({ top: 14, bottom: 14 })
              }
            } else {
              ListItem() {
                Text(this.loadingMore ? '正在加载更多…' : (this.noMore ? '没有更多了' : '上拉加载更多'))
                  .fontSize(13)
                  .fontColor(C_TEXT_WEAK)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 16, bottom: 16 })
              }
            }
          }

          ListItem() {
            Column().height(this.bottomInset + 12).width('100%')
          }
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        /**
         * 起始偏移：列表第一行落在透明标题栏下方，但**内容可以滚进这段区域**
         *
         * 之前这里是给外层容器加 `padding({ top })`，那会让列表的可视区从标题栏下面
         * 才开始，卡片滑到标题栏下边缘就被整块裁掉（看着像"被顶栏挡住"）。
         * 换成 List 自己的 contentStartOffset 之后，偏移只是"内容起点"，滚动时列表项
         * 能正常进入到标题栏底下、透过透明标题栏显示出来。
         */
        .contentStartOffset(6)
        .onScroll((_xOffset: number, yOffset: number) => {
          this.handleFoldScroll(yOffset);
        })
        .onReachEnd(() => {
          void this.loadMore();
        })
      }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(() => {
          void this.reload();
        })
      }
      .width('100%')
      .height('100%')

      /**
       * 顶栏渐隐：内容从透明的标题栏底下穿过时，靠近顶部的位置淡出到看不见，
       * 标题那两个字才不会被列表文字顶穿。压在内容之上、标题栏之下。
       */
      TopFade({ fadeHeight: this.topInset + 10 })
    }
    .width('100%')
    .height('100%')
    // 底色挂在外层 Stack（流光层之上、内容之下），别挪回内容那一层
    .backgroundColor(C_BG)
  }
}
