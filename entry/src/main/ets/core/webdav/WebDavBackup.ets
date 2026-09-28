import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebDavClient } from './WebDavClient';
import { WebDavConfig } from './WebDavTypes';
import { LocalLibrary, LibrarySummary } from '../sync/LocalLibrary';
import { LxListData } from '../sync/SyncTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'WebDavBackup';

/** 与安卓版（lx-music-mobile）同一个远端目录：LX Backup */
export const BACKUP_DIR: string = 'LX Backup';
/** 安卓版备份文件名是 lx_data.lxmc，鸿蒙版加 hm 后缀区分 */
export const BACKUP_FILE: string = 'lx_data_hm.lxmc';
/** 备份数据版本号：结构变了 +1 */
const BACKUP_VERSION: number = 1;
const REQUEST_TIMEOUT_MS: number = 20000;

/** 界面刷新用的版本号 key（与 SyncManager.K_SYNC_DATA_VERSION 同一个值，避免跨层 import） */
const K_SYNC_DATA_VERSION: string = 'sync_data_version';

/** 备份 / 恢复结果 */
export interface WebDavBackupResult {
  ok: boolean;
  message: string;
}

/**
 * WebDAV 备份（对齐安卓版 lx-music-mobile 的 WebDAV 同步方案）
 *
 *   - 远端目录：`LX Backup`（与安卓版完全一致，同一份备份文件夹）
 *   - 文件名：`lx_data_hm.lxmc`（安卓版是 `lx_data.lxmc`，鸿蒙版加 hm 后缀区分）
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
  async backup(config: WebDavConfig): Promise<WebDavBackupResult> {
    if (config.url.length === 0) {
      return { ok: false, message: '还没有配置 WebDAV 服务器，请先在「WebDAV 云端音乐」里填写服务器地址' };
    }
    try {
      const folder: string = await this.ensureBackupDir(config);
      const payload: string = buildBackupPayload();
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
  async restore(config: WebDavConfig): Promise<WebDavBackupResult> {
    if (config.url.length === 0) {
      return { ok: false, message: '还没有配置 WebDAV 服务器，请先在「WebDAV 云端音乐」里填写服务器地址' };
    }
    try {
      const base: string = stripTrailingSlash(config.url);
      const url: string = `${base}/${encodeURI(BACKUP_DIR)}/${encodeURI(BACKUP_FILE)}`;
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
          return { ok: false, message: `远端还没有备份（${BACKUP_DIR}/${BACKUP_FILE}），请先在鸿蒙版里备份一次` };
        }
        if (code < 200 || code >= 300) {
          return { ok: false, message: backupErrorText(code, '恢复') };
        }
        const text: string = typeof response.result === 'string' ? response.result : '';
        if (text.length === 0) {
          return { ok: false, message: '恢复失败：备份文件是空的' };
        }
        const applied: number = applyBackupPayload(text);
        return { ok: true, message: `已从备份恢复（${applied} 条数据）` };
      } finally {
        request.destroy();
      }
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

/** 构建备份数据：与安卓版同目录同账号，文件名带 hm 后缀；内容是鸿蒙版自己的音乐库 */
function buildBackupPayload(): string {
  const library: LocalLibrary = LocalLibrary.getInstance();
  const payload: BackupPayload = {
    version: BACKUP_VERSION,
    time: Date.now(),
    type: 'lxmusic_harmony_backup',
    listData: library.listData(),
    dislike: library.dislikeRules(),
  };
  return JSON.stringify(payload);
}

/** 解析备份并应用到本地库；@returns 恢复的数据条数（歌单数 + 歌曲数） */
function applyBackupPayload(text: string): number {
  const raw: BackupPayload | null = parseBackup(text);
  if (raw === null) {
    throw new Error('备份文件格式不对');
  }
  const library: LocalLibrary = LocalLibrary.getInstance();
  if (raw.listData !== null && raw.listData !== undefined) {
    library.applyRemoteListData(raw.listData);
  }
  if (typeof raw.dislike === 'string') {
    library.applyRemoteDislikeData(raw.dislike);
  }
  library.mirrorToSession();
  // 递增版本号，让订阅了它的列表页 / 我的页重新读一次数据
  const version: number = AppStorage.get<number>(K_SYNC_DATA_VERSION) ?? 0;
  AppStorage.setOrCreate(K_SYNC_DATA_VERSION, version + 1);
  const summary: LibrarySummary = library.summary();
  return summary.playlists + summary.songs;
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

interface BackupPayload {
  version: number;
  time: number;
  type: string;
  listData: LxListData;
  dislike: string;
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
