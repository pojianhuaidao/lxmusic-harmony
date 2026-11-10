import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SourceEngine } from '../core/source/SourceEngine';
import { MAX_SCRIPT_SIZE } from '../core/source/LxMetadata';
import { SourceInfo } from '../core/source/LxTypes';
import { HdsListItemCard, IconSize, PrefixIcon, SuffixArrow, SuffixText } from '@kit.UIDesignKit';
import { I_DISC, I_IMPORT, IconGlyph } from '../ui/Icons';
import { SEARCH_PLATFORMS, isSearchSupported } from '../core/music/MusicSearch';
import { C_BG, C_CARD, C_CHEVRON, C_DIVIDER, C_FILL_SOFT, C_FILL_SOFT_STRONG, C_RED, C_RED_TINT, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK, F_SECTION, F_SUB, R_CARD } from '../ui/Theme';
import { HintText } from '../ui/SettingWidgets';

const DOMAIN: number = 0x0001;
const TAG: string = 'SourceSettingsView';

const PLATFORM_NAMES: Record<string, string> = {
  'kw': '酷我',
  'kg': '酷狗',
  'mg': '咪咕',
  'tx': 'QQ',
  'wy': '网易',
  'xm': '喜马拉雅',
};

/**
 * 音源设置
 *
 * 上游的「设置 - 音源设置」就是这一页：导入音源、启用/删除已导入的音源、
 * 导入 -> 加载 -> 查看已导入音源。（沙箱环境切换、离线自检、引擎日志三块调试信息已移除）
 *
 * 导入有两条入口：粘贴链接/正文（在线拉取），或从文件导入本地脚本（见 pickSourceFile）。
 */
@Component
export struct SourceSettingsView {
  /** 平铺模式：由「我的」页把这一页的设置直接展开，不要自成滚动页 */
  @Prop embedded: boolean = false;
  /** 内容让出标题栏那一段（壳层传来的「状态栏 + 标题栏」）：见滚动内容里的顶部占位 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  onBack: () => void = () => {
  };
  @State sourceInput: string = '';
  @State status: string = '等待操作';
  @State busy: boolean = false;
  @State sources: SourceInfo[] = [];
  @State loadedId: string = '';

  aboutToAppear(): void {
    this.refreshSources();
  }

  private getContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private refreshSources(): void {
    const engine = SourceEngine.getInstance();
    this.sources = engine.listSources();
    this.loadedId = engine.getLoadedSourceId();
  }

  private platformName(id: string): string {
    const name: string = PLATFORM_NAMES[id];
    return name !== undefined ? name : id;
  }

  /** 脚本头里的 @version 常常自带 v（v1.2.1），别再补一个变成 vv1.2.1 */
  private versionText(version: string): string {
    if (version.length === 0) {
      return '未知版本';
    }
    return version.charAt(0).toLowerCase() === 'v' ? version : `v${version}`;
  }

