import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_core.dart';

/// 飞牛音乐的更新检查 —— 检测逻辑全部委托统一引擎 [AppUpdateCore]
/// (lib/app/services/app_update_core.dart, sanyelive / FeiNiuMusic / synapse 共用).
///
/// v1.x 之前这里是直连 api.github.com 的单路径实现: 有 VPN / 海外网络能用,
/// 但国内移动宽带直连被墙时会静默判定"已是最新". 换成统一引擎后自动获得
/// [gh-proxy 代理 → 直连 → jsDelivr meta] 三层可达路径.

class AppUpdateInfo {
  final String latestVersion;
  final String? releaseName;
  final String? releaseUrl;
  final String? releaseNotes;
  final bool hasUpdate;
  final bool isCritical;

  /// 所有数据源都失败 (网络不可达) —— 与"已是最新"区分开, 手动检查时可提示用户.
  final bool failed;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseName,
    this.releaseUrl,
    this.releaseNotes,
    this.isCritical = false,
    this.failed = false,
  });
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const AppUpdateConfig config = AppUpdateConfig(
    owner: 'aqiyoung',
    repo: 'FeiNiuMusic',
    // 仓库没有 meta 分支, 关掉 jsDelivr 兜底避免无谓等待.
    useMetaFallback: false,
  );

  /// 统一更新引擎实例 —— 检测 + 跳转发布页都用它, 保证与另两个 App 行为一致.
  static final AppUpdateCore core = AppUpdateCore(config);

  /// 保持 const —— 调用方有 `const ClipboardData(text: releasePageUrl)` 的用法.
  static const String releasePageUrl =
      'https://github.com/aqiyoung/FeiNiuMusic/releases/latest';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  /// 把 Dio 适配成引擎需要的取数函数; 非 200 全放行, 由引擎切换下一条路径.
  AppUpdateFetch get _fetch => (url, headers) async {
        final resp = await _dio.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 10),
            headers: headers,
            validateStatus: (_) => true,
          ),
        );
        return AppUpdateHttpResponse(
          resp.statusCode ?? 0,
          resp.data?.toString() ?? '',
        );
      };

  String? _cachedVersion;

  /// The running app's clean release version (e.g. "1.3.1"), read from the
  /// platform. The build number is intentionally omitted — it's only a
  /// maintenance counter and shouldn't appear in the displayed version or
  /// affect update comparison.
  Future<String> currentVersion() async {
    final cached = _cachedVersion;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      _cachedVersion = v.isEmpty ? '0.0.0' : v;
      return _cachedVersion!;
    } catch (_) {
      return _cachedVersion ?? '0.0.0';
    }
  }

  Future<AppUpdateInfo> checkLatest(String currentVersion) async {
    final result = await core.check(_fetch, currentVersion);
    if (result == null) {
      // 全部数据源失败 → 不谎报"已是最新".
      return AppUpdateInfo(
        latestVersion: currentVersion,
        hasUpdate: false,
        failed: true,
      );
    }
    return AppUpdateInfo(
      latestVersion: result.latestVersion,
      hasUpdate: result.hasUpdate,
      releaseName: result.releaseName,
      releaseUrl: result.releaseUrl,
      releaseNotes: result.releaseNotes,
      isCritical: result.isCritical,
    );
  }
}
