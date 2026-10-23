import { K_LIBRARY_VERSION, PlaySession, PlaylistSummary, SongItem } from '../core/player/PlaySession';
import { K_SYNC_DATA_VERSION, SyncManager } from '../core/sync/SyncManager';
import { CollectedPlaylist, CollectedPlaylists, K_COLLECTED_VERSION, collectedKeyOf } from '../core/sync/CollectedPlaylists';
import { OnlineRoute, platformName } from '../core/music/MusicList';
import { LOVE_LIST_NAME } from '../core/sync/SyncTypes';
import { C_BG, C_CARD, C_CHEVRON, C_DIVIDER, C_FILL_SOFT, C_PRESSED, C_RED, C_RED_TINT, C_TEXT,
  C_TEXT_SUB, C_TEXT_WEAK, F_ITEM, F_SECTION, F_SUB, R_CARD } from '../ui/Theme';
import { I_CHEVRON_RIGHT, I_HEART_FILLED, I_IMPORT, I_PLAYLIST, I_PLUS, IconGlyph } from '../ui/Icons';
import { CoverArt, TopFade } from '../ui/Widgets';
import { dustBus, DustPoint, dustPointOf } from '../ui/Dust';
import { ImportPlaylistSheet } from './ImportPlaylistSheet';

/** 底部栏收展阈值：与 MineView / RecommendView 保持一致（vp） */
const FOLD_THRESHOLD: number = 24;

/**
 * 歌单页（原「听书」页签改造成）
 *
 * 内容从「我的」页的「自检歌单」一段整体搬过来：自建歌单（新建 / 重命名 / 删除 /
 * 长按添加到收藏）+ 收藏歌单（收来的在线歌单）+ 歌单导入。原来的「我的」页只保留
 * 快捷入口与设置入口，歌单这一段独立成页签，与推荐 / 我的 并列。
 */
