import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cloudCommon, cloudStorage } from '@kit.CloudFoundationKit';
import auth, { AuthUser, SignInParam, SignInResult } from '@hw-agconnect/auth';
import { ALL_SCOPE, applyBackupPayload, BackupScope, buildBackupPayload } from '../webdav/WebDavBackup';
import { storageRootDir } from '../common/StoragePaths';

const DOMAIN: number = 0x1E01;
const TAG: string = 'HuaweiAccount';

/** 华为账号登录态：uid / 昵称 */
export const K_ACCOUNT_UID: string = 'hw_account_uid';
export const K_ACCOUNT_NAME: string = 'hw_account_name';

const ACCOUNT_FILE: string = 'account.json';
const BACKUP_SUBDIR: string = 'huawei_backup';
const BACKUP_FILE: string = 'lx_data_hw.lxmc';
/** AGC Cloud Storage 远端目录（真正云端备份区） */
const CLOUD_DIR: string = 'lxmusic_backups';

interface AccountRecord {
  uid: string;
  name: string;
  loginAt: number;
}

/**
 * 候选应用数据根目录
 *
 * storageRootDir 每次进程启动探测一次：公共 Download/LxMusicData 能建目录就返回它，
 * 否则回退沙箱 filesDir。公共目录可写性（媒体权限/系统状态）波动时，两次启动可能
 * 落到不同根目录，导致 account.json / huawei_backup 明明写过却读不到（表现为
 * 「重开未登录」「备份后拉不到恢复文件」）。这里把两个候选根都列出来，读写时都覆盖。
 */
