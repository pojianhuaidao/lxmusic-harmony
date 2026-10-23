import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { C_BG, C_CARD, C_DIVIDER, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK, F_ITEM, F_SUB, R_CARD } from '../ui/Theme';
import { HintText } from '../ui/SettingWidgets';

const DOMAIN: number = 0x0001;
const TAG: string = 'AboutView';

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
 * 两块：应用本身（图标 / 名称 / 版本）、关于软件（作者 / 开源协议）。
 */
@Component
export struct AboutView {
  /** 内容让出标题栏那一段（壳层传来的「状态栏 + 标题栏」）：见滚动内容里的顶部占位 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State version: string = '';

  aboutToAppear(): void {
    this.version = readVersionName();
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
          ? `v${this.version} · 鸿蒙原生音乐播放器`
          : '鸿蒙原生音乐播放器')
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

  @Builder
  aboutCard() {
    Column() {
      this.infoRow('作者', AUTHOR)
      Divider().strokeWidth(0.6).color(C_DIVIDER).margin({ left: 18 })
      this.infoRow('开源协议', LICENSE)
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
          this.appCard()

          this.aboutCard()
          HintText({ text: '该软件在 GitHub 上以阿帕奇 2.0 协议开源，欢迎 Star、提 Issue 或提 PR。' })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.bottomInset + 20 })
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
