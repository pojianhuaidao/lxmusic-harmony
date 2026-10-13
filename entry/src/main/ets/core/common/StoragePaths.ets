import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * 应用数据根目录（沙箱迁移）
 *
 * 需求：应用数据不再落在「兼容数据」私有沙箱（context.filesDir），改放到鸿蒙系统
 * 公共 Download 目录下的 LxMusicData 文件夹 —— 用户可见、可迁移、可参与华为云备份。
 *
 * 公共目录在部分机型 / 版本上受媒体权限约束（READ_MEDIA / WRITE_MEDIA 为受限 ACL，
 * 需上架申请；本工程未申请，运行期由系统决定是否授权）。这里先尝试直接读写公共目录
 * （能建目录即视为可用），失败则回退应用私有目录，保证功能不因权限缺失而崩。
 *
 * 华为账号备份（core/account/HuaweiAccount）把备份文件写在这个根目录下的
 * huawei_backup 子目录，作为「华为远端数据」的端侧镜像，与页面层同一套数据链路。
 */
const PUBLIC_DOWNLOAD_FALLBACK: string = '/storage/Users/currentUser/Download';
const APP_DATA_DIR: string = 'LxMusicData';

let cachedRoot: string = '';

/** 应用数据根目录（公共 Download 优先，失败回退私有沙箱） */
export function storageRootDir(context: common.Context): string {
  if (cachedRoot.length > 0) {
    return cachedRoot;
  }
  // 公共 Download 目录（/storage/Users/currentUser/Download）：先尝试创建数据子目录，
  // 能建即视为可用；失败则回退应用私有沙箱，保证功能不因权限缺失而崩。
  const base: string = PUBLIC_DOWNLOAD_FALLBACK;
  const target: string = `${base}/${APP_DATA_DIR}`;
  try {
    fs.mkdirSync(target);
    fs.accessSync(target);
    cachedRoot = target;
  } catch (e) {
    cachedRoot = context.filesDir;
  }
  return cachedRoot;
}
