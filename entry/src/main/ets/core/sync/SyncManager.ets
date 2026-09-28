import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalLibrary } from './LocalLibrary';
import { SyncStore } from './SyncStore';
import { PlaySession } from '../player/PlaySession';

const DOMAIN: number = 0x0001;
const TAG: string = 'SyncManager';

/** 音乐库数据（歌单/收藏/规则）的版本号，界面据此重新读一次 */
export const K_SYNC_DATA_VERSION: string = 'sync_data_version';

/**
 * 同步模块的对外门面（精简版）
 *
 * 原「LX 同步协议」在线同步（WebSocket 长连接）已下线，同步/备份能力改为
 * WebDAV 方案（见 core/webdav/WebDavBackup，与安卓版 lx-music-mobile 对齐）。
 * 这里保留 LocalLibrary（本地音乐库）的初始化与界面出口，以及数据版本号通知：
 * 界面（主页 / 设置页）仍通过它拿本地库、监听数据变化。
 */
export class SyncManager {
  private static instance: SyncManager | null = null;

  static getInstance(): SyncManager {
    if (SyncManager.instance === null) {
      SyncManager.instance = new SyncManager();
    }
    return SyncManager.instance;
  }

  private store: SyncStore = new SyncStore();
  private library: LocalLibrary = LocalLibrary.getInstance();
  private inited: boolean = false;

  /** 在 EntryAbility.onCreate 里调用：准备存储并接上界面的音乐库出口 */
  init(context: common.Context): void {
    if (this.inited) {
      return;
    }
    this.inited = true;
    this.store.init(context);
    this.library.init(context);
    PlaySession.getInstance().setLibrarySink(this.library);

    // 已经落过库就先镜像到界面（收藏 / 试听列表），没落过库就什么都不铺、界面是空的
    if (this.library.isInitialized()) {
      this.library.mirrorToSession();
    }
    hilog.info(DOMAIN, TAG, 'sync manager inited');
  }

  isInited(): boolean {
    return this.inited;
  }

  getLibrary(): LocalLibrary {
    return this.library;
  }

  /** 数据发生变化（备份恢复 / 本地库加载）时递增，界面据此刷新 */
  bumpDataVersion(): void {
    const version: number = AppStorage.get<number>(K_SYNC_DATA_VERSION) ?? 0;
    AppStorage.setOrCreate(K_SYNC_DATA_VERSION, version + 1);
  }
}
