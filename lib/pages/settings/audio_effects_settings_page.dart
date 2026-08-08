import 'package:flutter/material.dart';

import '../../app/services/audio_effects_service.dart';
import '../../app/state/settings_audio_effects_state.dart';
import '../../app/state/settings_state.dart';
import '../../components/index.dart';

/// 音效设置页：均衡器预设 + 重低音增强开关。
///
/// 改完即调用 [AudioEffectsService.instance.applyCurrent] 实时重放到当前播放，
/// 无需重启播放器。仅 Android 系统解码（just_audio 引擎）生效。
class AudioEffectsSettingsPage extends StatefulWidget {
  const AudioEffectsSettingsPage({super.key});

  @override
  State<AudioEffectsSettingsPage> createState() =>
      _AudioEffectsSettingsPageState();
}

class _AudioEffectsSettingsPageState extends State<AudioEffectsSettingsPage> {
  @override
  void initState() {
    super.initState();
    AudioEffectsSettings.ensureLoaded();
  }

  Future<void> _selectPreset(String id) async {
    await AudioEffectsSettings.setPreset(id);
    await AudioEffectsService.instance.applyCurrent();
  }

  Future<void> _toggleBass(bool value) async {
    await AudioEffectsSettings.setBassBoost(value);
    await AudioEffectsService.instance.applyCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '音效',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      showMiniPlayer: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ValueListenableBuilder<String>(
            valueListenable: AudioEffectsSettings.presetId,
            builder: (context, currentId, _) => AppSettingSection(
              title: '均衡器预设',
              children: [
                for (final preset in AudioEffectsSettings.presets)
                  AppSettingTile(
                    title: preset.name,
                    subtitle: preset.id == 'off' ? '原始声音' : '音效曲线',
                    trailing: currentId == preset.id
                        ? const Icon(Icons.check_rounded, size: 20)
                        : null,
                    onTap: () => _selectPreset(preset.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsSettings.bassBoost,
            builder: (context, bass, _) => AppSettingSection(
              title: '增强',
              children: [
                AppSettingTile(
                  title: '重低音增强',
                  subtitle: '提升低频量感与力度',
                  trailing: Switch.adaptive(
                    value: bass,
                    onChanged: (value) {
                      _toggleBass(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '音效仅在 Android 系统解码（just_audio 引擎）播放时生效；FLAC / DSF '
              '等走软解引擎的曲目暂不支持。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