function candidateRoots(context: common.Context): string[] {
  const roots: string[] = [];
  const primary: string = storageRootDir(context);
  const fallback: string = context.filesDir;
  if (primary.length > 0 && primary !== fallback) {
    roots.push(primary);
  }
  if (fallback.length > 0) {
    roots.push(fallback);
  }
  return roots;
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
 * 备份 / 恢复：音乐库数据打包后上传到 AGC Cloud Storage（远端目录
 * lxmusic_backups/lx_data_hw.lxmc），恢复时优先从云端拉取；同时写一份本地
 * 端侧镜像（公共 Download/LxMusicData/huawei_backup）作冗余与旧版兼容。
 */
export class HuaweiAccount {
  private static instance: HuaweiAccount | null = null;
  /** AGC Cloud Storage 是否已初始化成功 */
  private cloudReady: boolean = false;

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
   *
   * 会话残留处理：AGC 会话是 SDK 自己持久化的（token 在沙箱里），重启后即使本地
   * account.json 丢失（根目录漂移），SDK 仍认为已登录 —— 此时直接 signIn 会报
   * "already sign in a user, please sign out at first"。登录前先 getCurrentUser 探测，
   * 有残留会话先 signOut 再登录；万一探测漏了、signIn 仍报该错，也自动注销重试一次。
   */
  async login(context: common.Context): Promise<AccountBackupResult> {
    const param: SignInParam = { autoCreateUser: true, credentialInfo: { kind: 'hwid' } };
    try {
      const current: AuthUser | null = await auth.getCurrentUser();
      if (current !== null && current !== undefined) {
        hilog.info(DOMAIN, TAG, 'residual agc session detected, sign out first');
        await auth.signOut();
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'pre-signout check failed: %{public}s', (e as Error).message);
    }
    try {
      return await this.doSignIn(context, param);
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : '未知错误';
      if (msg.indexOf('already sign in') >= 0) {
        hilog.warn(DOMAIN, TAG, 'signIn rejected by residual session, retry after signOut');
        try {
          await auth.signOut();
        } catch (e2) {
          hilog.warn(DOMAIN, TAG, 'signOut before retry failed: %{public}s', (e2 as Error).message);
        }
        try {
          return await this.doSignIn(context, param);
        } catch (e3) {
          const msg3: string = (e3 as Error).message !== undefined ? (e3 as Error).message : '未知错误';
          hilog.error(DOMAIN, TAG, 'huawei signin retry failed: %{public}s', msg3);
          return { ok: false, message: `华为账号登录失败：${msg3}` };
        }
      }
      hilog.error(DOMAIN, TAG, 'huawei signin failed: %{public}s', msg);
      return { ok: false, message: `华为账号登录失败：${msg}` };
    }
  }

  private async doSignIn(context: common.Context, param: SignInParam): Promise<AccountBackupResult> {
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
    let localUid: string = '';
    let localName: string = '';
    // 1) 本地 account.json 恢复（两个候选根都找：公共根与沙箱根可能漂移）
    const roots: string[] = candidateRoots(context);
    for (let i = 0; i < roots.length; i++) {
      const filePath: string = `${roots[i]}/${ACCOUNT_FILE}`;
      try {
        fs.accessSync(filePath);
        const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
        const size: number = fs.statSync(filePath).size;
        if (size <= 0) {
          fs.closeSync(file);
          continue;
        }
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        fs.readSync(file.fd, buffer);
        fs.closeSync(file);
        const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
        const raw = JSON.parse(decoder.decodeToString(new Uint8Array(buffer))) as AccountRecord;
        if (raw !== null && raw !== undefined && raw.uid.length > 0) {
          localUid = raw.uid;
          localName = raw.name;
          break;
        }
      } catch (e) {
        hilog.info(DOMAIN, TAG, 'no account at %{public}s: %{public}s', filePath, (e as Error).message);
      }
    }
    // 2) 与 AGC 会话对齐：SDK 有残留会话（本地没读到/读到的丢了）时以 AGC 为准恢复，
    //    避免界面显示未登录、点登录却被 "already sign in" 挡住。
    try {
      const current: AuthUser | null = await auth.getCurrentUser();
      if (current !== null && current !== undefined) {
        const agcUid: string = current.getUid();
        if (agcUid.length > 0) {
          let name: string = current.getDisplayName();
          if (name === undefined || name === null || name.length === 0) {
            name = '华为账号';
          }
          AppStorage.setOrCreate(K_ACCOUNT_UID, agcUid);
          AppStorage.setOrCreate(K_ACCOUNT_NAME, name);
          this.persistAccount(context, agcUid, name);
          hilog.info(DOMAIN, TAG, 'bootstrap restored from agc session: %{public}s', agcUid);
          return;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'agc session check failed: %{public}s', (e as Error).message);
    }
    // 3) AGC 无会话：回退到本地记录
    if (localUid.length > 0) {
      AppStorage.setOrCreate(K_ACCOUNT_UID, localUid);
      AppStorage.setOrCreate(K_ACCOUNT_NAME, localName);
    }
  }

  private async persistAccount(context: common.Context, uid: string, name: string): Promise<void> {
    const roots: string[] = candidateRoots(context);
    const record: AccountRecord = { uid: uid, name: name, loginAt: Date.now() };
    for (let i = 0; i < roots.length; i++) {
      try {
        const file = fs.openSync(`${roots[i]}/${ACCOUNT_FILE}`,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, JSON.stringify(record));
        fs.closeSync(file);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'persist account at %{public}s failed: %{public}s',
          `${roots[i]}/${ACCOUNT_FILE}`, (e as Error).message);
      }
    }
  }

  /** 初始化 AGC Cloud Storage（幂等：成功一次后不再重复 init） */
  private async ensureCloud(): Promise<void> {
    if (this.cloudReady) {
      return;
    }
    cloudCommon.init({
      authProvider: auth.getAuthProvider(),
      region: cloudCommon.CloudRegion.CHINA
    });
    this.cloudReady = true;
  }

  /** 等待云传输任务结束（completed / failed 二选一） */
  private static awaitTask(task: request.agent.Task): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      const onCompleted = (): void => {
        task.off('completed', onCompleted);
        task.off('failed', onFailed);
        resolve();
      };
      const onFailed = (): void => {
        task.off('completed', onCompleted);
        task.off('failed', onFailed);
        reject(new Error('云传输失败'));
      };
      task.on('completed', onCompleted);
      task.on('failed', onFailed);
    });
  }

  /**
   * 备份：按勾选范围把音乐库数据打包 → 上传到 AGC Cloud Storage（真正云端备份区），
   * 同时写一份本地端侧镜像作为冗余（旧版本数据与断网兜底）。
   * @param scope 备份内容选择（试听列表 / 收藏 / 歌单 / 不喜欢规则 / 音源）
   */
  async backup(context: common.Context, scope?: BackupScope): Promise<AccountBackupResult> {
    if (!this.isLoggedIn()) {
      return { ok: false, message: '请先登录华为账号' };
    }
    const sc: BackupScope = scope !== undefined && scope !== null ? scope : ALL_SCOPE;
    const payload: string = buildBackupPayload(sc, context);
    // 1) 本地端侧镜像（兼容旧版恢复链路，也便于断网时本地兜底）
    const roots: string[] = candidateRoots(context);
    for (let i = 0; i < roots.length; i++) {
      try {
        const dir: string = `${roots[i]}/${BACKUP_SUBDIR}`;
        fs.mkdirSync(dir);
        const file = fs.openSync(`${dir}/${BACKUP_FILE}`,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, payload);
        fs.closeSync(file);
        break;
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'hw local mirror at %{public}s failed: %{public}s',
          `${roots[i]}/${BACKUP_SUBDIR}/${BACKUP_FILE}`, (e as Error).message);
      }
    }
    // 2) 上传 AGC Cloud Storage
    try {
      await this.ensureCloud();
      const cacheName: string = `hw_backup_${Date.now()}.lxmc`;
      const cachePath: string = `${context.cacheDir}/${cacheName}`;
      const file = fs.openSync(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, payload);
      fs.closeSync(file);
      const bucket = cloudStorage.bucket();
      const cloudPath: string = `${CLOUD_DIR}/${BACKUP_FILE}`;
      const task = await bucket.uploadFile(context, {
        localPath: cacheName,
        cloudPath: cloudPath,
        metadata: { contentType: 'application/json' }
      });
      await HuaweiAccount.awaitTask(task);
      try {
        fs.unlinkSync(cachePath);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'remove hw backup cache failed: %{public}s', (e as Error).message);
      }
      return { ok: true, message: `已备份到华为云端（${CLOUD_DIR}/${BACKUP_FILE}）` };
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : '未知错误';
      hilog.error(DOMAIN, TAG, 'hw cloud backup failed: %{public}s', msg);
      return { ok: false, message: `备份失败：${msg}` };
    }
  }

  /**
   * 恢复：优先从 AGC Cloud Storage 拉取远端备份并应用到本地库；
   * 云端无备份（或网络失败）时回退读取本地端侧镜像，兼容旧版本数据。
   */
  async restore(context: common.Context): Promise<AccountBackupResult> {
    if (!this.isLoggedIn()) {
      return { ok: false, message: '请先登录华为账号' };
    }
    // 1) 云端恢复
    try {
      await this.ensureCloud();
      const cacheName: string = `hw_restore_${Date.now()}.lxmc`;
      const cachePath: string = `${context.cacheDir}/${cacheName}`;
      const bucket = cloudStorage.bucket();
      const cloudPath: string = `${CLOUD_DIR}/${BACKUP_FILE}`;
      const task = await bucket.downloadFile(context, { localPath: cacheName, cloudPath: cloudPath });
      await HuaweiAccount.awaitTask(task);
      const size: number = fs.statSync(cachePath).size;
      if (size <= 0) {
        throw new Error('云端备份文件是空的');
      }
      const file = fs.openSync(cachePath, fs.OpenMode.READ_ONLY);
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      try {
        fs.unlinkSync(cachePath);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'remove hw restore cache failed: %{public}s', (e as Error).message);
      }
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const applied: number = applyBackupPayload(decoder.decodeToString(new Uint8Array(buffer)), context);
      return { ok: true, message: `已从华为云端恢复（${applied} 条数据）` };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'hw cloud restore failed, fallback to local mirror: %{public}s',
        (e as Error).message);
    }
    // 2) 本地端侧镜像回退（旧版数据 / 断网兜底）
    const roots: string[] = candidateRoots(context);
    let lastError: string = '未找到备份文件';
    for (let i = 0; i < roots.length; i++) {
      const filePath: string = `${roots[i]}/${BACKUP_SUBDIR}/${BACKUP_FILE}`;
      try {
        fs.accessSync(filePath);
        const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
        const size: number = fs.statSync(filePath).size;
        if (size <= 0) {
          fs.closeSync(file);
          lastError = '备份文件是空的';
          continue;
        }
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        fs.readSync(file.fd, buffer);
        fs.closeSync(file);
        const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
        const applied: number = applyBackupPayload(decoder.decodeToString(new Uint8Array(buffer)), context);
        return { ok: true, message: `已从本地镜像恢复（${applied} 条数据）` };
      } catch (e) {
        lastError = (e as Error).message;
        hilog.error(DOMAIN, TAG, 'hw restore at %{public}s failed: %{public}s', filePath, lastError);
      }
    }
    return { ok: false, message: `恢复失败：${lastError}` };
  }
}
