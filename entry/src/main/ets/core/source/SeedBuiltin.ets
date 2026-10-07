import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SourceInfo } from './LxTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'SeedBuiltin';

/**
 * SeedBuiltin 依赖的 SourceEngine 能力子集（结构接口，避免与 SourceEngine 互相 import 的循环依赖）
 */
interface SeedEngine {
  isPrepared(): boolean;
  listSources(): SourceInfo[];
  importSource(script: string): SourceInfo;
  hasScript(id: string): boolean;
  getScript(id: string): string;
  removeSources(ids: string[]): SourceInfo[];
}

/** 内置音源资产目录（rawfile 下） */
const ASSET_DIR: string = 'lx-builtin-user-api';
/** 已注入音源 id 的记录文件（与 SourceStore 同目录 lx_sources/ 下） */
const SEED_FILE: string = 'builtin_seed.json';

interface BuiltinSource {
  id: string;
  file: string;
  name: string;
}

interface RemovedSource {
  id: string;
  name: string;
  hash: string;
}

/** 内置第三方音源（对应安卓版 seedBuiltin.ts 的 BUILTIN_USER_APIS 最终版，与 assets/lx-builtin-user-api 一致） */
const BUILTIN_SOURCES: BuiltinSource[] = [
  { id: 'qdy', file: 'qdy.js', name: '全豆要[聚合音源]' },
  { id: 'sixyin', file: 'sixyin.js', name: '六音音源' },
  { id: 'flower', file: 'flower.js', name: '野花🌷' },
  { id: 'grass', file: 'grass.js', name: '野草🌾' },
  { id: 'huibq', file: 'huibq.js', name: 'Huibq_lxmusic源' },
  { id: 'kuwo', file: 'kuwo.js', name: 'KuwoDES' },
  { id: 'kxh', file: 'kxh.js', name: 'K×H测试' },
  { id: 'fish', file: 'fish.js', name: 'fish_music' },
  { id: 'gdstudio', file: 'gdstudio.js', name: 'gdstudio音乐源' },
  { id: 'ikun', file: 'ikun.js', name: 'ikun音源（中国香港服务器)' },
  { id: 'monster', file: 'monster.js', name: 'monster' },
  { id: 'cloud', file: 'cloud.js', name: '云端音源(免费版)' },
  { id: 'qdoya', file: 'qdoya.js', name: '全豆要' },
  { id: 'collect', file: 'collect.js', name: '收集の聚合接口(LX版)' },
  { id: 'lxmusic', file: 'lxmusic.js', name: '洛雪音乐源' },
  { id: 'xinghai', file: 'xinghai.js', name: '星海音乐源' },
  { id: 'ynx', file: 'ynx.js', name: 'lx-玉宁熙-Pro' },
  { id: 'yuxi', file: 'yuxi.js', name: '屿溪-终章' },
  { id: 'changqing', file: 'changqing.js', name: '长青SVIP音源(二改修复版)' },
  { id: 'jiexiang', file: 'jiexiang.js', name: '杰翔聚合音源' },
  { id: 'molan', file: 'molan.js', name: '墨澜聚合音源' },
  { id: 'hyw', file: 'hyw.js', name: 'HYWmusic_beta_公益测试' },
  { id: 'juhe', file: 'juhe.js', name: '聚合API接口 (CF)' },
  { id: 'juheapi', file: 'juheapi.js', name: '聚合API接口' },
  { id: 'hires', file: 'hires.js', name: '聚合Hi-Res音乐音源v1.0' },
  { id: 'suyin', file: 'suyin.js', name: '溯音音源' },
  { id: 'wuming', file: 'wuming.js', name: '無名' },
  { id: 'lx', file: 'lx.js', name: '独家音源' },
  { id: 'stable', file: 'stable.js', name: '稳定版音源 v1.0.3' },
];

/**
 * 已下线内置源（资产文件已删除，不再注入）。
 * 旧版升级设备上可能残留已注入项（存储 id 为 user_api_xxx 随机 id，无法按内置固定 id 直接匹配），
 * 故启动时按「id 精确匹配」或「脚本内容 hash 匹配」或「name 匹配」清理残留，不误删用户自建源。
 */
const REMOVED_SOURCES: RemovedSource[] = [
  // 2026-10-07 用户重新提供 ikun / juhe(聚合API接口 CF) / lx(独家音源) 新版文件，
  // 已从下线名单移除并在 BUILTIN_SOURCES 重新启用；后续再下线时在此追加条目。
];

