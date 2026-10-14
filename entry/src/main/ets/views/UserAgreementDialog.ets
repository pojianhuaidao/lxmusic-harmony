import { C_BG, C_CARD, C_DIVIDER, C_TEXT, C_TEXT_SUB, F_ITEM, F_SECTION, F_SUB, F_TITLE, R_PILL } from '../ui/Theme';

/**
 * 首启用户协议 / 隐私政策确认页（整屏遮罩）
 *
 * 由 Index 壳层在「未同意」时渲染，盖在主界面最上层：主界面仍然在后面初始化、
 * 但用户看不到也点不到，满足「未同意不得进入主界面」；点「同意并继续」后由
 * 壳层调 UserAgreement.accept() 落盘，本弹窗随 @StorageLink 状态消失。
 *
 * 「不同意」只给提示不退出应用：退出需要 terminateSelf，而 AGC 审核/测试分发
 * 拉起应用时（action 非 home）若自杀式退出会被判「启动即闪退」，所以用遮罩
 * 挡住而非退出，是更安全的合规呈现方式。
 *
 * 文案为内置占位内容，正式发布前请替换为合规版本（见 AGREEMENT_TEXT / PRIVACY_TEXT）。
 */

const AGREEMENT_TITLE: string = '用户协议';
const PRIVACY_TITLE: string = '隐私政策';

/** 【占位文案】正式发布前请替换为律师/法务确认后的合规版本 */
const AGREEMENT_TEXT: string = '【占位文案 · 正式发布前请替换为合规版本】\n\n' +
  '欢迎使用本应用。在使用本应用前，请仔细阅读并充分理解本用户协议（以下简称"本协议"）。\n\n' +
  '一、服务说明\n' +
  '本应用提供音乐搜索、播放、下载、歌单管理等服务。使用本应用即表示您同意本协议的全部条款。\n\n' +
  '二、用户行为规范\n' +
  '您不得利用本应用从事任何违反法律法规的活动，不得侵犯他人知识产权，不得对本应用进行逆向工程、破解或干扰。\n\n' +
  '三、免责声明\n' +
  '本应用仅提供技术工具与播放能力，音乐内容来源由用户自行选择。因使用本应用产生的任何纠纷，请依法解决。\n\n' +
  '四、协议的变更\n' +
  '我们可能适时修改本协议，修改后的协议将在应用内公示。您继续使用本应用即视为接受修改后的协议。';

/** 【占位文案】正式发布前请替换为律师/法务确认后的合规版本 */
const PRIVACY_TEXT: string = '【占位文案 · 正式发布前请替换为合规版本】\n\n' +
  '我们重视您的个人信息保护。本隐私政策说明我们如何收集、使用、存储和保护您的信息。\n\n' +
  '一、我们收集的信息\n' +
  '为提供播放与同步服务，我们会在本地保存您的播放设置、歌单、播放历史、下载记录等数据；' +
  '若您使用账号登录，我们会处理您授权提供的账号标识信息。\n\n' +
  '二、信息的使用\n' +
  '您的数据默认仅存储在本机；仅在您主动开启云端同步（WebDAV / 华为账号备份）时，才会将您选择的数据上传至您指定的服务。\n\n' +
  '三、信息的保护\n' +
  '我们采取合理的技术与组织措施保护您的数据安全，未经您的授权不向第三方披露。\n\n' +
  '四、您的权利\n' +
  '您可以随时在设置中关闭同步、清除本地数据，或通过应用内入口联系我们处理您的数据相关请求。';

/**
 * 首启协议确认页组件
 *
 * @param onAccept 点「同意并继续」：壳层调 UserAgreement.accept() 落盘并关闭遮罩
 * @param onDecline 点「不同意」：壳层给提示（遮罩保持，不进入主界面）
 */
@Component
export struct UserAgreementDialog {
  onAccept: () => void = () => {
  };
  onDecline: () => void = () => {
  };

  build() {
    Stack() {
      // 半透明遮罩：盖住整屏（含状态栏/导航条区域，expandSafeArea 后铺满全窗口）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#B3000000')

      // 居中卡片：标题 + 可滚动文案 + 按钮行
      Column() {
        Column() {
          Text('欢迎使用')
            .fontSize(F_SECTION)
            .fontColor(C_TEXT_SUB)
          Text('用户协议与隐私政策')
            .fontSize(F_TITLE)
            .fontColor(C_TEXT)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 6 })
        }
        .width('100%')
        .padding({ top: 22, bottom: 14 })
        .alignItems(HorizontalAlign.Center)

        Divider()
          .color(C_DIVIDER)

        // 文案区：上下两段可滚动阅读
        Scroll() {
          Column() {
            Text(AGREEMENT_TITLE)
              .fontSize(F_ITEM)
              .fontColor(C_TEXT)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            Text(AGREEMENT_TEXT)
              .fontSize(F_SUB)
              .fontColor(C_TEXT_SUB)
              .lineHeight(19)
              .width('100%')
              .margin({ top: 8 })

            Divider()
              .color(C_DIVIDER)
              .margin({ top: 18, bottom: 18 })

            Text(PRIVACY_TITLE)
              .fontSize(F_ITEM)
              .fontColor(C_TEXT)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            Text(PRIVACY_TEXT)
              .fontSize(F_SUB)
              .fontColor(C_TEXT_SUB)
              .lineHeight(19)
              .width('100%')
              .margin({ top: 8 })
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })

        Divider()
          .color(C_DIVIDER)

        Row() {
          Button('不同意')
            .fontSize(F_SUB)
            .fontColor(C_TEXT_SUB)
            .backgroundColor(C_CARD)
            .borderRadius(R_PILL)
            .layoutWeight(1)
            .onClick(() => {
              this.onDecline();
            })
          Button('同意并继续')
            .fontSize(F_SUB)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.c_red'))
            .borderRadius(R_PILL)
            .layoutWeight(1)
            .margin({ left: 14 })
            .onClick(() => {
              this.onAccept();
            })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14, bottom: 16 })
      }
      .width('88%')
      .constraintSize({ maxHeight: '86%' })
      .backgroundColor(C_BG)
      .borderRadius(22)
      // 避开状态栏 / 导航条：全屏布局下遮罩铺满窗口，卡片留出安全区高度
      .margin({ top: 56, bottom: 56 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