@Component
export struct SongListView {
  /** 内容起始偏移：让出透明标题栏那一段（状态栏 + 标题栏，由壳层算好） */
  @Prop topInset: number = 0;
  /** 内容底部要留出的空间：悬浮页签栏 + 手势条（由壳层算好） */
  @Prop bottomInset: number = 0;
  /** 点歌单 → 打开歌单详情（与壳层那套路由同一个入口） */
  onOpenPlaylist: (playlist: PlaylistSummary) => void = () => {
  };
  /** 收藏歌单那一段点开的还是**在线**歌单，路由也交给壳层（在线详情页） */
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
  @State playlists: PlaylistSummary[] = [];
  /** 歌单卡当前那一段：0 = 自建歌单（自己建的 + 导入的），1 = 收藏歌单（收来的在线歌单） */
  @State playlistTab: number = 0;
  /** 收藏的在线歌单（按收藏顺序，最近的在前） */
  @State collected: CollectedPlaylist[] = [];
  /** 新建 / 重命名共用的小面板：editingId 为空表示新建 */
  @State editOpen: boolean = false;
  @State editingId: string = '';
  @State editName: string = '';
  /** 「导入歌单」面板（粘贴第三方歌单分享链接） */
  @State importOpen: boolean = false;
  /** 最近一次触摸点：删除歌单时在这里撒一把粒子（普通字段，不引起重绘） */
  private dustX: number = 0;
  private dustY: number = 0;
  /** 歌单 / 收藏歌单在别处被改了（同步库 / 推荐页爱心 / 多选）时重读 */
  @StorageLink(K_LIBRARY_VERSION) @Watch('refresh') libraryVersion: number = 0;
  @StorageLink(K_SYNC_DATA_VERSION) @Watch('refresh') syncVersion: number = 0;
  @StorageLink(K_COLLECTED_VERSION) @Watch('refresh') collectedVersion: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    const library = SyncManager.getInstance().getLibrary();
    this.playlists = library.playlistSummaries();
    this.collected = CollectedPlaylists.getInstance().list();
  }

  // ------------------------------------------------------------ 歌单：新建 / 重命名 / 删除

  private openCreate(): void {
    this.editingId = '';
    this.editName = '';
    this.editOpen = true;
  }

  private openRename(item: PlaylistSummary): void {
    this.editingId = item.id;
    this.editName = item.name;
    this.editOpen = true;
  }

  private submitEdit(): void {
    const name: string = this.editName.trim();
    if (name.length === 0) {
      return;
    }
    const library = SyncManager.getInstance().getLibrary();
    if (this.editingId.length === 0) {
      library.createPlaylist(name);
    } else {
      library.renamePlaylist(this.editingId, name);
    }
    this.editOpen = false;
    this.refresh();
  }

  private removePlaylist(item: PlaylistSummary): void {
    this.getUIContext().showAlertDialog({
      title: '删除歌单',
      message: `确定要删除「${item.name}」吗？删除会同步到其它设备。`,
      autoCancel: true,
      buttons: [
        { value: '取消', action: () => { } },
        {
          value: '删除',
          fontColor: C_RED,
          action: () => {
            SyncManager.getInstance().getLibrary().removePlaylists([item.id]);
            // 删除给一点粒子飘散（在触摸点撒，不在支持的系统上自动不做）
            dustBus.spray(this.dustX, this.dustY);
            this.refresh();
          },
        },
      ],
    });
  }

  /** 把整张歌单的歌批量加进收藏（收藏是参与同步的数据，只上行一次） */
  private addPlaylistToFavorites(item: PlaylistSummary): void {
    const songs: SongItem[] = SyncManager.getInstance().getLibrary().playlistSongs(item.id);
    if (songs.length === 0) {
      this.toast(`「${item.name}」还没有歌曲`);
      return;
    }
    const added: number = PlaySession.getInstance().addFavorites(songs);
    this.toast(added > 0
      ? `已把「${item.name}」的 ${added} 首歌添加到${LOVE_LIST_NAME}`
      : `「${item.name}」里的歌都已经在${LOVE_LIST_NAME}里了`);
  }

  // ------------------------------------------------------------ 收藏歌单（收来的在线歌单）

  /** 收藏段里的一行点开：走在线详情页（收藏只是记一下，不把它拉成本地歌单） */
  private openCollected(entry: CollectedPlaylist): void {
    const route: OnlineRoute = {
      kind: 'playlist',
      source: entry.source,
      id: entry.id,
      name: entry.name,
      cover: entry.cover,
    };
    this.onOpenOnline(route);
  }

  /** 收藏段那一行的第二行说明：先标平台（收来的歌单可能不在当前推荐来源上），再接收藏时那份说明 */
  private collectedMeta(entry: CollectedPlaylist): string {
    const platform: string = platformName(entry.source);
    return entry.meta.length > 0 ? `${platform} · ${entry.meta}` : platform;
  }

  /** 取消收藏一张（只去掉收藏这一位，什么都不动） */
  private uncollect(entry: CollectedPlaylist): void {
    CollectedPlaylists.getInstance().remove(entry.source, entry.id);
    this.refresh();
    this.toast(`已取消收藏「${entry.name}」`);
  }

  /** 记住这次触摸的位置：删除歌单时拿它当粒子飘散的起点 */
  private rememberTouch(event: TouchEvent): void {
    const point: DustPoint | null = dustPointOf(event);
    if (point !== null) {
      this.dustX = point.x;
      this.dustY = point.y;
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ------------------------------------------------------------ 界面

  /** 歌单卡里那块浅灰底的「动作区」（照华为音乐：新建歌单 / 歌单导入 并排） */
  @Builder
  cardAction(index: number) {
    Column({ space: 6 }) {
      IconGlyph({ symbol: index === 0 ? I_PLUS : I_IMPORT, iconSize: 23, color: C_TEXT })
      Text(index === 0 ? '新建歌单' : '歌单导入')
        .fontSize(F_SUB + 0.5)
        .fontColor(C_TEXT)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .stateStyles({
      normal: { .backgroundColor(Color.Transparent) },
      pressed: { .backgroundColor(C_PRESSED) },
    })
    .onClick(() => {
      if (index === 0) {
        this.openCreate();
      } else {
        this.importOpen = true;
      }
    })
    .accessibilityText(index === 0 ? '新建歌单' : '导入歌单')
    .accessibilityLevel('yes')
  }

  /** 歌单行：图形占位封面 + 名字 + 曲目数 + 右箭头（长按是重命名 / 删除那套菜单） */
  @Builder
  playlistRow(item: PlaylistSummary, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.6)
          .color(C_DIVIDER)
          .margin({ left: 72 })
      }

      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(46)
            .height(46)
            .borderRadius(14)
            .backgroundColor(C_RED_TINT)
          IconGlyph({ symbol: I_PLAYLIST, iconSize: 22, color: C_RED })
        }
        .width(46)
        .height(46)

        Column({ space: 4 }) {
          Text(item.name)
            .fontSize(F_ITEM)
            .fontColor(C_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
          Text(`${item.count} 首`)
            .fontSize(F_SUB)
            .fontColor(C_TEXT_WEAK)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        IconGlyph({ symbol: I_CHEVRON_RIGHT, iconSize: 18, color: C_CHEVRON })
          .accessibilityLevel('no')
      }
      .width('100%')
      .height(70)
      .padding({ left: 14, right: 14 })
      .onClick(() => {
        this.onOpenPlaylist(item);
      })
      .onTouch((event: TouchEvent) => {
        this.rememberTouch(event);
      })
      .bindContextMenu(this.rowMenu(item), ResponseType.LongPress)
    }
    .width('100%')
  }

  @Builder
  rowMenu(item: PlaylistSummary) {
    Menu() {
      MenuItem({ content: '添加到收藏' })
        .onClick(() => {
          this.addPlaylistToFavorites(item);
        })
      MenuItem({ content: '重命名' })
        .onClick(() => {
          this.openRename(item);
        })
      MenuItem({ content: '删除' })
        .onClick(() => {
          this.removePlaylist(item);
        })
    }
  }

  /** 收藏歌单那一段的行：在线封面 + 名字 + 平台·说明 + 右箭头（长按可取消收藏） */
  @Builder
  collectedRow(entry: CollectedPlaylist, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.6)
          .color(C_DIVIDER)
          .margin({ left: 72 })
      }

      Row({ space: 12 }) {
        CoverArt({
          url: entry.cover,
          name: entry.name,
          art: entry.cover.length === 0,
          boxSize: 46,
          radius: 14,
        })

        Column({ space: 4 }) {
          Text(entry.name)
            .fontSize(F_ITEM)
            .fontColor(C_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
          Text(this.collectedMeta(entry))
            .fontSize(F_SUB)
            .fontColor(C_TEXT_WEAK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        IconGlyph({ symbol: I_CHEVRON_RIGHT, iconSize: 18, color: C_CHEVRON })
          .accessibilityLevel('no')
      }
      .width('100%')
      .height(70)
      .padding({ left: 14, right: 14 })
      .onClick(() => {
        this.openCollected(entry);
      })
      .bindContextMenu(this.collectedMenu(entry), ResponseType.LongPress)
    }
    .width('100%')
  }

  /** 收藏歌单那一段的行菜单：只有「取消收藏歌单」（那只记着平台 + 歌单 id，别的不动） */
  @Builder
  collectedMenu(entry: CollectedPlaylist) {
    Menu() {
      MenuItem({ content: '取消收藏歌单' })
        .onClick(() => {
          this.uncollect(entry);
        })
    }
  }

  /** 歌单卡：自建歌单 | 收藏歌单 两段 */
  @Builder
  playlistCard() {
    Column() {
      Row({ space: 6 }) {
        Text('自建歌单')
          .fontSize(F_SECTION)
          .fontWeight(this.playlistTab === 0 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.playlistTab === 0 ? C_TEXT : C_TEXT_SUB)
          .onClick(() => {
            this.playlistTab = 0;
          })
        Text(`${this.playlists.length}`)
          .fontSize(F_SUB)
          .fontColor(C_TEXT_WEAK)
        Text('|')
          .fontSize(F_SECTION)
          .fontColor(C_DIVIDER)
          .padding({ left: 2, right: 2 })
        Text('收藏歌单')
          .fontSize(F_SECTION)
          .fontWeight(this.playlistTab === 1 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.playlistTab === 1 ? C_TEXT : C_TEXT_SUB)
          .onClick(() => {
            this.playlistTab = 1;
          })
        Text(`${this.collected.length}`)
          .fontSize(F_SUB)
          .fontColor(C_TEXT_WEAK)
        Blank()
      }
      .width('100%')
      .height(54)
      .padding({ left: 14, right: 14 })

      if (this.playlistTab === 1) {
        if (this.collected.length === 0) {
          Column({ space: 6 }) {
            IconGlyph({ symbol: I_HEART_FILLED, iconSize: 28, color: C_TEXT_WEAK })
              .accessibilityLevel('no')
            Text('还没有收藏的歌单')
              .fontSize(F_SUB)
              .fontColor(C_TEXT_SUB)
            Text('在推荐页点开一张歌单，点里面的「收藏歌单」就会收进来')
              .fontSize(11.5)
              .fontColor(C_TEXT_WEAK)
          }
          .width('100%')
          .padding({ top: 16, bottom: 28 })
          .alignItems(HorizontalAlign.Center)
        } else {
          ForEach(this.collected, (entry: CollectedPlaylist, index: number) => {
            this.collectedRow(entry, index > 0)
          }, (entry: CollectedPlaylist) => collectedKeyOf(entry.source, entry.id))
        }
      } else {
        Column() {
          Row() {
            this.cardAction(0)
            this.cardAction(1)
          }
          .width('100%')
          .height(64)
          .borderRadius(16)
          .backgroundColor(C_FILL_SOFT)
          .clip(true)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 10 })

        if (this.playlists.length === 0) {
          Text('还没有歌单，点上面的「新建歌单」建一个，或者用「歌单导入」粘贴一张分享链接')
            .fontSize(F_SUB)
            .fontColor(C_TEXT_WEAK)
            .width('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 18 })
            .textAlign(TextAlign.Start)
        } else {
          ForEach(this.playlists, (item: PlaylistSummary, index: number) => {
            this.playlistRow(item, index > 0)
          }, (item: PlaylistSummary) => `${item.id}_${item.count}_${item.name}`)
        }
      }
    }
    .width('100%')
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
    .clip(true)
  }

  @Builder
  editSheet() {
    Column({ space: 12 }) {
      Text(this.editingId.length === 0 ? '新建歌单' : '重命名歌单')
        .fontSize(F_ITEM)
        .fontWeight(FontWeight.Medium)
        .fontColor(C_TEXT)
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({ text: this.editName, placeholder: '歌单名称' })
        .placeholderColor(C_TEXT_WEAK)
        .placeholderFont({ size: 14 })
        .fontSize(14)
        .height(46)
        .backgroundColor(C_FILL_SOFT)
        .onChange((value: string) => {
          this.editName = value;
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(C_FILL_SOFT)
          .fontColor(C_TEXT)
          .onClick(() => {
            this.editOpen = false;
          })
        Button('确定')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(C_RED)
          .onClick(() => {
            this.submitEdit();
          })
      }
      .width('100%')

      Column().height(this.bottomInset + 8).width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder
  importSheet() {
    ImportPlaylistSheet({
      bottomInset: this.bottomInset,
      onDone: (message: string) => {
        this.importOpen = false;
        this.toast(message);
      },
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll() {
          Column({ space: 14 }) {
            Column().height(this.topInset + 6).width('100%')
            this.playlistCard()
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
      .bindSheet($$this.editOpen, this.editSheet(), {
        preferType: SheetType.BOTTOM,
        detents: [SheetSize.MEDIUM],
        detentSelection: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        title: { title: this.editingId.length === 0 ? '新建歌单' : '重命名' },
      })

      TopFade({ fadeHeight: this.topInset + 10 })

      Column()
        .width(1)
        .height(1)
        .bindSheet($$this.importOpen, this.importSheet(), {
          preferType: SheetType.BOTTOM,
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          detentSelection: SheetSize.LARGE,
          dragBar: true,
          showClose: true,
          title: { title: '导入歌单' },
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_BG)
  }
}