/**
 * FNV-1a 32 位哈希（纯 JS，用于脚本内容一致性标识；非加密用途）。
 * 与安卓版 seedBuiltin.ts 完全一致，保证跨端哈希值可复用。
 */
function fnv1a32(input: string): string {
  let h: number = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16);
}

/**
 * 规范化音源名称：去除 emoji / 符号区 / 变体选择符 / 零宽连接符 / 首尾空白并小写，用于「同名即重复」判定。
 * 范围与安卓版 seedBuiltin.ts 的 normalizeName 一致（1F000-1FAFF、2600-27BF、FE0F、200D）；
 * 另加 toLowerCase 兜底大小写变体。用 codePointAt 逐字符扫描（ArkTS 正则对 \u{...} 转义支持不稳定，避开正则）。
 */
function normalizeName(s: string): string {
  let out = '';
  let i = 0;
  while (i < s.length) {
    const code: number = s.codePointAt(i) as number;
    if ((code >= 0x1F000 && code <= 0x1FAFF) || (code >= 0x2600 && code <= 0x27BF)) {
      i += code > 0xFFFF ? 2 : 1;
      continue;
    }
    if (code >= 0xFE00 && code <= 0xFE0F) {
      i += 1;
      continue;
    }
    if (code === 0x200D) {
      i += 1;
      continue;
    }
    out += s[i];
    i += 1;
  }
  return out.trim().toLowerCase();
}

/**
 * 内置音源注入（对应安卓版 src/core/userApi/seedBuiltin.ts 的鸿蒙移植）
 *
 * 启动时读取 rawfile/lx-builtin-user-api/ 下的第三方音源脚本并写入 SourceStore：
 *   - 已注入的音源 id 持久化于 lx_sources/builtin_seed.json
 *   - 用户手动删除某内置音源后，其 id 仍在 seeded 记录中，下次启动不再注入（防“幽灵音源”复活）
 *   - 注入前按「脚本 hash / 规范化 name」与已有列表去重，避免与用户手动导入的同名源重复
 *   - 同步执行（rawfile 与文件 IO 均为同步 API），必须在 restoreLastSource 之前完成
 */
export class SeedBuiltin {
  private static instance: SeedBuiltin | null = null;

  static getInstance(): SeedBuiltin {
    if (SeedBuiltin.instance === null) {
      SeedBuiltin.instance = new SeedBuiltin();
    }
    return SeedBuiltin.instance;
  }

  private seeded: string[] = [];
  private seededLoaded: boolean = false;
  private seededChanged: boolean = false;

  private seedFilePath(context: common.Context): string {
    return `${context.filesDir}/lx_sources/${SEED_FILE}`;
  }

  private loadSeeded(context: common.Context): void {
    if (this.seededLoaded) {
      return;
    }
    this.seededLoaded = true;
    try {
      const path: string = this.seedFilePath(context);
      if (!fs.accessSync(path)) {
        return;
      }
      const text: string = fs.readTextSync(path);
      const parsed: object = JSON.parse(text);
      const arr: string[] = parsed as string[];
      if (Array.isArray(arr)) {
        this.seeded = arr;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'failed to load builtin seed: %{public}s', JSON.stringify(e));
    }
  }

