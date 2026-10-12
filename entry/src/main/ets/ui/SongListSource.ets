import { SongItem } from '../core/player/PlaySession';

/**
 * 空条目哨兵：数据源越界或拿到空项时返回它，避免渲染回调收到 undefined
 * 导致访问 item.name / item.singer 等字段时抛异常（AGC 上报的 anonymous JsCrash）。
 */
export const EMPTY_SONG_ITEM: SongItem = {
  id: '',
  name: '',
  singer: '',
  coverUrl: '',
  art: false,
  source: '',
  quality: '',
  interval: '',
  musicInfoJson: '',
};

/**
 * 歌曲列表的懒加载数据源
 *
 * SongListPane 原来用 `Column + ForEach` 把整列一次性建出来：收藏里几百首时，
 * 每行都要建封面与文字节点，而且**每行的封面解析还会各发一次网络请求**；
 * 列表每次重画又把这些行全建一遍 —— 页面卡住，请求堆多了进程也扛不住（闪退）。
 *
 * 换成 `List + LazyForEach` 之后，只有屏幕上可见的那几行会被创建（含封面解析），
 * 滚动时按需创建、滑出即回收。这类「可能几百上千条」的列表都应该走它。
 */
export class SongListSource implements IDataSource {
  private items: SongItem[] = [];
  private listeners: DataChangeListener[] = [];

  setItems(items: SongItem[]): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): SongItem {
    if (index < 0 || index >= this.items.length) {
      // 数据源在刷新（setItems -> onDataReloaded）期间，框架可能仍按旧
      // totalCount 请求旧索引；越界直接返回哨兵，杜绝 undefined 传进行渲染。
      return EMPTY_SONG_ITEM;
    }
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }
}
