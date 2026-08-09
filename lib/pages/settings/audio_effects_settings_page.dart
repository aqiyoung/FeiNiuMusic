import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// 系统设置跳转 MethodChannel（对应 MainActivity.kt 的 system_settings 通道）。
  static const MethodChannel _systemSettings =
      MethodChannel('com.feiniu.music/system_settings');

  /// 打开系统均衡器（Android 标准音频效果控制面板）。
  ///
  /// 通过原生 MethodChannel 发送
  /// [AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL] intent，
  /// 与 Spotify / Google Play Music 相同的实现方式，
  /// 小米 / 三星 / 一加等 OEM 均已适配。仅 Android 平台有效。
  Future<void> _openSystemEqualizer() async {
    if (!Platform.isAndroid) return;
    try {
      await _systemSettings.invokeMethod<bool>('openSystemEqualizer');
    } catch (_) {
      // 静默失败——部分定制 ROM 可能未注册此 intent
    }
  }

  /// 打开 Mi Sound 系统音效设置（MIUI/HyperOS → 声音与振动 → 音质音效）。
  Future<void> _openMiSoundSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _systemSettings.invokeMethod<bool>('openSoundSettings');
    } catch (_) {
      // 静默失败
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
  // Mi Sound 入口（官方 MI logo + 静默跳转系统设置）
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
            // 官方 MI logo（CustomPaint 绘制 simple-icons Xiaomi SVG 路径）
            SizedBox(
              width: 40,
              height: 40,
              child: const _MiLogoPainterWidget(),
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
            play_circle_outline_rounded,
            size: 28,
            color: theme.colorScheme.primary.withOpacity(0.6),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 官方小米 MI logo（基于 simple-icons SVG 路径矢量绘制）
// ═══════════════════════════════════════════════════════════════

/// 小米官方 MI logo 绘制组件。
///
/// 使用 [CustomPainter] 基于 simple-icons 项目的小米 SVG 路径数据绘制，
/// 包含圆角方形背景 + 白色 "mi" 字标。矢量渲染，任意缩放清晰。
class _MiLogoPainterWidget extends StatelessWidget {
  const _MiLogoPainterWidget();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiLogoPainter(),
      size: Size.infinite,
    );
  }
}

class _MiLogoPainter extends CustomPainter {
  // 小米品牌橙（Xiaomi Orange #FF6900）
  static const Color _miOrange = Color(0xFFFF6900);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _miOrange;

    // 将 SVG viewBox (0,0,24,24) 映射到实际尺寸
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);

    // 官方路径：圆角方形背景 + "mi" 字标（来自 simple-icons/xiaomi.svg）
    final path = Path()
      ..addPath(Path()
        ..moveTo(12, 0)
        ..cubicTo(8.016, 0, 4.756, 0.255, 2.493, 2.516)
        ..cubicTo(0.23, 4.776, 0, 8.033, 0, 12.012)
        ..cubicTo(0, 15.992, 0.23, 19.235, 2.494, 21.497)
        ..cubicTo(4.757, 23.77, 8.017, 24, 12, 24)
        ..cubicTo(15.983, 24, 19.243, 23.77, 21.506, 21.509)
        ..cubicTo(23.77, 19.247, 24, 15.99, 24, 12.012)
        ..cubicTo(24, 8.028, 23.767, 4.769, 21.498, 2.508)
        ..cubicTo(19.234, 0.252, 15.978, 0, 12, 0)
        ..close(), Offset.zero)
      ..addPath(Path()
        ..moveTo(4.906, 7.405)
        ..lineTo(10.53, 7.405)
        ..cubicTo(11.999, 7.405, 13.536, 7.473, 14.293, 8.232)
        ..cubicTo(15.039, 8.978, 15.120, 10.465, 15.123, 11.908)
        ..lineTo(15.123, 16.448)
        ..arcToPoint(Offset(14.971, 16.595), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(13.024, 16.595)
        ..arcToPoint(Offset(12.872, 16.447), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(12.872, 11.83)
        ..cubicTo(12.870, 11.024, 12.824, 10.196, 12.408, 9.779)
        ..cubicTo(12.050, 9.419, 11.382, 9.338, 10.688, 9.320)
        ..lineTo(7.158, 9.320)
        ..arcToPoint(Offset(7.007, 9.467), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(7.007, 16.447)
        ..arcToPoint(Offset(6.855, 16.595), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(4.906, 16.595)
        ..arcToPoint(Offset(4.756, 16.447), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(4.756, 7.554)
        ..arcToPoint(Offset(4.906, 7.405), radius: Radius.circular(0.15), clockwise: true)
        ..close(), Offset.zero)
      ..addPath(Path()
        ..moveTo(17.037, 7.405)
        ..lineTo(18.986, 7.405)
        ..arcToPoint(Offset(19.136, 7.555), radius: Radius.circular(0.15), clockwise: true)
        ..lineTo(19.136, 16.447)
        ..arcToPoint(Offset(18.985, 16.595), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(17.037, 16.595)
        ..arcToPoint(Offset(16.886, 16.447), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(16.886, 7.554)
        ..arcToPoint(Offset(17.037, 7.405), radius: Radius.circular(0.15), clockwise: true)
        ..close(), Offset.zero)
      ..addPath(Path()
        ..moveTo(8.92, 10.948)
        ..lineTo(10.966, 10.948)
        ..arcToPoint(Offset(11.116, 11.095), radius: Radius.circular(0.15), clockwise: true)
        ..lineTo(11.116, 16.447)
        ..arcToPoint(Offset(10.966, 16.595), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(8.92, 16.595)
        ..arcToPoint(Offset(8.768, 16.447), radius: Radius.circular(0.15), clockwise: false)
        ..lineTo(8.768, 11.095)
        ..arcToPoint(Offset(8.92, 10.948), radius: Radius.circular(0.15), clockwise: true)
        ..close(), Offset.zero);

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
