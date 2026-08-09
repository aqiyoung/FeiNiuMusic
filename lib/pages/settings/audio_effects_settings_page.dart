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
                  _buildPresetTile(context, preset, currentId),
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

  /// 构建预设列表项：标题 + 标识徽章 + 副标题 + 选中勾。
  Widget _buildPresetTile(
    BuildContext context,
    EqualizerPreset preset,
    String currentId,
  ) {
    final theme = Theme.of(context);
    final isSelected = currentId == preset.id;
    final badgeTag = preset.tag;
    final badgeColor = preset.tagColor;

    return InkWell(
      onTap: () => _selectPreset(preset.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.5)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            // 左侧：名称 + 徽章
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (badgeTag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: badgeColor.withOpacity(0.12),
                            border: Border.all(
                              color: badgeColor.withOpacity(0.5),
                              width: 0.7,
                            ),
                          ),
                          child: Text(
                            badgeTag,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.3,
                              fontWeight: FontWeight.w800,
                              color: badgeColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preset.id == 'off' ? '原始声音' : '音效曲线',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧：选中勾
            if (isSelected)
              Icon(
                Icons.check_rounded,
                size: 22,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
