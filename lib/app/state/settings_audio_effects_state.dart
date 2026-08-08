import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音效预设（均衡器曲线）。每条预设是一组按频段从低到高排列的增益（dB），
/// 数量写 10 段以适配大多数设备。
///
/// 实际频段数由 ExoPlayer 的 AndroidEqualizer 决定（通常 5–10 段），应用时
/// 按索引比例映射到真实频段，因此 10 段预设可通用。
class EqualizerPreset {
  const EqualizerPreset(this.id, this.name, this.gains);

  final String id;
  final String name;
  final List<double> gains;

  /// 取第 [bandIndex] 段（共 [bandCount] 段）的增益，按索引比例映射以适配
  /// 不同设备的频段数。
  double gainFor(int bandIndex, int bandCount) {
    if (bandCount <= 0) return 0;
    if (bandIndex < 0 || bandIndex >= bandCount) return 0;
    if (bandCount == gains.length) return gains[bandIndex];
    final t = bandCount <= 1 ? 0.0 : bandIndex / (bandCount - 1);
    final idx = (t * (gains.length - 1)).round().clamp(0, gains.length - 1);
    return gains[idx];
  }
}

/// 音效设置：均衡器预设 + 重低音增强开关。
///
/// 仅 Android 系统解码（just_audio 引擎）播放时生效；media_kit（FLAC/DSF
/// 软解）一路暂不支持。UI 修改后需由 [AudioEffectsService] 应用到引擎。
class AudioEffectsSettings {
  static const String _prefsPreset = 'audio_effects_preset';
  static const String _prefsBass = 'audio_effects_bass_boost';

  static const String defaultPresetId = 'off';

  static final ValueNotifier<String> presetId = ValueNotifier(defaultPresetId);
  static final ValueNotifier<bool> bassBoost = ValueNotifier(false);

  /// 内置均衡器预设目录。
  static const List<EqualizerPreset> presets = [
    EqualizerPreset('off', '关闭', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqualizerPreset('pop', '流行', [-2, 0, 2, 4, 4, 2, 0, -1, -1, -2]),
    EqualizerPreset('rock', '摇滚', [5, 4, 3, 2, 0, -1, -2, -2, 0, 3]),
    EqualizerPreset('classical', '古典', [0, 0, 0, 0, 0, 0, -1, -1, -2, -3]),
    EqualizerPreset('vocal', '人声', [-2, -1, 1, 3, 4, 4, 3, 2, 1, -1]),
    EqualizerPreset('dance', '舞曲', [4, 4, 2, 0, 0, -1, -2, -2, 0, 2]),
    EqualizerPreset('bass', '重低音', [7, 6, 4, 2, 0, -1, -2, -3, -3, -3]),
    EqualizerPreset('bright', '明亮', [-3, -3, -2, -1, 0, 1, 3, 5, 6, 7]),
  ];

  /// 按 id 取预设；未知 id 回落到关闭（首项）。
  static EqualizerPreset presetById(String id) =>
      presets.firstWhere((p) => p.id == id, orElse: () => presets.first);

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsPreset);
    presetId.value =
        stored != null && presets.any((p) => p.id == stored)
            ? stored
            : defaultPresetId;
    bassBoost.value = prefs.getBool(_prefsBass) ?? false;
  }

  static Future<void> setPreset(String id) async {
    if (!presets.any((p) => p.id == id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPreset, id);
    presetId.value = id;
  }

  static Future<void> setBassBoost(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsBass, enabled);
    bassBoost.value = enabled;
  }
}
