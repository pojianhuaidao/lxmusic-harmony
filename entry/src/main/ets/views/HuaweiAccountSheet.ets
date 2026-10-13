import { common } from '@kit.AbilityKit';
import { AccountBackupResult, HuaweiAccount, K_ACCOUNT_NAME, K_ACCOUNT_UID } from '../core/account/HuaweiAccount';
import { C_BG, C_CARD, C_FILL_SOFT, C_RED, C_TEXT, C_TEXT_SUB, C_TEXT_WEAK, F_ITEM, F_SUB, R_CARD } from '../ui/Theme';
import { I_CHEVRON_RIGHT, I_PERSON, I_PERSON_FILL, IconGlyph } from '../ui/Icons';

/**
 * 华为账号登录 / 管理面板（「我的」页右上角那颗人形钮打开的半模态）
 *
 * 未登录：说明 + 「使用华为账号登录」；已登录：显示账号信息 + 「备份 / 恢复数据」入口
 * （跳到备份选项页）+ 退出登录。登录态同时驱动「我的」页右上角图标状态。
 */
@Component
export struct HuaweiAccountSheet {
  /** 内容底部要留出的空间：手势条（由壳层算好） */
  @Prop bottomInset: number = 0;
  /** 去备份选项页（壳层路由） */
  onGoBackup: () => void = () => {
  };
  /** 关闭本面板（由壳层收起 bindSheet 状态位） */
  onClose: () => void = () => {
  };
  @StorageLink(K_ACCOUNT_UID) accountUid: string = '';
  @StorageLink(K_ACCOUNT_NAME) accountName: string = '';
  @State logging: boolean = false;

  private async doLogin(): Promise<void> {
    if (this.logging) {
      return;
    }
    this.logging = true;
    const context: common.Context = getContext(this) as common.Context;
    const result: AccountBackupResult = await HuaweiAccount.getInstance().login(context);
    this.logging = false;
    this.toast(result.message);
    if (result.ok) {
      this.onClose();
    }
  }

  private async doLogout(): Promise<void> {
    await HuaweiAccount.getInstance().logout();
    this.toast('已退出登录');
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  @Builder
  loginBody() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        IconGlyph({ symbol: I_PERSON, iconSize: 26, color: C_RED })
        Text('华为账号')
          .fontSize(F_ITEM)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_TEXT)
      }
      .width('100%')

      Text('登录华为账号后，可把试听列表 / 收藏 / 歌单 / 不喜欢规则备份到华为云端备份区，'
        + '或随时恢复回来。登录将拉起华为账号授权（AGC 认证服务）。')
        .fontSize(F_SUB)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .textAlign(TextAlign.Start)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(C_FILL_SOFT)
          .fontColor(C_TEXT)
          .onClick(() => {
            this.onClose();
          })
        Button(this.logging ? '授权中…' : '使用华为账号登录')
          .layoutWeight(2)
          .height(40)
          .backgroundColor(C_RED)
          .enabled(!this.logging)
          .onClick(() => {
            this.doLogin();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  loggedBody() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        IconGlyph({ symbol: I_PERSON_FILL, iconSize: 26, color: C_RED })
        Text(this.accountName.length > 0 ? this.accountName : '华为账号')
          .fontSize(F_ITEM)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_TEXT)
        Blank()
        Text('已登录')
          .fontSize(F_SUB)
          .fontColor(C_RED)
      }
      .width('100%')

      Text(`账号 UID：${this.accountUid}`)
        .fontSize(F_SUB)
        .fontColor(C_TEXT_WEAK)
        .width('100%')
        .textAlign(TextAlign.Start)

      Row({ space: 8 }) {
        Text('备份 / 恢复数据')
          .fontSize(F_ITEM)
          .fontColor(C_TEXT)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        IconGlyph({ symbol: I_CHEVRON_RIGHT, iconSize: 18, color: C_TEXT_WEAK })
          .accessibilityLevel('no')
      }
      .width('100%')
      .height(52)
      .padding({ left: 14, right: 14 })
      .borderRadius(16)
      .backgroundColor(C_FILL_SOFT)
      .onClick(() => {
        this.onClose();
        this.onGoBackup();
      })

      Text('退出登录')
        .fontSize(F_SUB)
        .fontColor(C_RED)
        .width('100%')
        .textAlign(TextAlign.End)
        .onClick(() => {
          this.doLogout();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8 })
  }

  build() {
    Column() {
      if (this.accountUid.length > 0) {
        this.loggedBody()
      } else {
        this.loginBody()
      }
      Column().height(this.bottomInset + 8).width('100%')
    }
    .width('100%')
    .padding({ bottom: 8 })
    .backgroundColor(C_BG)
  }
}
