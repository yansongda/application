import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum LogDomain {
  ABILITY = 0,

  UTILS = 1,

  MODELS = 2,

  PAGES = 3,
}

export enum HttpDomain {
  TEST = 'https://application.test.yanda.net.cn',

  PROD = 'https://application.yanda.net.cn',
}

export enum AppEnv {
  TEST = 'test',

  PROD = 'prod',
}

export enum AppPagesName {
  LOGIN = 'login',
  GUIDE = 'guide',
  HOME = 'home',
  INDEX = 'index',
  INDEX_CREATE = 'index/create',
  INDEX_DETAIL = 'index/detail',
  INDEX_EDIT_ISSUER = 'index/edit/issuer',
  INDEX_EDIT_USERNAME = 'index/edit/username',
  USER = 'user',
  USER_DETAIL = 'user/detail',
  USER_DELETE = 'user/delete',
  USER_EDIT_SLOGAN = 'user/edit/slogan',
}

export class App {
  private static _clientId: string | undefined;

  static get clientId(): string {
    if ('undefined' !== typeof App._clientId) {
      return App._clientId;
    }

    const clientId = App.getMetadata('client_id');

    if ('undefined' === typeof clientId) {
      hilog.warn(LogDomain.UTILS, 'utils/app', 'metadata 中不存在 client_id');

      return '';
    }

    App._clientId = clientId

    return clientId;
  }

  private static _version: string | undefined;

  static get version(): string {
    if ('undefined' !== typeof App._version) {
      return App._version;
    }

    const bundleInfo = App.getBundleInfo();

    App._version = bundleInfo.versionName;

    return App._version;
  }

  private static _env: AppEnv | undefined;

  static get env(): AppEnv {
    if ('undefined' !== typeof App._env) {
      return App._env;
    }

    App._env = AppEnv.PROD;

    if (App.getBundleInfo().versionName.length === 0 || App.getMetadata('env') === 'test') {
      App._env = AppEnv.TEST;
    }

    return App._env;
  }

  static getMetadata(name: string, module?: string): string | undefined {
    if (typeof module === 'undefined') {
      module = 'entry';
    }

    const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA
    );

    hilog.info(LogDomain.UTILS, 'utils/app', 'metadata 获取信息: %{public}s',
      JSON.stringify(bundleInfo.appInfo.metadataArray));

    return bundleInfo.appInfo.metadataArray
      .find(item => item.moduleName === module)?.metadata
      .find(metadata => metadata.name === name)?.value;
  }

  static getBundleInfo(): bundleManager.BundleInfo {
    const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
    );

    hilog.info(LogDomain.UTILS, 'utils/app', 'BundleInfo 获取信息: %{public}s', JSON.stringify(bundleInfo));

    return bundleInfo;
  }
}