  private saveSeeded(context: common.Context): void {
    if (!this.seededChanged) {
      return;
    }
    try {
      const path: string = this.seedFilePath(context);
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(this.seeded));
      } finally {
        fs.closeSync(file);
      }
      this.seededChanged = false;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'failed to save builtin seed: %{public}s', JSON.stringify(e));
    }
  }

  private markSeeded(id: string): void {
    if (!this.seeded.includes(id)) {
      this.seeded.push(id);
      this.seededChanged = true;
    }
  }

  private readRawScript(context: common.Context, file: string): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(context.resourceManager.getRawFileContentSync(`${ASSET_DIR}/${file}`));
  }

  private scriptHashOf(engine: SeedEngine, id: string): string {
    try {
      if (!engine.hasScript(id)) {
        return '';
      }
      return fnv1a32(engine.getScript(id));
    } catch (e) {
      return '';
    }
  }

  /**
   * 启动时注入内置音源（同步）。调用方：SourceEngine.prepare()
   */
  seed(context: common.Context, engine: SeedEngine): void {
    if (!engine.isPrepared()) {
      return;
    }
    this.loadSeeded(context);

    const list: SourceInfo[] = engine.listSources();

    // === 清理已下线内置源在旧版升级设备上的残留注入项 ===
    const removedIds: string[] = [];
    if (list.length > 0) {
      for (let i = list.length - 1; i >= 0; i--) {
        const item: SourceInfo = list[i];
        const hash: string = this.scriptHashOf(engine, item.id);
        const nameNorm: string = normalizeName(item.name);
        let hit: boolean = false;
        for (const r of REMOVED_SOURCES) {
          if (r.id === item.id || r.hash === hash || normalizeName(r.name) === nameNorm) {
            hit = true;
            break;
          }
        }
        if (hit) {
          removedIds.push(item.id);
          list.splice(i, 1);
        }
      }
      if (removedIds.length > 0) {
        engine.removeSources(removedIds);
        hilog.info(DOMAIN, TAG, 'removed %{public}d obsolete builtin source(s)', removedIds.length);
      }
    }

    // === 注入内置音源（与安卓版 seedBuiltin.ts 行为一致：同名项按「内置脚本 hash 优先」清理，再注入内置版） ===
    // 不依赖 builtin_seed.json 记录跳过注入：以 store 实际内容为准增量补齐缺失的内置源，
    // 修复「升级覆盖安装后 App 看不到新集成内置音源」问题（旧逻辑 seeded 命中即 continue，
    // 一旦 seeded 记录与实际 store 数据不一致或源数达到 MAX_USER_API，新源将永久缺失）。
    for (const item of BUILTIN_SOURCES) {
      try {
        const script: string = this.readRawScript(context, item.file);
        if (script.trim().length === 0) {
          hilog.warn(DOMAIN, TAG, 'builtin source %{public}s is empty (rawfile mocked?)', item.id);
          continue;
        }
        const hash: string = fnv1a32(script);
        // 同名项：normalizeName 与内置 @name 一致的历史项（网络版 / 旧版 / 用户自建同名项）
        const sameNameIds: string[] = [];
        let alreadyBuiltin: boolean = false;
        for (const existing of list) {
          if (normalizeName(existing.name) !== normalizeName(item.name)) {
            continue;
          }
          if (this.scriptHashOf(engine, existing.id) === hash) {
            // 已存在内容与内置资产一致的项（历史注入的内置版 / 用户自建同内容项）：标记 seeded，不重复注入（防“幽灵音源”复活）
            alreadyBuiltin = true;
            continue;
          }
          sameNameIds.push(existing.id);
        }
        if (alreadyBuiltin) {
          // 内置版已存在，但残留了同名网络版：删掉冗余项，保留内置版
          if (sameNameIds.length > 0) {
            engine.removeSources(sameNameIds);
            for (const rid of sameNameIds) {
              const idx: number = list.findIndex((li: SourceInfo) => li.id === rid);
              if (idx >= 0) {
                list.splice(idx, 1);
              }
            }
            hilog.info(DOMAIN, TAG, 'removed %{public}d duplicate network source(s) of %{public}s', sameNameIds.length, item.id);
          }
          this.markSeeded(item.id);
          continue;
        }
        // 本地缺失（升级不重种子 / seeded 记录与实际数据不一致 / store 数据丢失）：增量补齐内置版，不设数量上限
        // 存在同名项但内容与内置不一致（网络版）：删除后注入内置版（内置优先，与安卓一致）
        if (sameNameIds.length > 0) {
          engine.removeSources(sameNameIds);
          for (const rid of sameNameIds) {
            const idx: number = list.findIndex((li: SourceInfo) => li.id === rid);
            if (idx >= 0) {
              list.splice(idx, 1);
            }
          }
          hilog.info(DOMAIN, TAG, 'replaced %{public}d network source(s) with builtin %{public}s', sameNameIds.length, item.id);
        }
        const info: SourceInfo = engine.importSource(script);
        list.push(info);
        this.markSeeded(item.id);
        hilog.info(DOMAIN, TAG, 'seeded builtin source: %{public}s', item.id);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'seed builtin user api failed %{public}s: %{public}s', item.id, JSON.stringify(e));
      }
    }

    this.saveSeeded(context);
  }

  /** 已注入的内置音源 id（供默认源回退使用） */
  isSeeded(id: string): boolean {
    return this.seeded.includes(id);
  }
}
