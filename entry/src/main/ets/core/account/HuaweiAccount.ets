import { common } from '@kit.AbilityKit';
import { cloudSync, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
/**
 * 华为云空间端云文件协同目录（应用沙箱 el2/cloud，写入后由系统自动同步到
 * 使用者自己的华为云空间；不再使用 AGC Cloud Storage 项目 Bucket）。
 */
const CLOUD_DIR: string = '/data/storage/el2/cloud/lxmusic_backups';

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
 * 备份 / 恢复：音乐库数据打包后写入华为云空间端云文件协同目录
 * （el2/cloud/lxmusic_backups/lx_data_hw.lxmc），由系统自动同步到使用者自己的
 * 华为云空间；同时写一份本地端侧镜像（公共 Download/LxMusicData/huawei_backup）
 * 作冗余与旧版兼容。不再使用 AGC Cloud Storage 项目 Bucket（作者空间）。
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

  /** 确保华为云空间同步目录存在（el2/cloud 下，写入后系统自动同步到使用者云空间） */
  private async ensureCloudDir(): Promise<void> {
    if (this.cloudReady) {
      return;
    }
    // 目录已存在则直接复用，避免 mkdirSync 对已存在目录抛 File exists
    let dirExists: boolean = false;
    try {
      fs.accessSync(CLOUD_DIR);
      dirExists = true;
    } catch (e) {
      dirExists = false;
    }
    if (dirExists) {
      this.cloudReady = true;
      return;
    }
    try {
      fs.mkdirSync(CLOUD_DIR, true);
      this.cloudReady = true;
    } catch (e) {
      this.cloudReady = false;
      hilog.error(DOMAIN, TAG, 'create cloud sync dir failed: %{public}s', (e as Error).message);
      throw new Error('创建华为云空间同步目录失败，请检查应用云空间开关');
    }
  }

  /** 带超时的 Promise 包装：超时后强制 reject（防止 SDK 调用本身挂起不返回） */
  private static withTimeout<T>(p: Promise<T>, timeoutMs: number, tip: string): Promise<T> {
    return new Promise<T>((resolve: (v: T) => void, reject: (reason: Error) => void) => {
      let settled: boolean = false;
      const timer: number = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error(tip));
        }
      }, timeoutMs);
      p.then((v: T) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(v);
      }).catch((e: Error) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(e);
      });
    });
  }

  /**
   * 备份：按勾选范围把音乐库数据打包 → 写入华为云空间端云文件协同目录
   * （自动同步到使用者自己的华为云空间），同时写一份本地端侧镜像作为冗余。
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
        // 目录可能已存在：递归创建（存在不报错），避免第二次备份被 File exists 误拦
        fs.mkdirSync(dir, true);
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
    // 2) 写入华为云空间同步目录并触发端云同步（同步到使用者自己的华为云空间）
    try {
      await this.ensureCloudDir();
      const cloudPath: string = `${CLOUD_DIR}/${BACKUP_FILE}`;
      // 先判存在再写：文件尚未产生属正常态，直接走创建分支；已存在则复用覆盖
      try {
        fs.accessSync(cloudPath);
      } catch (e) {
        // 文件不存在，无需处理
      }
      const file = fs.openSync(cloudPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, payload);
      fs.closeSync(file);
      // 触发端云同步并等待单文件上传完成（带 120s 超时兜底，杜绝"备份中"永不结束）
      await this.triggerSyncAndWait(context, cloudPath);
      return { ok: true, message: '已备份到你的华为云空间（lxmusic_backups/lx_data_hw.lxmc）' };
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : '未知错误';
      hilog.error(DOMAIN, TAG, 'hw cloud backup failed: %{public}s', msg);
      return { ok: false, message: `备份失败：${msg}` };
    }
  }

  /**
   * 触发华为云空间端云同步并等待单文件上传完成（带 120s 超时兜底，杜绝"备份中"永不结束）。
   * 依赖用户在系统「设置 -> 云空间」中打开本应用的同步开关。
   */
  private async triggerSyncAndWait(context: common.Context, cloudPath: string): Promise<void> {
    const uri: string = fileUri.getUriFromPath(cloudPath);
    const fileSync = new cloudSync.FileSync();
    const onProgress = (pg: cloudSync.SyncProgress): void => {
      hilog.info(DOMAIN, TAG, 'cloud sync progress state=%{public}s err=%{public}s', pg.state, pg.error);
    };
    fileSync.on('progress', onProgress);
    try {
      await HuaweiAccount.withTimeout(fileSync.start(), 60000, '云空间同步启动超时，请检查网络后重试');
    } catch (e) {
      fileSync.off('progress', onProgress);
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : '未知错误';
      if (msg.indexOf('超时') >= 0) {
        throw new Error('云空间同步启动超时：文件已写入本机云空间目录，稍后将自动同步');
      }
      throw new Error('云空间同步启动失败：请在系统「设置 -> 云空间」中打开本应用的同步开关');
    }
    const deadline: number = Date.now() + 120000;
    while (Date.now() < deadline) {
      try {
        const st: cloudSync.FileState = cloudSync.getCoreFileSyncState(uri);
        if (st === cloudSync.FileState.UPLOAD_SUCCESS) {
          fileSync.off('progress', onProgress);
          return;
        }
        if (st === cloudSync.FileState.UPLOAD_FAILURE) {
          fileSync.off('progress', onProgress);
          throw new Error('云空间同步失败，请检查网络与云空间容量');
        }
      } catch (e) {
        if ((e as Error).message === '云空间同步失败，请检查网络与云空间容量') {
          fileSync.off('progress', onProgress);
          throw new Error('云空间同步失败，请检查网络与云空间容量');
        }
        // 文件刚写入可能暂未建立索引，忽略错误继续轮询
      }
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1000));
    }
    fileSync.off('progress', onProgress);
    throw new Error('云空间同步超时：文件已写入本机云空间目录，稍后将自动同步');
  }

  /**
   * 恢复：优先从华为云空间同步目录读取远端备份并应用到本地库；
   * 云端无备份（或未开同步）时回退读取本地端侧镜像，兼容旧版本数据。
   */
  async restore(context: common.Context): Promise<AccountBackupResult> {
    if (!this.isLoggedIn()) {
      return { ok: false, message: '请先登录华为账号' };
    }
    // 1) 从华为云空间同步目录恢复（el2/cloud 下的文件即云端副本的本地实体，
    //    未开同步或云端无备份时 statSync 抛错，落到本地镜像回退）
    try {
      await this.ensureCloudDir();
      const cloudPath: string = `${CLOUD_DIR}/${BACKUP_FILE}`;
      const size: number = fs.statSync(cloudPath).size;
      if (size <= 0) {
        throw new Error('华为云空间备份文件是空的');
      }
      const file = fs.openSync(cloudPath, fs.OpenMode.READ_ONLY);
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const applied: number = applyBackupPayload(decoder.decodeToString(new Uint8Array(buffer)), context);
      return { ok: true, message: `已从华为云空间恢复（${applied} 条数据）` };
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