  private async importAndLoad(): Promise<void> {
    if (this.busy) {
      return;
    }
    const input: string = this.sourceInput.trim();
    if (input.length === 0) {
      this.status = '请先粘贴音源脚本链接（或脚本正文）';
      return;
    }
    const engine = SourceEngine.getInstance();
    this.busy = true;
    this.status = '导入中…';
    try {
      let info: SourceInfo;
      if (/^https?:\/\//.test(input)) {
        info = await engine.importFromUrl(input);
      } else {
        info = engine.importSource(input);
      }
      this.status = `已导入「${info.name}」，正在初始化沙箱…`;
      this.refreshSources();
      await this.loadSource(info.id);
    } catch (e) {
      this.status = `导入失败: ${(e as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  private async loadSource(id: string): Promise<void> {
    const engine = SourceEngine.getInstance();
    this.busy = true;
    this.status = '正在加载音源…';
    try {
      await engine.loadSource(id);
      this.refreshSources();
      this.loadedId = id;
      const playable: string[] = [];
      for (const platform of Object.keys(engine.getSupportedSources())) {
        if (isSearchSupported(platform)) {
          playable.push(this.platformName(platform));
        }
      }
      this.status = playable.length > 0
        ? `音源已就绪，可播放平台：${playable.join(' / ')}`
        : `音源已加载，但它声明的平台都不在可播放范围内（可播放：${SEARCH_PLATFORMS.map(
          (p: string) => this.platformName(p)).join('/')}）`;
    } catch (e) {
      this.status = `加载失败: ${(e as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  private removeSource(id: string): void {
    const engine = SourceEngine.getInstance();
    this.sources = engine.removeSource(id);
    this.status = '已删除该音源';
    this.refreshSources();
  }

  /** 图标 + 文字平铺的卡片标题行（与「播放设置」等设置页统一观感） */
  @Builder
  cardTitle(icon: Resource, title: string, trailing: string) {
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
          .fontColor(C_TEXT_WEAK)
      }
    }
    .width('100%')
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
    Column({ space: 16 }) {
      // 顶部占位：第一行落在透明标题栏下方，但它跟着内容一起滚走 —— 用容器内边距会把
      // 这一段内容裁在标题栏下边缘，看起来就"像被顶栏挡住"（首页就是这么做的）
      Column().height(this.embedded ? 0 : this.topInset + 6).width('100%')
      Text(this.status)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 4 })

      // ------------------------------------------------ 导入音源
      Column({ space: 10 }) {
        this.cardTitle(I_IMPORT, '导入音源', '')
        TextArea({
          text: this.sourceInput,
          placeholder: '粘贴音源脚本链接，例如 https://example.com/lx-source.js',
        })
          .height(72)
          .width('100%')
          .fontSize(12.5)
          .backgroundColor(C_FILL_SOFT)
          .borderRadius(10)
          .onChange((value: string) => {
            this.sourceInput = value;
          })
        Row({ space: 10 }) {
          Button(this.busy ? '处理中…' : '导入并加载')
            .fontSize(14)
            .height(40)
            .layoutWeight(1)
            .backgroundColor(C_RED)
            .enabled(!this.busy)
            .onClick(() => {
              this.importAndLoad();
            })
          Button('导入音源文件')
            .fontSize(14)
            .height(40)
            .layoutWeight(1)
            .backgroundColor(C_FILL_SOFT_STRONG)
            .fontColor(C_TEXT)
            .enabled(!this.busy)
            .onClick(() => {
              this.pickSourceFile();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(R_CARD)
      .backgroundColor(C_CARD)
      HintText({ text: '粘贴音源脚本链接（在线拉取）或脚本正文，也可从本地文件导入；导入成功后自动加载。' })

      // ------------------------------------------------ 已导入音源
      Column({ space: 10 }) {
        this.cardTitle(I_DISC, '已导入音源', this.sources.length > 0 ? `${this.sources.length} 个` : '')
        if (this.sources.length === 0) {
          Column() {
            Text('还没有导入任何音源')
              .fontSize(F_SUB)
              .fontColor(C_TEXT_WEAK)
          }
          .width('100%')
          .padding(14)
          .borderRadius(R_CARD)
          .backgroundColor(C_CARD)
        }
        ForEach(this.sources, (item: SourceInfo) => {
          Column({ space: 8 }) {
            // 一条音源就是一张 HDS 列表卡：官方符号图标 + 名称/版本，
            // 点卡片即加载；右侧「已就绪」用 HDS 的 SuffixText。
            // 白卡底由外层自绘容器给（HdsListItemCard 的 cardWidth/cardBackgroundColor
            // 会破坏它内部的宽度测量，导致整行文字消失，别用）。
            Column() {
              HdsListItemCard({
                prefixItem: new PrefixIcon({
                  iconSize: IconSize.SYSTEM_ICON,
                  iconValue: { symbol: I_DISC },
                }),
                textItem: {
                  primaryText: { text: item.name },
                  secondaryText: {
                    text: `${this.versionText(item.version)}　${item.author.length > 0 ? item.author : '未知作者'}`,
                  },
                },
                suffixItem: this.loadedId === item.id
                  ? new SuffixText({ text: '已就绪' })
                  : new SuffixArrow({ color: C_CHEVRON }),
                cardHeight: 68,
                onClick: () => {
                  this.loadSource(item.id);
                },
              })
            }
            .width('100%')
            .borderRadius(R_CARD)
            .backgroundColor(C_CARD)
            .clip(true)

            Row({ space: 10 }) {
              Button('加载')
                .fontSize(13)
                .height(34)
                .layoutWeight(1)
                .backgroundColor(C_FILL_SOFT_STRONG)
                .fontColor(C_TEXT)
                .onClick(() => {
                  this.loadSource(item.id);
                })
              Button('删除')
                .fontSize(13)
                .height(34)
                .layoutWeight(1)
                .backgroundColor(C_RED_TINT)
                .fontColor(C_RED)
                .onClick(() => {
                  this.removeSource(item.id);
                })
            }
            .width('100%')
          }
          .width('100%')
        }, (item: SourceInfo) => item.id)
      }
      .width('100%')

    }
    .width('100%')
    .padding({
      left: this.embedded ? 0 : 16,
      right: this.embedded ? 0 : 16,
      top: this.embedded ? 0 : 0,
      bottom: this.embedded ? 6 : this.bottomInset + 20,
    })
  }

  // ------------------------------------------------------------ 从文件导入

  /**
   * 从文件导入音源：拉起文件管理选一个脚本文件，读成文本后走和「粘贴正文」同一条路
   *
   * 选文件用 DocumentViewPicker（与「导入音乐」选音频文件是同一套做法）；后缀过滤给 .js，
   * 上游的源就是 js 脚本。用户在文件管理里取消不会进 then，这里也不报错 —— 取消不是失败。
   */
  private pickSourceFile(): void {
    if (this.busy) {
      return;
    }
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      // 一次可选多个音源脚本（上限 20 个）：逐个导入，单个失败跳过不影响其他文件
      options.maxSelectNumber = 20;
      options.fileSuffixFilters = ['音源脚本 (.js)|.js'];
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.getContext());
      documentPicker.select(options)
        .then((uris: string[]) => {
          if (uris.length === 0) {
            return;
          }
          void this.importSourceFiles(uris);
        })
        .catch((err: BusinessError) => {
          // 用户取消也走这里（错误码里带 cancel），不当成失败提示
          hilog.info(DOMAIN, TAG, 'pick source file ended: %{public}s', err.message);
        });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'open document picker failed: %{public}s', JSON.stringify(e));
      this.status = '打不开文件选择器，当前环境可能不支持选择文件';
    }
  }

  /**
   * 导入单个音源脚本文件
   *
   * 成功返回空串，失败返回失败原因（不抛错）—— 批量导入时单个失败直接跳过继续。
   * 注意 loadSource 内部会自己复位 busy，批量循环里由 importSourceFiles 每轮补回。
   */
  private async importSourceFile(uri: string): Promise<string> {
    const name: string = fileNameOf(uri);
    this.busy = true;
    this.status = `正在读取「${name}」…`;
    try {
      const text: string = readScriptFile(uri);
      if (text.trim().length === 0) {
        return `「${name}」是空文件，没有可导入的脚本`;
      }
      const info: SourceInfo = SourceEngine.getInstance().importSource(text);
      this.status = `已导入「${info.name}」，正在初始化沙箱…`;
      this.refreshSources();
      // 加载这一步自己管 busy 与状态文案，与「导入并加载」共用
      await this.loadSource(info.id);
      return '';
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'import source file failed (%{public}s): %{public}s', name, JSON.stringify(e));
      return `${(e as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  /**
   * 批量导入多个音源脚本（文件选择器多选结果）
   *
   * 逐个导入：单个失败跳过继续，全部结束后弹出导入结果汇总（成功 x 个 / 失败 y 个及原因）。
   */
  private async importSourceFiles(uris: string[]): Promise<void> {
    if (this.busy || uris.length === 0) {
      return;
    }
    this.busy = true;
    const okNames: string[] = [];
    const failLines: string[] = [];
    for (let i = 0; i < uris.length; i++) {
      const name: string = fileNameOf(uris[i]);
      this.status = `正在导入 ${i + 1}/${uris.length}「${name}」…`;
      const error: string = await this.importSourceFile(uris[i]);
      // loadSource 的 finally 会把 busy 复位：下一轮前补回，避免批量处理中途被打断
      this.busy = true;
      if (error.length === 0) {
        okNames.push(name);
      } else {
        failLines.push(`「${name}」：${error}`);
      }
    }
    this.busy = false;
    if (failLines.length > 0) {
      this.status = `导入完成：成功 ${okNames.length} 个，失败 ${failLines.length} 个`;
      this.getUIContext().showAlertDialog({
        title: '音源导入结果',
        message: `成功导入 ${okNames.length} 个音源，${failLines.length} 个失败。\n\n失败原因：\n${failLines.join('\n')}`,
        autoCancel: true,
        buttons: [
          { value: '知道了', action: () => { } },
        ],
      });
    } else {
      this.status = `已导入 ${okNames.length} 个音源，全部成功`;
    }
  }
}

/**
 * 读出用户选中的音源脚本
 *
 * picker 给的是文件管理那边的 uri（`file://docs/...`），用 fs.openSync 直接打开即可
 * （与「导入音乐」读音频文件是同一套做法），再按 UTF-8 解成文本。
 *
 * 大小上限跟引擎用同一个常量：引擎本来就以「源脚本过大」拒收超过 MAX_SCRIPT_SIZE 的正文，
 * 这里提前按文件大小拦下来，选错一个大文件时不会先把整个文件读进内存。
 */
function readScriptFile(uri: string): string {
  let file: fs.File | null = null;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const size: number = fs.statSync(file.fd).size;
    if (size <= 0) {
      return '';
    }
    if (size > MAX_SCRIPT_SIZE) {
      throw new Error(`文件太大（${Math.round(size / 1024)} KB），音源脚本不会这么大`);
    }
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    const read: number = fs.readSync(file.fd, buffer);
    const decoder = util.TextDecoder.create('utf-8');
    const text: string = decoder.decodeToString(new Uint8Array(buffer, 0, read));
    // 带 BOM 的脚本会把一个不可见字符顶在正文最前面，交给引擎前先摘掉
    return text.charCodeAt(0) === 0xFEFF ? text.substring(1) : text;
  } finally {
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'close source file failed: %{public}s', JSON.stringify(e));
      }
    }
  }
}

/** uri 上的文件名（只用于提示；取不到就显示整条 uri） */
function fileNameOf(uri: string): string {
  const cut: number = uri.lastIndexOf('/');
  const raw: string = cut >= 0 ? uri.substring(cut + 1) : uri;
  try {
    return decodeURIComponent(raw);
  } catch (e) {
    return raw;
  }
}
