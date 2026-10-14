import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'UserAgreement';
const FILE_NAME: string = 'user_agreement.json';
/** 落盘结构变了就 +1，读到不认识的版本按默认值处理 */
const SETTINGS_VERSION: number = 1;

/**
 * 首启用户协议与隐私政策同意状态
 *
 * 首次启动弹出协议/隐私政策确认页，用户点「同意并继续」后把结果落盘，
 * 后续启动不再重复展示；未同意时主界面被整屏遮罩盖住（见 views/UserAgreementDialog）。
 *
 * 存法与其它设置单例一致：JSON 落盘 + AppStorage 发布，界面用 @StorageLink 订阅。
 * 与其它设置不同的是落盘位置固定用 context.filesDir（应用私有沙箱）而不是
 * storageRootDir（公共 Download/LxMusicData）：协议同意是应用级合规标记，
 * 不能跟着公共目录被用户手动清理而丢失，也不依赖公共目录写权限。
 */
export const K_AGREEMENT_ACCEPTED: string = 'cfg_agreement_accepted';

/** 落盘结构（字段全部可选：老文件可能缺字段） */
interface UserAgreementData {
  version?: number;
  /** 用户是否已同意用户协议与隐私政策 */
  accepted?: boolean;
}

export class UserAgreement {
  private static instance: UserAgreement | null = null;

  static getInstance(): UserAgreement {
    if (UserAgreement.instance === null) {
      UserAgreement.instance = new UserAgreement();
    }
    return UserAgreement.instance;
  }

  private file: string = '';
  private inited: boolean = false;
  private accepted: boolean = false;

  init(context: common.Context): void {
    if (this.inited) {
      return;
    }
    this.file = `${context.filesDir}/${FILE_NAME}`;
    this.inited = true;
    const text: string = this.read();
    if (text.length > 0) {
      try {
        this.apply(JSON.parse(text) as UserAgreementData);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'failed to parse user agreement: %{public}s', JSON.stringify(e));
      }
    }
    this.publish();
  }

  private read(): string {
    try {
      if (!fs.accessSync(this.file)) {
        return '';
      }
      return fs.readTextSync(this.file);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'failed to read user agreement: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  private write(): void {
    if (!this.inited) {
      return;
    }
    const data: UserAgreementData = {
      version: SETTINGS_VERSION,
      accepted: this.accepted,
    };
    try {
      const handle = fs.openSync(this.file, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, JSON.stringify(data));
      } finally {
        fs.closeSync(handle);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'failed to write user agreement: %{public}s', JSON.stringify(e));
    }
  }

  private apply(data: UserAgreementData): void {
    if (data.version !== SETTINGS_VERSION) {
      return;
    }
    if (data.accepted !== undefined) {
      this.accepted = data.accepted;
    }
  }

  private publish(): void {
    try {
      AppStorage.setOrCreate(K_AGREEMENT_ACCEPTED, this.accepted);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'failed to publish user agreement: %{public}s', JSON.stringify(e));
    }
  }

  isAccepted(): boolean {
    return this.accepted;
  }

  /** 用户点「同意并继续」：落盘 + 发布，界面弹窗随之关闭 */
  accept(): void {
    if (this.accepted) {
      return;
    }
    this.accepted = true;
    AppStorage.setOrCreate(K_AGREEMENT_ACCEPTED, true);
    this.write();
  }
}
