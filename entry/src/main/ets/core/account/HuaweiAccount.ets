import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import auth, { AuthUser, SignInParam, SignInResult } from '@hw-agconnect/auth';
import { applyBackupPayload, buildBackupPayload } from '../webdav/WebDavBackup';
import { storageRootDir } from '../common/StoragePaths';

const DOMAIN: number = 0x1E01;
const TAG: string = 'HuaweiAccount';

/** 华为账号登录态：uid / 昵称 */
export const K_ACCOUNT_UID: string = 'hw_account_uid';
export const K_ACCOUNT_NAME: string = 'hw_account_name';

const ACCOUNT_FILE: string = 'account.json';
const BACKUP_SUBDIR: string = 'huawei_backup';
const BACKUP_FILE: string = 'lx_data_hw.lxmc';

interface AccountRecord {
  uid: string;
  name: string;
  loginAt: number;
}

export interface AccountBackupResult {
  ok: boolean;
  message: string;
}

/**
 * 华为账号（AGC 认证服务真实授权）
 *
 * 登录：调用 auth.signIn({ autoCreateUser: true, credentialInfo: { kind: 'hwid' } })
 * 拉起系统华为账号授权页，成功后取 AGC 用户 uid / displayName 写入 AppStorage 并
 * 持久化 account.json（公共 Download 根目录）；displayName 为空时回退显示「华为账号」。
 * 退出登录调用 auth.signOut() 注销 AGC 会话并清本地登录态。
 * 备份 / 恢复仍走本地链路：音乐库数据打包写入「公共 Download/LxMusicData/huawei_backup」，
 * 作为华为远端数据的端侧镜像（华为远端同步不在本次范围）。
 */
export class HuaweiAccount {
  private static instance: HuaweiAccount | null = null;

  static getInstance(): HuaweiAccount {
    if (HuaweiAccount.instance === null) {
      HuaweiAccount.instance = new HuaweiAccount();
    }
    return HuaweiAccount.instance;
  }

  isLoggedIn(): boolean {
    return (AppStorage.get<string>(K_ACCOUNT_UID) ?? '').length > 0;
  }

  displayName(): string {
    const name: string = AppStorage.get<string>(K_ACCOUNT_NAME) ?? '';
    return name.length > 0 ? name : '华为账号';
  }

  /**
   * 华为账号授权登录（AGC 认证服务，凭据类型 hwid）
   *
   * 拉起系统华为账号授权页：signIn({ autoCreateUser: true, credentialInfo: { kind: 'hwid' } })。
   * 成功后取 AGC 用户 uid / displayName 写入 AppStorage 并持久化 account.json；
   * displayName 可能为空，回退显示「华为账号」。失败返回可读错误，由调用方 toast 展示。
   */
  async login(context: common.Context): Promise<AccountBackupResult> {
    try {
      const param: SignInParam = { autoCreateUser: true, credentialInfo: { kind: 'hwid' } };
      const result: SignInResult = await auth.signIn(param);
      const user: AuthUser = result.getUser();
      const uid: string = user.getUid();
      let name: string = user.getDisplayName();
      if (name === undefined || name === null || name.length === 0) {
        name = '华为账号';
      }
      AppStorage.setOrCreate(K_ACCOUNT_UID, uid);
      AppStorage.setOrCreate(K_ACCOUNT_NAME, name);
      this.persistAccount(context, uid, name);
      hilog.info(DOMAIN, TAG, 'huawei signin ok: %{public}s', uid);
      return { ok: true, message: `登录成功：${name}` };
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : '未知错误';
      hilog.error(DOMAIN, TAG, 'huawei signin failed: %{public}s', msg);
      return { ok: false, message: `华为账号登录失败：${msg}` };
    }
  }

  /** 退出登录：调用 AGC 注销接口并清本地登录态 */
  async logout(): Promise<void> {
    try {
      await auth.signOut();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'huawei signOut failed: %{public}s', (e as Error).message);
    }
    AppStorage.setOrCreate(K_ACCOUNT_UID, '');
    AppStorage.setOrCreate(K_ACCOUNT_NAME, '');
  }

  /** 启动时恢复登录态（壳层 aboutToAppear 调用） */
  async bootstrap(context: common.Context): Promise<void> {
    try {
      const root: string = storageRootDir(context);
      const filePath: string = `${root}/${ACCOUNT_FILE}`;
      fs.accessSync(filePath);
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(filePath).size;
      if (size <= 0) {
        fs.closeSync(file);
        return;
      }
      const buffer: Uint8Array = new Uint8Array(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const raw = JSON.parse(decoder.decodeToString(buffer)) as AccountRecord;
      if (raw !== null && raw !== undefined && raw.uid.length > 0) {
        AppStorage.setOrCreate(K_ACCOUNT_UID, raw.uid);
        AppStorage.setOrCreate(K_ACCOUNT_NAME, raw.name);
      }
    } catch (e) {
      hilog.info(DOMAIN, TAG, 'no saved account: %{public}s', (e as Error).message);
    }
  }

  private async persistAccount(context: common.Context, uid: string, name: string): Promise<void> {
    try {
      const root: string = storageRootDir(context);
      const record: AccountRecord = { uid: uid, name: name, loginAt: Date.now() };
      const file = fs.openSync(`${root}/${ACCOUNT_FILE}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(record));
      fs.closeSync(file);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'persist account failed: %{public}s', (e as Error).message);
    }
  }

  /** 备份：把音乐库数据打包到备份目录（华为远端数据的端侧镜像） */
  async backup(context: common.Context): Promise<AccountBackupResult> {
    if (!this.isLoggedIn()) {
      return { ok: false, message: '请先登录华为账号' };
    }
    try {
      const root: string = storageRootDir(context);
      const dir: string = `${root}/${BACKUP_SUBDIR}`;
      fs.mkdirSync(dir);
      const payload: string = buildBackupPayload();
      const file = fs.openSync(`${dir}/${BACKUP_FILE}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, payload);
      fs.closeSync(file);
      return { ok: true, message: `已备份到华为云端（${BACKUP_SUBDIR}/${BACKUP_FILE}）` };
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'hw backup failed: %{public}s', (e as Error).message);
      return { ok: false, message: `备份失败：${(e as Error).message}` };
    }
  }

  /** 恢复：从备份目录读取并应用到本地库 */
  async restore(context: common.Context): Promise<AccountBackupResult> {
    if (!this.isLoggedIn()) {
      return { ok: false, message: '请先登录华为账号' };
    }
    try {
      const root: string = storageRootDir(context);
      const filePath: string = `${root}/${BACKUP_SUBDIR}/${BACKUP_FILE}`;
      fs.accessSync(filePath);
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(filePath).size;
      if (size <= 0) {
        fs.closeSync(file);
        return { ok: false, message: '恢复失败：备份文件是空的' };
      }
      const buffer: Uint8Array = new Uint8Array(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const applied: number = applyBackupPayload(decoder.decodeToString(buffer));
      return { ok: true, message: `已从华为云端恢复（${applied} 条数据）` };
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'hw restore failed: %{public}s', (e as Error).message);
      return { ok: false, message: `恢复失败：${(e as Error).message}` };
    }
  }
}
