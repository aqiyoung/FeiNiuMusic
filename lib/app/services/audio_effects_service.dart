import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../state/settings_audio_effects_state.dart';
import 'player/just_audio_engine.dart';

/// 音效应用服务：把 [AudioEffectsSettings] 的预设 / 重低音开关应用到 just_audio 引擎。
///
/// 仅 Android（ExoPlayer）的 just_audio 引擎支持 AndroidEqualizer /
/// AndroidLoudnessEnhancer；media_kit（FLAC/DSF 软解）一路暂不支持，留待后续。
///
/// PlayerService 在每次激活 just_audio 引擎后调用 [applyCurrent]，并把当前
/// just_audio 引擎设为 [setActiveEngine]，使设置页切换预设 / 重低音时能立即重放。
class AudioEffectsService {
  AudioEffectsService._();
  static final AudioEffectsService instance = AudioEffectsService._();

  /// 当前活跃且支持音效的引擎（仅 just_audio）。media_kit 时为 null。
  JustAudioEngine? _activeEngine;

  /// 重低音增强通过 LoudnessEnhancer 的增益（dB）实现；设备不支持时回退为
  /// 给最低 3 段 EQ 额外叠加低音增益。
  static const double _bassTargetGain = 6.0; // dB
  static const double _bassEqBoost = 5.0; // dB，回退方案用

  /// 记录当前活跃的支持音效的引擎（仅 just_audio）。非 just_audio 引擎传 null。
  void setActiveEngine(JustAudioEngine? engine) => _activeEngine = engine;

  /// 把当前设置应用到活跃引擎（必要时先确保设置已加载）。
  Future<void> applyCurrent() async {
    await AudioEffectsSettings.ensureLoaded();
    final engine = _activeEngine;
    if (engine == null) return;
    await applyTo(engine);
  }

  /// 把当前预设与重低音开关应用到指定 just_audio 引擎。
  ///
  /// 全程 try/catch：音效是增强项，任何平台/设备不支持都应静默跳过，绝不
  /// 影响正常播放。
  Future<void> applyTo(JustAudioEngine engine) async {
    try {
      final preset = AudioEffectsSettings.presetById(
        AudioEffectsSettings.presetId.value,
      );
      final bass = AudioEffectsSettings.bassBoost.value;

      final eq = await engine.androidEqualizer;
      if (eq != null) {
        final bands = eq.bands;
        for (var i = 0; i < bands.length; i++) {
          final gain = preset.gainFor(i, bands.length);
          await bands[i].setGain(gain);
        }
      }

      final loud = await engine.androidLoudnessEnhancer;
      if (loud != null) {
        await loud.setEnabled(bass);
        if (bass) await loud.setTargetGain(_bassTargetGain);
      } else if (bass && eq != null) {
        // 设备无 LoudnessEnhancer（iOS / 桌面）时，回退为给最低 3 段叠加低音。
        final bands = eq.bands;
        for (var i = 0; i < bands.length && i < 3; i++) {
          final base = preset.gainFor(i, bands.length);
          final g = (base + _bassEqBoost).clamp(
            bands[i].minGain,
            bands[i].maxGain,
          );
          await bands[i].setGain(g);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioEffects] apply failed: $e');
      }
    }
  }
}
