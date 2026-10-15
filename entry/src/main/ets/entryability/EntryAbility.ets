import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { window, display } from '@kit.ArkUI';
import { initialize as agConnectInitialize, JsonTypeInfo } from '@hw-agconnect/hmcore';
import { PlaybackService } from '../core/player/PlaybackService';
import { PlaySession, K_OPEN_PLAYER_PENDING } from '../core/player/PlaySession';
import { LocalMusic } from '../core/local/LocalMusic';
import { WebDavLibrary } from '../core/webdav/WebDavLibrary';
import { WebDavSettings } from '../core/webdav/WebDavSettings';
import { AudioCache } from '../core/music/AudioCache';
import { MediaCache } from '../core/music/MediaCache';
import { SyncManager } from '../core/sync/SyncManager';
import { CollectedPlaylists } from '../core/sync/CollectedPlaylists';
import { PlaySettings } from '../core/settings/PlaySettings';
import { AppearanceSettings } from '../core/settings/AppearanceSettings';
import { DownloadSettings } from '../core/download/DownloadSettings';
import { DownloadManager } from '../core/download/DownloadManager';
import { UserAgreement } from '../core/settings/UserAgreement';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /**
   * 逐个安全初始化：任一模块初始化失败只记日志、不阻断应用启动。
   * 侧载 / 低权限 / 系统版本差异环境下，某个模块（如沙箱目录读写、AVSession、
   * 文件索引恢复）抛异常不应表现为「启动即闪退」，否则连日志都来不及抓。
   */
  private safeInit(name: string, fn: () => void): void {
    try {
      fn();
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', '%{public}s init failed: %{public}s', name,
        (e as Error).message === undefined ? JSON.stringify(e) : (e as Error).message);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 防任意拉起：本应用只暴露桌面入口（exported=true 且 skills 仅
    // entity.system.home + ohos.want.action.home，无 uri/自定义 action skill），
    // 隐式拉起已被系统按 skills 匹配挡掉，无需运行时自杀式拦截。
    // 注意：AGC 审核/测试分发拉起应用时 want.action 可能为空或其他值，
    // 若在这里 terminateSelf 会表现为「启动即闪退」并被华为拒审，故只记录不终止。
    if (want.action !== 'ohos.want.action.home') {
      hilog.info(DOMAIN, 'testTag', 'launched with action: %{public}s',
        want.action === undefined ? 'undefined' : want.action);
      // 外部拉起（含通知栏媒体卡冷启动）：标记待直达播放页，Index 在 aboutToAppear 里消费
      AppStorage.setOrCreate(K_OPEN_PLAYER_PENDING, true);
    }
    // AGC 初始化：读取 rawfile 的 agconnect-services.json 并初始化核心 SDK
    // （华为账号授权 auth.signIn 依赖此初始化；失败只记日志，不阻断应用启动）
    try {
      const rawFile: Uint8Array = this.context.resourceManager.getRawFileContentSync('agconnect-services.json');
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const json: JsonTypeInfo = JSON.parse(decoder.decodeToString(rawFile)) as JsonTypeInfo;
      agConnectInitialize(this.context, json);
      hilog.info(DOMAIN, 'testTag', 'AGC initialized');
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'AGC init failed: %{public}s', (e as Error).message);
    }
    // 系统音乐服务（AVSession + 后台播放长时任务）要一个 Ability 的 Context，
    // 这里尽早给它（长时任务必须在应用还处于前台时申请）。
    this.safeInit('PlaybackService', () => { PlaybackService.getInstance().init(this.context); });
    // 播放现场的落盘也要沙箱目录：必须在 seed()（Index 里）之前准备好
    this.safeInit('PlaySession', () => { PlaySession.getInstance().init(this.context); });
    // 本地音乐库：读回导入索引（歌单 / 收藏里本地歌的侧表也挂在它上面），须早于 SyncManager
    this.safeInit('LocalMusic', () => { LocalMusic.getInstance().init(this.context); });
    // 云端音乐库（WebDAV）：同样有自己的索引与歌单侧表，也要早于 SyncManager
    this.safeInit('WebDavLibrary', () => { WebDavLibrary.getInstance().init(this.context); });
    // 同步模块也要 Context：读配置、落音乐库
    this.safeInit('SyncManager', () => { SyncManager.getInstance().init(this.context); });
    // 缓存：元数据（播放地址 / 歌词）与播放缓存都要沙箱目录
    this.safeInit('MediaCache', () => { MediaCache.getInstance().init(this.context); });
    // 播放 / 外观：都要读回上次的选择并早于界面创建，界面用 @StorageLink 订阅它们发布的值
    this.safeInit('PlaySettings', () => { PlaySettings.getInstance().init(this.context); });
    this.safeInit('AppearanceSettings', () => { AppearanceSettings.getInstance().init(this.context); });
    // 首启用户协议：读回同意状态并发布 AppStorage，早于界面创建，
    // 界面第一帧就能拿到「是否要盖协议遮罩」（见 Index 的 K_AGREEMENT_ACCEPTED）
    this.safeInit('UserAgreement', () => { UserAgreement.getInstance().init(this.context); });
    // 重 IO 模块挪到首帧之后分批执行（AGC 上架检验 AppFreeze THREAD_BLOCK_6S）：
    // 下载索引 / 播放缓存对账要读大 JSON、逐项校验文件存在、全目录清扫，量大了能卡主线程
    // 数秒；这批都不参与首帧渲染（下载页 / 缓存设置页才消费），首帧后跑完全来得及。
    // 第一帧拿到的是各自默认值（下载列表空 / 缓存未启用），页面真正展示前早已就绪。
    setTimeout(() => {
      this.safeInit('AudioCache', () => { AudioCache.getInstance().init(this.context); });
      this.safeInit('DownloadManager', () => { DownloadManager.getInstance().init(this.context); });
    }, 0);
    setTimeout(() => {
      this.safeInit('DownloadSettings', () => { DownloadSettings.getInstance().init(this.context); });
      this.safeInit('WebDavSettings', () => { WebDavSettings.getInstance().init(this.context); });
      this.safeInit('CollectedPlaylists', () => { CollectedPlaylists.getInstance().init(this.context); });
    }, 0);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 热启动路径：launchType 为默认 singleton，应用在后台被拉起时走 onNewWant。
    // 与 onCreate 同一策略：隐式拉起由 skills 挡住，这里只记录不终止，
    // 避免 AGC 审核拉起（action 可能为空/非 home）被误杀成启动闪退。
    hilog.info(DOMAIN, 'testTag', 'Ability onNewWant, action: %{public}s',
      want.action === undefined ? 'undefined' : want.action);
    // 通知栏媒体卡 / 系统拉起（热启动）：标记待直达播放页，Index 的 @Watch 会消费
    AppStorage.setOrCreate(K_OPEN_PLAYER_PENDING, true);
    // 热启动无需重复初始化单例；仅记录拉起事件，供问题排查
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    PlaybackService.getInstance().close();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // 深浅模式先定下来（界面颜色已全部迁到资源 token，见 ui/Theme.ets 与
    // resources 下的 base / dark 两份 color.json）：跟随系统，外观设置里选了
    // 「浅色 / 深色」时按存档覆盖。**必须在下面给状态栏定字色之前**，
    // 否则按「覆盖前的模式」算出来的字色会与最终界面不一致。
    try {
      AppearanceSettings.getInstance().applyColorMode(this.context);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    // 洛雪移动端是「内容铺满、状态栏压在内容上」的观感，这里开全屏布局；
    // 具体的安全区留白由页面自己读 AvoidArea 处理（见 pages/Index.ets）。
    // 状态栏字色按当前深浅模式给：启动窗口的底色是深色（dark 那份
    // start_window_background = #000000）时，黑字会整条看不见。
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true);
      // 平板/大屏自动铺满兜底：若启动窗口明显小于屏幕（窗口记忆把上次的小窗/悬浮
      // 尺寸恢复回来了），直接 resize 到屏幕尺寸铺满。真正的窗口模式（全屏/分屏/
      // 悬浮）由 module.json5 的 supportWindowMode 声明；本 SDK 的 window 模块
      // 没有 WindowMode / setWindowMode 可用，只能做尺寸兜底，resize 失败（如已
      // 处于分屏）不阻塞启动。
      try {
        const rect = mainWindow.getWindowProperties().windowRect;
        const dsp = display.getDefaultDisplaySync();
        if (rect.width > 0 && rect.height > 0 &&
          (rect.width < dsp.width * 0.9 || rect.height < dsp.height * 0.9)) {
          mainWindow.resize(dsp.width, dsp.height)
            .then(() => {
              hilog.info(DOMAIN, 'testTag', 'resize to full screen ok');
            })
            .catch((err: BusinessError) => {
              hilog.error(DOMAIN, 'testTag', 'resize to full screen failed. Cause: %{public}s', JSON.stringify(err));
            });
        }
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'resize probe failed. Cause: %{public}s', JSON.stringify(e));
      }
      const dark: boolean = this.isDarkMode();
      mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000',
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to enable full screen layout. Cause: %{public}s',
        JSON.stringify(err));
    }
  }

  /** 当前是不是深色模式（读资源管理器的配置，UI 还没起来时也能用） */
  private isDarkMode(): boolean {
    try {
      return this.context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // 退到后台是「记下停在哪儿」的最好时机：进度只在切歌/退后台时才落盘，
    // 不然每秒写一次文件。force 绕过节流，保证这次一定写上。
    PlaySession.getInstance().persistPlayState(true);
  }
}