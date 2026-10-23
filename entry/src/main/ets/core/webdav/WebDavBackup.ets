import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebDavClient } from './WebDavClient';
import { WebDavConfig } from './WebDavTypes';
import { LocalLibrary, LibrarySummary } from '../sync/LocalLibrary';
import { LxListData } from '../sync/SyncTypes';
import { SourceBundle, SourceStore } from '../source/SourceStore';

const DOMAIN: number = 0x0001;
const TAG: string = 'WebDavBackup';

/**
 * WebDAV 备份远端目录（原名 LX Backup，与安卓版 lx-music-mobile 共用同一目录；
 * 品牌切割后改用 Music Backup，与安卓版目录不再互通。旧备份仍留在 LX Backup 下，
 * 如需迁移可手动在 WebDAV 服务器上把 LX Backup 内容合并到 Music Backup）。
 */
export const BACKUP_DIR: string = 'Music Backup';
/** 备份文件名：品牌切割后统一为 music_data_hm.mbak（旧名 lx_data_hm.lxmc 仅恢复时兼容） */
export const BACKUP_FILE: string = 'music_data_hm.mbak';
/** 旧版备份文件名（品牌切割前的 lx 前缀命名），恢复时兼容读取，不再写入 */
export const LEGACY_BACKUP_FILE: string = 'lx_data_hm.lxmc';
/** 备份数据版本号：结构变了 +1（v2 引入可选备份范围与音源） */
const BACKUP_VERSION: number = 2;
const REQUEST_TIMEOUT_MS: number = 20000;

/** 界面刷新用的版本号 key（与 SyncManager.K_SYNC_DATA_VERSION 同一个值，避免跨层 import） */
const K_SYNC_DATA_VERSION: string = 'sync_data_version';

/** 备份内容选择：哪几类数据参与备份 / 恢复（全部为 true 时等价旧版全量备份） */
export interface BackupScope {
  /** 试听列表（本机播放队列） */
  playList: boolean;
  /** 收藏 */
  loveList: boolean;
  /** 歌单 */
  playlists: boolean;
  /** 不喜欢规则 */
  dislike: boolean;
  /** 音源（自建 / 导入的音源脚本） */
  sources: boolean;
}

/** 全量备份范围（旧版行为：除音源外全部数据） */
export const ALL_SCOPE: BackupScope = {
  playList: true,
  loveList: true,
  playlists: true,
  dislike: true,
  sources: false,
};

/** 备份 / 恢复结果 */
export interface WebDavBackupResult {
  ok: boolean;
  message: string;
}

/**
 * WebDAV 备份（对齐安卓版 lx-music-mobile 的 WebDAV 同步方案）
 *
 *   - 远端目录：`Music Backup`（与安卓版完全一致，同一份备份文件夹）
 *   - 文件名：`music_data_hm.mbak`（品牌切割后统一命名；恢复时兼容旧名 `lx_data_hm.lxmc`）
 *   - 账号：复用「WebDAV 云端音乐」的同一套配置（WebDavSettings：url / username / password）
 *
 * 只做协议：MKCOL 建目录、PUT 上传、GET 下载；数据内容由 LocalLibrary 提供
 * （试听列表 / 收藏 / 歌单 / 不喜欢规则）。
 */
export class WebDavBackup {
  private static instance: WebDavBackup | null = null;

  static getInstance(): WebDavBackup {
    if (WebDavBackup.instance === null) {
      WebDavBackup.instance = new WebDavBackup();
    }
    return WebDavBackup.instance;
  }

  /** 把当前音乐库整体备份到 WebDAV */
  async backup(config: WebDavConfig, context?: common.Context): Promise<WebDavBackupResult> {
    if (config.url.length === 0) {
      return { ok: false, message: '还没有配置 WebDAV 服务器，请先在「WebDAV 云端音乐」里填写服务器地址' };
    }
    try {
      const folder: string = await this.ensureBackupDir(config);
      const payload: string = buildBackupPayload(undefined, context);
      const url: string = `${folder}/${encodeURI(BACKUP_FILE)}`;
      const request = http.createHttp();
      try {
        const headers: Record<string, string> = WebDavClient.getInstance().authHeaders(config);
        headers['Content-Type'] = 'application/json; charset=utf-8';
        headers['Accept'] = '*/*';
        const response: http.HttpResponse = await request.request(url, {
          method: http.RequestMethod.PUT,
          header: headers,
          extraData: payload,
          connectTimeout: REQUEST_TIMEOUT_MS,
          readTimeout: REQUEST_TIMEOUT_MS,
        });
        const code: number = response.responseCode;
        if (code >= 200 && code < 300) {
          return { ok: true, message: `已备份到 ${BACKUP_DIR}/${BACKUP_FILE}` };
        }
        return { ok: false, message: backupErrorText(code, '备份') };
      } finally {
        request.destroy();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'backup failed: %{public}s', (e as Error).message);
      return { ok: false, message: `备份失败：${(e as Error).message}` };
    }
  }

