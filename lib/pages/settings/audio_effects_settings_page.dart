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
              _buildExternalFxTile(
                context,
                icon: Icons.speaker_group_rounded,
                iconColor: const Color(0xFFFF9800),
                title: 'Mi Sound',
                subtitle: '小米设备系统级音效（需 MIUI/HyperOS）',
                onTap: () => _showMiSoundInfo(context),
              ),
              _buildExternalFxTile(
                context,
                icon: Icons.music_note_rounded,
                iconColor: const Color(0xFFE91E63),
                title: 'Salt Player AudioFX',
                subtitle: '第三方 EQ 引擎（需安装 Salt Player）',
                onTap: () => _showSaltFxInfo(context),
              ),
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
  // 信息弹窗
  // ═══════════════════════════════════════════════════════════════

  void _showMiSoundInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.speaker_group_rounded, color: Color(0xFFFF9800)),
            SizedBox(width: 10),
            Text('Mi Sound'),
          ],
        ),
        content: const Text(
          'Mi Sound 是小米设备的系统级音效引擎，通过 DSP 处理提升听感。\n\n'
          '启用方式：\n'
          '1. 进入 系统 → 声音与振动 → 音质音效\n'
          '2. 开启 Mi Sound / 小米音效\n\n'
          '注意：本 App 内置的「Mi Sound」预设是 EQ 曲线近似方案，'
          '跨设备可用。若你的设备支持真 Mi Sound，建议两者配合使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showSaltFxInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.music_note_rounded, color: Color(0xFFE91E63)),
            SizedBox(width: 10),
            Text('Salt Player AudioFX'),
          ],
        ),
        content: const Text(
          'Salt Player 自带的 V3/V4 音效引擎，提供更精细的 EQ 控制。\n\n'
          '使用方式：\n'
          '1. 安装 Salt Player（GitHub/Mirrors 可下载）\n'
          '2. 在 Salt Player 中配置好音效\n'
          '3. 全局生效（作为系统级音效处理）\n\n'
          '本 App 内置均衡器与 Salt Player AudioFX 不冲突，可叠加使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse('https://github.com/Moriafly/SaltPlayerSource'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('前往下载'),
          ),
        ],
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
