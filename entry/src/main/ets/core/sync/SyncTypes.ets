/**
 * 洛雪音乐库的数据类型
 *
 * 与 lx-music-mobile / lx-music-sync-server 的约定逐字对齐：
 *   - 歌曲：`LX.Music.MusicInfoOnline`（id/name/singer/source/interval/meta）；
 *   - 列表：`LX.Sync.List.ListData`（defaultList / loveList / userList）；
 *   - 不喜欢：一整段纯文本规则（每行「歌名@歌手」）。
 * 这些格式同时用于本地音乐库持久化与 WebDAV 备份文件（见 core/webdav/WebDavBackup）。
 * 原「LX 同步协议」在线同步（WebSocket）已下线，连接 / 认证 / 同步方式相关类型已移除。
 */

// ------------------------------------------------------------------ 歌曲

/** 音质大小（LX meta._qualitys 的值，注意没有 type 字段） */
export interface LxQualitySize {
  size: string | null;
  /** 酷狗的音质条目额外带 hash */
  hash?: string;
}

/** 同步用的歌曲 meta（LX.Music.MusicInfoMeta_online） */
export interface LxMusicMeta {
  /** 平台歌曲 ID；咪咕为 copyrightId */
  songId: string | number;
  albumName: string;
  picUrl?: string | null;
  qualitys?: Object[];
  _qualitys?: Record<string, LxQualitySize>;
  albumId?: string | number;
  /** kg */
  hash?: string;
  /** tx */
  strMediaMid?: string;
  id?: string | number;
  albumMid?: string;
  /** mg */
  copyrightId?: string;
  lrcUrl?: string;
  mrcUrl?: string;
  trcUrl?: string;
}

/** 同步用的在线歌曲（LX.Music.MusicInfoOnline） */
export interface LxMusicInfoNew {
  id: string;
  name: string;
  singer: string;
  source: string;
  interval: string | null;
  meta: LxMusicMeta;
}

// ------------------------------------------------------------------ 歌单

/** 歌单信息（LX.List.UserListInfo） */
export interface LxUserListInfo {
  id: string;
  name: string;
  source?: string;
  sourceListId?: string;
  locationUpdateTime: number | null;
}

/** 带歌曲的歌单（LX.List.UserListInfoFull） */
export interface LxUserListInfoFull {
  id: string;
  name: string;
  source?: string;
  sourceListId?: string;
  locationUpdateTime: number | null;
  list: LxMusicInfoNew[];
}

/** 同步的列表数据（LX.Sync.List.ListData） */
export interface LxListData {
  defaultList: LxMusicInfoNew[];
  loveList: LxMusicInfoNew[];
  userList: LxUserListInfoFull[];
}

/** 同步动作（服务端与客户端双向使用，data 按 action 各自解释） */
export interface LxSyncAction {
  action: string;
  data?: Object;
}

/** 歌曲更新动作的载荷（list_music_update） */
export interface LxMusicUpdateItem {
  id: string;
  musicInfo: LxMusicInfoNew;
}

/** list_create 的载荷 */
export interface LxListCreateData {
  position: number;
  listInfos: LxUserListInfo[];
}

/** list_music_add 的载荷 */
export interface LxListMusicAddData {
  id: string;
  musicInfos: LxMusicInfoNew[];
  addMusicLocationType: string;
}

/** list_music_remove 的载荷 */
export interface LxListMusicRemoveData {
  listId: string;
  ids: string[];
}

/** list_music_move 的载荷 */
export interface LxListMusicMoveData {
  fromId: string;
  toId: string;
  musicInfos: LxMusicInfoNew[];
  addMusicLocationType: string;
}

/** list_music_overwrite 的载荷 */
export interface LxListMusicOverwriteData {
  listId: string;
  musicInfos: LxMusicInfoNew[];
}

/** list_music_update_position 的载荷 */
export interface LxListMusicUpdatePositionData {
  listId: string;
  position: number;
  ids: string[];
}

/** list_update_position 的载荷 */
export interface LxListUpdatePositionData {
  position: number;
  ids: string[];
}

/** 不喜欢规则里的一条（dislike_music_add 的条目） */
export interface LxDislikeMusicInfo {
  name: string;
  singer: string;
}

/** 添加歌曲到歌单的位置（LX.AddMusicLocationType） */
export const ADD_MUSIC_TOP: string = 'top';
export const ADD_MUSIC_BOTTOM: string = 'bottom';

/** 洛雪内置收藏列表（loveList）：界面把它当一个内置歌单用，协议上仍是 loveList */
export const LIST_ID_LOVE: string = 'love';
/** 内置收藏歌单的展示名 —— 与官方客户端叫法一致 */
export const LOVE_LIST_NAME: string = '我的收藏';

/** 不喜欢规则的分隔符（与洛雪 SPLIT_CHAR 一致） */
export const DISLIKE_NAME_SEP: string = '@';
export const DISLIKE_NAME_ALIAS: string = '#';