  /** 从 WebDAV 读取备份并应用到本地音乐库 */
  async restore(config: WebDavConfig, context?: common.Context): Promise<WebDavBackupResult> {
    if (config.url.length === 0) {
      return { ok: false, message: '还没有配置 WebDAV 服务器，请先在「WebDAV 云端音乐」里填写服务器地址' };
    }
    try {
      const base: string = stripTrailingSlash(config.url);
      // 新名优先，旧名（lx_data_hm.lxmc）404 时兼容读取历史备份
      const candidates: string[] = [BACKUP_FILE, LEGACY_BACKUP_FILE];
      for (const fileName of candidates) {
        const url: string = `${base}/${encodeURI(BACKUP_DIR)}/${encodeURI(fileName)}`;
        const request = http.createHttp();
        try {
          const headers: Record<string, string> = WebDavClient.getInstance().authHeaders(config);
          headers['Accept'] = '*/*';
          const response: http.HttpResponse = await request.request(url, {
            method: http.RequestMethod.GET,
            header: headers,
            connectTimeout: REQUEST_TIMEOUT_MS,
            readTimeout: REQUEST_TIMEOUT_MS,
          });
          const code: number = response.responseCode;
          if (code === 404) {
            continue;
          }
          if (code < 200 || code >= 300) {
            return { ok: false, message: backupErrorText(code, '恢复') };
          }
          const text: string = typeof response.result === 'string' ? response.result : '';
          if (text.length === 0) {
            return { ok: false, message: '恢复失败：备份文件是空的' };
          }
          const applied: number = applyBackupPayload(text, context);
          const label: string = fileName === BACKUP_FILE ? BACKUP_FILE : `${BACKUP_FILE}（旧版 ${LEGACY_BACKUP_FILE}）`;
          return { ok: true, message: `已从备份恢复（${applied} 条数据）` };
        } finally {
          request.destroy();
        }
      }
      return { ok: false, message: `远端还没有备份（${BACKUP_DIR}/${BACKUP_FILE}），请先在鸿蒙版里备份一次` };
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'restore failed: %{public}s', (e as Error).message);
      return { ok: false, message: `恢复失败：${(e as Error).message}` };
    }
  }

  /** 确保远端备份目录存在（MKCOL 逐层建）；@returns 备份目录的 URL */
  private async ensureBackupDir(config: WebDavConfig): Promise<string> {
    const base: string = stripTrailingSlash(config.url);
    const folder: string = `${base}/${encodeURI(BACKUP_DIR)}`;
    await this.mkcol(folder, config);
    return folder;
  }

  /** MKCOL 建目录；已存在（405）不算错 */
  private async mkcol(url: string, config: WebDavConfig): Promise<void> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = WebDavClient.getInstance().authHeaders(config);
      headers['Accept'] = '*/*';
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.POST,
        customMethod: 'MKCOL',
        header: headers,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
      });
      const code: number = response.responseCode;
      if (code === 201 || code === 405) {
        return;
      }
      if (code === 401) {
        throw new Error('用户名或密码不对');
      }
      if (code === 403) {
        throw new Error('账号没有创建目录的权限');
      }
      throw new Error(`创建备份目录失败：服务器返回 HTTP ${code}`);
    } finally {
      request.destroy();
    }
  }
}

// ------------------------------------------------------------------ 数据

/** 构建备份数据：按勾选范围打包；scope 缺省时等价旧版全量（不含音源）。
 *  context 提供时且勾选音源，才把音源索引 + 脚本正文一并打包（脚本可能数 MB）。 */
