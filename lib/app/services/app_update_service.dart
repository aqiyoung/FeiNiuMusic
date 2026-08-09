import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String? releaseName;
  final String? releaseUrl;
  final String? releaseNotes;
  final bool hasUpdate;
  final bool isCritical;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseName,
    this.releaseUrl,
    this.releaseNotes,
    this.isCritical = false,
  });
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const String releasePageUrl =
      'https://github.com/aqiyoung/FeiNiuMusic/releases/latest';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/aqiyoung/FeiNiuMusic/releases/latest';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

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
    try {
      final response = await _dio.get(
        latestReleaseApiUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'FeiNiuMusic',
          },
        ),
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        return AppUpdateInfo(latestVersion: currentVersion, hasUpdate: false);
      }

      final tagName = (data['tag_name'] as String? ?? '').trim();
      final latestName = tagName.startsWith('v') || tagName.startsWith('V')
          ? tagName.substring(1)
          : tagName;
      final releaseName = data['name'] as String?;
      final body = data['body'] as String?;
      final htmlUrl = data['html_url'] as String?;

      final hasUpdate = _compareVersions(latestName, currentVersion) > 0;
      final isCritical = _isCriticalRelease(body ?? '');
      return AppUpdateInfo(
        latestVersion: latestName,
        hasUpdate: hasUpdate,
        releaseName: releaseName,
        releaseUrl: htmlUrl ?? releasePageUrl,
        releaseNotes: body,
        isCritical: isCritical,
      );
    } catch (e) {
      return AppUpdateInfo(latestVersion: currentVersion, hasUpdate: false);
    }
  }

  String _normalizeVersion(String version) {
    final value = version.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1);
    }
    return value;
  }

  /// 与 sanyelive 一致的 critical 判定: release body 首非空行含
  /// "**P0**" 或 "**critical**" (case-insensitive) → 重要更新, 弹窗强制升级
  /// (不显示"稍后"). 仅在发版时在正文首行显式打标记才生效.
  static bool _isCriticalRelease(String body) {
    final firstLine = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final lower = firstLine.toLowerCase();
    return lower.contains('**p0**') || lower.contains('**critical**');
  }

  int _compareVersions(String a, String b) {
    // Compare only the release part (major.minor.patch); ignore any build or
    // prerelease suffix so maintenance builds (e.g. 1.3.1-2 vs 1.3.1) don't
    // register as a new version.
    List<int> release(String v) {
      var s = _normalizeVersion(v);
      final cut = s.indexOf(RegExp(r'[+\-]'));
      if (cut >= 0) s = s.substring(0, cut);
      return s.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    }

    final left = release(a);
    final right = release(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}
