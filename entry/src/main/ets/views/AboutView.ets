import { bundleManager, common, Want } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppLog } from '../core/log/AppLog';
import { C_BG, C_CARD, C_DIVIDER, C_ICON_BLUE, C_PRESSED, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK, F_ITEM, F_SUB, R_CARD } from '../ui/Theme';
import { HintText } from '../ui/SettingWidgets';
import { I_EXTERNAL, IconGlyph } from '../ui/Icons';

const DOMAIN: number = 0x0001;
const TAG: string = 'AboutView';

/** 项目主页（点开交给系统浏览器；地址按用户给的原样展示，带 .git 也能正常打开） */
const REPO_URL: string = 'https://github.com/pojianhuaidao/lxmusic-harmony';
const AUTHOR: string = 'pojianhuaidao';
/** 协议名按官方写法给出，中文说明里再说一次「阿帕奇 2.0」 */
const LICENSE: string = 'Apache License 2.0';

/**
 * 版本号取自安装包信息
 *
 * 不写死在界面里：`AppScope/app.json5` 的 versionName 一改这里跟着变，
 * 免得出现「界面写着 1.0.0、装的是 1.1.0」这种对不上的情况。
 */
function readVersionName(): string {
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionName;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read version failed: %{public}s', (e as BusinessError).message);
    return '';
  }
}

/**
 * 关于（设置 - 关于）
 *
 * 两块：应用本身（图标 / 名称 / 版本）、关于软件（作者 / 协议 / 仓库地址）。
 * 能点的都做成可点的：仓库地址交给系统浏览器打开。
 */
@Component
export struct AboutView {
  /** 内容让出标题栏那一段（壳层传来的「状态栏 + 标题栏」）：见滚动内容里的顶部占位 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State version: string = '';
  /** 运行日志展示文本（AppLog.dump() 的快照，定时刷新保持接近实时） */
  @State logText: string = '';
  private logTimer: number = -1;

  aboutToAppear(): void {
    this.version = readVersionName();
    this.refreshLog();
    // 每 2 秒刷新一次日志快照，避免用户开着关于页等日志时看不到新增
    this.logTimer = setInterval(() => {
      this.refreshLog();
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.logTimer >= 0) {
      clearInterval(this.logTimer);
      this.logTimer = -1;
    }
  }

  private refreshLog(): void {
    this.logText = AppLog.dump();
  }

  /** 把当前日志全文复制到系统剪贴板（失败弹 toast 提示） */
  private copyLog(): void {
    const text: string = this.logText.length > 0 ? this.logText : '暂无日志';
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast('运行日志已复制');
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'copy log failed: %{public}s', err.message);
        this.toast('复制失败，请重试');
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'copy log create data failed: %{public}s', JSON.stringify(e));
      this.toast('复制失败，请重试');
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  /**
   * 打开项目主页
   *
   * 这里**不用** `UIAbilityContext.openLink()`：那个接口要求应用在 module.json5 里
   * 声明并校验过域名归属（域名没验证过会报 16000019「没有匹配的应用」），
   * 传一个任意 https 地址是打不开的。用一个「浏览网页」的隐式 Want 让系统去挑浏览器，
   * 是通用且稳定的做法。
   *
   * 失败不静默：把地址原样弹出来，用户至少能自己复制去搜。
   */
  private openRepo(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: REPO_URL,
    };
    context.startAbility(want).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'open repo failed: %{public}s', err.message);
      this.toast(`没能打开浏览器，地址是：${REPO_URL}`);
    });
  }

  /** 应用卡片：图标 + 名称 + 版本与一句话说明 */
  @Builder
  appCard() {
    Row({ space: 15 }) {
      Image($r('app.media.startIcon'))
        .width(62)
        .height(62)
        .borderRadius(15)
        .draggable(false)

      Column({ space: 6 }) {
        Text('听·音乐')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(C_TEXT)
          .width('100%')
          .textAlign(TextAlign.Start)
        Text(this.version.length > 0
          ? `v${this.version} · 洛雪音乐（LX Music）的鸿蒙移植版`
          : '洛雪音乐（LX Music）的鸿蒙移植版')
          .fontSize(F_SUB)
          .fontColor(C_TEXT_WEAK)
          .maxLines(2)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 20, bottom: 20 })
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  /** 键值一行（作者 / 开源协议） */
  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(F_ITEM)
        .fontColor(C_TEXT)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      Text(value)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(56)
    .padding({ left: 18, right: 18 })
  }

  /** 项目主页：上面一行小字标签，下面是完整地址（点开浏览器） */
  @Builder
  repoRow() {
    Column({ space: 5 }) {
      Text('项目主页')
        .fontSize(F_SUB)
        .fontColor(C_TEXT_WEAK)
        .width('100%')
        .textAlign(TextAlign.Start)
      Row({ space: 6 }) {
        Text(REPO_URL)
          .fontSize(13.5)
          .fontColor(C_ICON_BLUE)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
        IconGlyph({ symbol: I_EXTERNAL, iconSize: 15, color: C_ICON_BLUE })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 16, top: 14, bottom: 15 })
    .stateStyles({
      normal: { .backgroundColor(Color.Transparent) },
      pressed: { .backgroundColor(C_PRESSED) },
    })
    .onClick(() => {
      this.openRepo();
    })
    .accessibilityText(`打开项目主页 ${REPO_URL}`)
    .accessibilityLevel('yes')
  }

  @Builder
  aboutCard() {
    Column() {
      this.infoRow('作者', AUTHOR)
      Divider().strokeWidth(0.6).color(C_DIVIDER).margin({ left: 18 })
      this.infoRow('开源协议', LICENSE)
      Divider().strokeWidth(0.6).color(C_DIVIDER).margin({ left: 18 })
      this.repoRow()
    }
    .width('100%')
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
    .clip(true)
  }

  /**
   * 运行日志卡片：标题 + 「复制全部 / 刷新」按钮 + 可滚动、可长按选择的日志文本。
   *
   * 手机上连不上 logcat 时，用户在这里把最近的关键事件（播放失败、音源请求等）
   * 复制出来反馈给开发者；文本同时开了 copyOption，长按也能手动选择复制。
   */
  @Builder
  logCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('运行日志')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(C_TEXT)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        Button('复制全部')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor(C_ICON_BLUE)
          .height(30)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.copyLog();
          })
        Button('刷新')
          .fontSize(13)
          .fontColor(C_TEXT_SUB)
          .backgroundColor(C_PRESSED)
          .height(30)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.refreshLog();
          })
      }
      .width('100%')

      Scroll() {
        Text(this.logText.length > 0 ? this.logText : '暂无日志')
          .fontSize(12)
          .fontColor(C_TEXT_SUB)
          .lineHeight(18)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .height(260)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)

      Text(`共 ${AppLog.count()} 条 · 内存环形日志（最多 200 条，重启即清空）`)
        .fontSize(11)
        .fontColor(C_TEXT_WEAK)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(R_CARD)
    .backgroundColor(C_CARD)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 顶部占位：第一行落在透明标题栏下方，但它跟着内容一起滚走 —— 用容器内边距会把
          // 这一段内容裁在标题栏下边缘，看起来就"像被顶栏挡住"（首页就是这么做的）
          Column().height(this.topInset + 6).width('100%')
          this.appCard()

          this.aboutCard()
          this.logCard()
          HintText({ text: '该软件在 GitHub 上以阿帕奇 2.0 协议开源，欢迎 Star、提 Issue 或提 PR。' })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.bottomInset + 20 })
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