export function buildBackupPayload(scope?: BackupScope, context?: common.Context): string {
  const library: LocalLibrary = LocalLibrary.getInstance();
  const sc: BackupScope = scope !== undefined && scope !== null ? scope : ALL_SCOPE;
  const ld: LxListData = library.listData();
  const listData: LxListData = { defaultList: [], loveList: [], userList: [] };
  if (sc.playList) {
    listData.defaultList = ld.defaultList;
  }
  if (sc.loveList) {
    listData.loveList = ld.loveList;
  }
  if (sc.playlists) {
    listData.userList = ld.userList;
  }
  const payload: BackupPayload = {
    version: BACKUP_VERSION,
    time: Date.now(),
    type: 'lxmusic_harmony_backup',
    scope: sc,
    listData: listData,
    dislike: sc.dislike ? library.dislikeRules() : '',
  };
  if (sc.sources && context !== undefined && context !== null) {
    const store: SourceStore = new SourceStore();
    store.init(context);
    if (store.isReady()) {
      payload.sources = store.exportBundle();
    }
  }
  return JSON.stringify(payload);
}

/**
 * 解析备份并应用到本地库：按备份时勾选的范围逐类恢复——
 * 勾选过的类别用备份覆盖本地，未勾选的类别保留本地现状；
 * 旧版（v1）备份无 scope 字段，等价全量恢复。
 * @returns 恢复的数据条数（歌单数 + 歌曲数 + 音源数）
 */
export function applyBackupPayload(text: string, context?: common.Context): number {
  const raw: BackupPayload | null = parseBackup(text);
  if (raw === null) {
    throw new Error('备份文件格式不对');
  }
  const library: LocalLibrary = LocalLibrary.getInstance();
  const sc: BackupScope = raw.scope !== undefined && raw.scope !== null ? raw.scope : ALL_SCOPE;
  // 列表逐类合并：备份有的覆盖、备份没有的保留本地现状
  const merged: LxListData = mergeListData(library.listData(), raw.listData, sc);
  library.applyRemoteListData(merged);
  if (typeof raw.dislike === 'string' && sc.dislike) {
    library.applyRemoteDislikeData(raw.dislike);
  }
  let sourceCount: number = 0;
  if (sc.sources && raw.sources !== undefined && raw.sources !== null && context !== undefined && context !== null) {
    const store: SourceStore = new SourceStore();
    store.init(context);
    if (store.isReady()) {
      sourceCount = store.importBundle(raw.sources);
    }
  }
  library.mirrorToSession();
  // 递增版本号，让订阅了它的列表页 / 我的页重新读一次数据
  const version: number = AppStorage.get<number>(K_SYNC_DATA_VERSION) ?? 0;
  AppStorage.setOrCreate(K_SYNC_DATA_VERSION, version + 1);
  const summary: LibrarySummary = library.summary();
  const base: number = summary.playlists + summary.songs;
  return sourceCount > 0 ? base + sourceCount : base;
}

/** 按备份范围合并本地与备份的列表数据：勾选类别取备份值，未勾选保留本地值 */
function mergeListData(current: LxListData, backup: LxListData | undefined | null, sc: BackupScope): LxListData {
  const b: LxListData = backup !== undefined && backup !== null
    ? backup : { defaultList: [], loveList: [], userList: [] };
  return {
    defaultList: sc.playList ? b.defaultList : current.defaultList,
    loveList: sc.loveList ? b.loveList : current.loveList,
    userList: sc.playlists ? b.userList : current.userList,
  };
}

function parseBackup(text: string): BackupPayload | null {
  try {
    const raw = JSON.parse(text) as BackupPayload;
    if (raw === null || raw === undefined || raw.listData === null || raw.listData === undefined) {
      return null;
    }
    return raw;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'parse backup failed: %{public}s', JSON.stringify(e));
    return null;
  }
}

export interface BackupPayload {
  version: number;
  time: number;
  type: string;
  /** v2 起记录本次备份勾选的范围；旧版备份无此字段 */
  scope?: BackupScope;
  /** 按 scope 截取后的列表数据（未勾选的类别为空数组） */
  listData: LxListData;
  dislike?: string;
  /** 音源（索引 + 脚本正文 + 上次加载），勾选音源且提供 context 时才打包 */
  sources?: SourceBundle;
}

// ------------------------------------------------------------------ 工具

/** 401/403/5xx 之类的状态码翻译成人话 */
function backupErrorText(code: number, action: string): string {
  if (code === 401) {
    return `${action}失败：用户名或密码不对`;
  }
  if (code === 403) {
    return `${action}失败：账号没有读写该目录的权限`;
  }
  if (code >= 500) {
    return `${action}失败：服务器出错（HTTP ${code}）`;
  }
  return `${action}失败：服务器返回 HTTP ${code}`;
}

function stripTrailingSlash(url: string): string {
  let text: string = url;
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
