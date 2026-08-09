import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services/audio_effects_service.dart';
import '../../app/state/settings_audio_effects_state.dart';
import '../../app/state/settings_state.dart';
import '../../components/index.dart';

/// 音频输出设置页（参考 Salt Player 音频输出页布局）。
///
/// 分区：
///   1. 均衡器预设（9 预设 + 彩色标识徽章）
///   2. 增强（重低音 + 压限器/动态范围）
///   3. 外部音效入口（系统均衡器 / Mi Sound 说明）
///   4. 兼容性提示
///
/// 改完即调用 [AudioEffectsService.instance.applyCurrent] 实时重放。
/// 仅 Android 系统解码（just_audio 引擎）生效。
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

  Future<void> _toggleCompressor(bool value) async {
    await AudioEffectsSettings.setCompressor(value);
    await AudioEffectsService.instance.applyCurrent();
  }

  /// 打开系统均衡器设置（Android Settings → 音效）。
  Future<void> _openSystemEqualizer() async {
    const url = 'package://com.android.settings/.settings.SoundSettingsActivity';
    // 大部分 OEM 的系统均衡器在 SOUND_SETTINGS 里；若打不开则给 toast 提示。
    try {
      // 先尝试通用 ACTION
      if (!await launchUrl(
        Uri.parse('android.settings.SOUND_SETTINGS'),
        mode: LaunchMode.externalApplication,
      )) {
        // 回退：尝试直接打开 EQ intent（部分 OEM 支持）
        if (!await launchUrl(
          Uri.parse(
            'android.settings.EQUALIZER',
          ),
          mode: LaunchMode.externalApplication,
        )) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请前往 系统 → 声音与振动 查找均衡器'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请手动前往系统设置 → 声音'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 打开 Mi Sound 系统音效设置（MIUI/HyperOS → 声音与振动）。
  Future<void> _openMiSoundSettings() async {
    try {
      // 优先尝试 MIUI 音效设置页
      if (!await launchUrl(
        Uri.parse('android.settings.SOUND_SETTINGS'),
        mode: LaunchMode.externalApplication,
      )) {
        // 回退到通用声音设置
        if (!await launchUrl(
          Uri.parse('android.settings.SETTINGS'),
          mode: LaunchMode.externalApplication,
        )) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请前往 系统 → 声音与振动 查找 Mi Sound'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请手动前往系统设置 → 声音'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '音频输出',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      showMiniPlayer: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── 区块 1：均衡器预设 ──
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

          const SizedBox(height: 20),

          // ── 区块 2：增强 ──
          AppSettingSection(
            title: '增强',
            children: [
              // 重低音增强
              ValueListenableBuilder<bool>(
                valueListenable: AudioEffectsSettings.bassBoost,
                builder: (context, bass, _) => _buildSwitchTile(
                  context,
                  icon: Icons.graphic_eq_rounded,
                  iconColor: const Color(0xFFFF5722),
                  title: '重低音增强',
                  subtitle: '提升低频量感与力度',
                  value: bass,
                  onChanged: (v) => _toggleBass(v),
                ),
              ),
              // 压限器 / 动态范围
              ValueListenableBuilder<bool>(
                valueListenable: AudioEffectsSettings.compressor,
                builder: (context, comp, _) => _buildSwitchTile(
                  context,
                  icon: Icons.waves_rounded,
                  iconColor: const Color(0xFF7C4DFF),
                  title: '压限器（动态范围）',
                  subtitle: '控制电平，使音乐响亮的部分更安静、安静的部分更响亮',
                  value: comp,
                  onChanged: (v) => _toggleCompressor(v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 区块 3：外部音效入口 ──
          AppSettingSection(
            title: '外部音效',
            children: [
              _buildExternalFxTile(
                context,
                icon: Icons.android_rounded,
                iconColor: const Color(0xFF4CAF50),
                title: '系统均衡器',
                subtitle: 'Android Audio Effect',
                onTap: _openSystemEqualizer,
              ),
              _buildMiSoundTile(context),
            ],
          ),

          const SizedBox(height: 20),

          // ── 底部兼容性说明 ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '兼容性说明',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• 内置均衡器 + 重低音 + 压限器仅在 Android 系统解码（just_audio '
                  '引擎）播放时生效\n'
                  '• FLAC / DSF / DFF 等走软解引擎的曲目暂不支持内置音效，可使用外部音效\n'
                  '• 已适配 Poweramp Equalizer 等第三方音效处理软件',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.85),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── 当前播放音频信息（实时显示）──
          _buildNowPlayingInfo(context),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 均衡器预设列表项（标题 + 彩色标识徽章 + 选中态）
  // ═══════════════════════════════════════════════════════════════

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.5)
              : Colors.transparent,
        ),
        child: Row(
          children: [
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
                  const SizedBox(height: 2),
                  Text(
                    preset.id == 'off' ? '原始声音' : '10 段均衡器曲线',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
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

  // ═══════════════════════════════════════════════════════════════
  // 开关列表项（重低音 / 压限器）
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: iconColor.withOpacity(0.12),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 外部音效入口列表项
  // ═══════════════════════════════════════════════════════════════

  Widget _buildExternalFxTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: iconColor.withOpacity(0.12),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Mi Sound 入口（MI logo + 跳转系统设置）
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMiSoundTile(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: _openMiSoundSettings,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            // MI logo：橙色方块 + 白色 "mi"
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFFFF6A00), // Xiaomi 橙
              ),
              child: const Center(
                child: Text(
                  'mi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MISOUND',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '小米设备系统级音效',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 当前播放信息栏
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNowPlayingInfo(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          // 封面占位
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          // 歌曲信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前无播放',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '音频解码信息将在此显示',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.play_circle_outline_rounded,
            size: 28,
            color: theme.colorScheme.primary.withOpacity(0.6),
          ),
        ],
      ),
    );
  }
}
