package com.feiniu.music

import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.content.pm.PackageManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.github.proify.lyricon.lyric.model.LyricWord
import io.github.proify.lyricon.lyric.model.RichLyricLine
import io.github.proify.lyricon.lyric.model.Song
import io.github.proify.lyricon.provider.LyriconFactory
import io.github.proify.lyricon.provider.LyriconProvider
import com.feiniu.music.island.IslandLyricNotification
import com.feiniu.music.island.shizuku.ShizukuManager
import com.feiniu.music.track_change.OverlayFloatingIsland
import com.feiniu.music.track_change.OverlayTrackChange
import com.feiniu.music.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.Locale

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.feiniu.music/meizu_lyrics"
    private val lyriconChannelName = "com.feiniu.music/lyricon"
    private val downloadsChannelName = "com.feiniu.music/downloads"
    private val artworkChannelName = "com.feiniu.music/native_artwork"
    private val tvChannelName = "com.feiniu.music/tv"
    private val islandLyricChannelName = "com.feiniu.music/island_lyric"
    private val islandShizukuChannelName = "com.feiniu.music/island_lyric_shizuku"
    private val systemSettingsChannelName = "com.feiniu.music/system_settings"
    private val castVolumeChannelName = "com.feiniu.music/cast_volume"
    private val notificationId = 10010
    private val notificationChannelId = "meizu_lyric_channel"
    private var flagShowTicker: Int? = null
    private var flagUpdateTicker: Int? = null
    private var lyriconProvider: LyriconProvider? = null
    private var lyriconEnabled = false
    private var castVolumeChannel: MethodChannel? = null
    private var castVolumeActive = false

    /**
     * 投屏时拦截物理音量键，转发到 Flutter 侧遥控投屏设备音量。
     * 返回 true 表示已消费（不再走系统音量）；false 交回系统默认行为。
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (castVolumeActive && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            val delta = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
            castVolumeChannel?.invokeMethod("volumeDelta", delta)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkSupport" -> {
                    result.success(checkSupport())
                }
                "updateLyric" -> {
                    val text = call.argument<String>("text") ?: ""
                    updateLyric(text)
                    result.success(null)
                }
                "stopLyric" -> {
                    stopLyric()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            lyriconChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setServiceEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setLyriconEnabled(enabled)
                    result.success(null)
                }
                "setPlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    setLyriconPlaybackState(isPlaying)
                    result.success(null)
                }
                "setSong" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        setLyriconSong(args)
                    }
                    result.success(null)
                }
                "updatePosition" -> {
                    val position = call.argument<Int>("position") ?: 0
                    updateLyriconPosition(position.toLong())
                    result.success(null)
                }
                "setDisplayTranslation" -> {
                    val display = call.argument<Boolean>("display") ?: false
                    setLyriconDisplayTranslation(display)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidSdkInt" -> {
                    result.success(Build.VERSION.SDK_INT)
                }
                "saveToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"
                    val subdirectory = call.argument<String>("subdirectory") ?: "FeiNiuMusic"
                    val overwrite = call.argument<Boolean>("overwrite") ?: false
                    if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("invalid_args", "缺少文件信息", null)
                    } else {
                        try {
                            val savedPath = saveToDownloads(
                                sourcePath = sourcePath,
                                fileName = fileName,
                                mimeType = mimeType,
                                subdirectory = subdirectory,
                                overwrite = overwrite
                            )
                            result.success(savedPath)
                        } catch (t: Throwable) {
                            result.error("save_failed", t.message ?: "保存失败", null)
                        }
                    }
                }
                "existsInDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val subdirectory = call.argument<String>("subdirectory") ?: "FeiNiuMusic"
                    if (fileName.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        try {
                            result.success(downloadFileExists(fileName, subdirectory))
                        } catch (t: Throwable) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            artworkChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadAudioThumbnail" -> {
                    val path = call.argument<String>("path")
                    val size = call.argument<Int>("size") ?: 320
                    if (path.isNullOrBlank()) {
                        result.success(null)
                    } else {
                        try {
                            result.success(loadAudioThumbnail(path, size))
                        } catch (t: Throwable) {
                            result.error("thumbnail_failed", t.message ?: "读取缩略图失败", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            tvChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTvDevice" -> result.success(isTvDevice())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            islandLyricChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val leftLyric = call.argument<String>("leftLyric") ?: ""
                    val lyric = call.argument<String>("lyric") ?: ""
                    val fullLyric = call.argument<String>("fullLyric") ?: lyric
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    // Flutter 的 int 在 Android 端可能编码为 Integer（小值）或 Long（大值），
                    // 必须用 Number 统一读取再转 Long，否则小整数会抛 ClassCastException。
                    val positionMs = (call.argument<Number>("positionMs") as? Number)?.toLong() ?: 0L
                    val durationMs = (call.argument<Number>("durationMs") as? Number)?.toLong() ?: 0L
                    val showProgress =
                        call.argument<Boolean>("showProgress") ?: true
                    val coverPath = call.argument<String>("coverPath")
                    val aodLyrics = call.argument<Boolean>("aodLyrics") ?: false
                    val notificationType =
                        (call.argument<Number>("notificationType") as? Number)?.toInt()
                            ?: IslandLyricNotification.TYPE_FOCUS
                    val bypassFocusLimit =
                        call.argument<Boolean>("bypassFocusLimit") ?: false
                    islandLyricNotification.update(
                        leftLyric = leftLyric,
                        lyric = lyric,
                        fullLyric = fullLyric,
                        title = title,
                        artist = artist,
                        isPlaying = isPlaying,
                        positionMs = positionMs,
                        durationMs = durationMs,
                        showProgressSetting = showProgress,
                        coverPath = coverPath,
                        aodLyrics = aodLyrics,
                        notificationType = notificationType,
                        bypassFocusLimit = bypassFocusLimit
                    )
                    result.success(null)
                }
                "hide" -> {
                    islandLyricNotification.hide()
                    result.success(null)
                }
                "openAodSettings" -> {
                    val ok = openAodSettings()
                    result.success(ok)
                }
                "isHyperOs" -> {
                    result.success(isHyperOs())
                }
                // 查询当前 OS 的灵动岛 / 焦点通知能力，供设置页按设备能力隐藏开关：
                // - supportIsland: persist.sys.feature.island（是否支持岛）
                // - focusProtocol: notification_focus_protocol（1=OS1, 2=OS2, 3=OS3，
                //   OS2/OS3 均支持焦点通知，模板不同）
                // - focusPermission: canShowFocus（应用焦点通知权限是否开启）
                "queryCapabilities" -> {
                    result.success(queryIslandCapabilities())
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            islandShizukuChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAvailable", "requestPermission" -> {
                    // Shizuku 授权探测：必须在后台协程执行，绝不阻塞主线程。
                    // checkShizukuPermission 未授权时会弹出系统授权框并挂起等待
                    // 用户交互，用 runBlocking 堵住主线程会导致授权完成时
                    // （尤其 Sui/root 场景）进程被卡死/闪退。
                    shizukuScope.launch {
                        val granted = ShizukuManager.checkShizukuPermission(packageName)
                        result.success(granted)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.feiniu.music/track_change_overlay"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val coverPath = call.argument<String>("coverPath")
                    val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 3000L
                    val isLarge = call.argument<Boolean>("isLarge") ?: false
                    val scale = call.argument<Double>("scale") ?: 1.0
                    // 颜色为 32 位 ARGB（如 0xFFFFFFFF 超出 Java int 范围），
                    // Flutter 会编码为 Long，必须用 Number 统一读取再转 Int。
                    val isDark = call.argument<Boolean>("isDark") ?: false
                    val cardColor = (call.argument<Number>("cardColor")?.toInt()) ?: 0xFF262A30.toInt()
                    val textColor = (call.argument<Number>("textColor")?.toInt()) ?: Color.WHITE
                    val secondaryColor = (call.argument<Number>("secondaryColor")?.toInt()) ?: 0xFFB0B3B8.toInt()
                    val accentColor = (call.argument<Number>("accentColor")?.toInt()) ?: 0xFF3B82F6.toInt()
                    overlayTrackChange.show(
                        title, artist, coverPath, durationMs, isLarge, scale,
                        isDark, cardColor, textColor, secondaryColor, accentColor
                    )
                    result.success(null)
                }
                "updateCover" -> {
                    val coverPath = call.argument<String>("coverPath")
                    overlayTrackChange.updateCover(coverPath)
                    result.success(null)
                }
                "hide" -> {
                    overlayTrackChange.hide()
                    result.success(null)
                }
                "hasOverlayPermission" -> result.success(overlayTrackChange.hasOverlayPermission())
                "openOverlaySettings" -> result.success(overlayTrackChange.openOverlaySettings())
                "showPermissionToast" -> {
                    overlayTrackChange.showPermissionToast()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.feiniu.music/floating_island"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val lyric = call.argument<String>("lyric") ?: ""
                    val coverPath = call.argument<String>("coverPath")
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 0.75f
                    overlayFloatingIsland.show(
                        title, artist, lyric, coverPath, isPlaying, opacity
                    )
                    result.success(null)
                }
                "update" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val lyric = call.argument<String>("lyric") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 0.75f
                    overlayFloatingIsland.update(
                        title, artist, lyric, isPlaying, opacity
                    )
                    result.success(null)
                }
                "hide" -> {
                    overlayFloatingIsland.hide()
                    result.success(null)
                }
                "hasOverlayPermission" -> result.success(overlayFloatingIsland.hasOverlayPermission())
                "openOverlaySettings" -> result.success(overlayFloatingIsland.openOverlaySettings())
                else -> result.notImplemented()
            }
        }

        // 系统设置跳转通道：直接发真实的 Android 系统 Intent（系统均衡器 / 音质音效）。
        // 不依赖任何第三方包。多候选 + 运行时 Activity 自发现，跨 OEM/版本稳健。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            systemSettingsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSystemEqualizer" -> startFirstSurviving(equalizerCandidates(), result)
                "openMiSoundQuality" -> startFirstSurviving(miSoundCandidates(), result)
                else -> result.notImplemented()
            }
        }

        // DLNA 投屏音量键透传通道：Flutter 侧设置「投屏激活」标志，原生层在
        // onKeyDown 拦截物理音量键并回调 volumeDelta（+1 / -1），由 Flutter 遥控
        // 投屏设备音量。投屏时手机音量条不再调节本机媒体音量。
        val castChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            castVolumeChannelName
        )
        castVolumeChannel = castChannel
        castChannel.setMethodCallHandler { call, _ ->
            when (call.method) {
                "setActive" -> {
                    castVolumeActive = call.argument<Boolean>("active") ?: false
                }
                else -> {}
            }
        }
    }

    /** 本 Activity 是否在前台。用于判断跳转目标是否"站住了"（见 [startFirstSurviving]）。 */
    @Volatile
    private var isForeground: Boolean = true

    /** 最近一次退到后台 / 回到前台的时刻（elapsedRealtime），用于估算目标页面的停留时长。 */
    @Volatile
    private var lastPauseAtMs: Long = 0L

    @Volatile
    private var lastResumeAtMs: Long = 0L

    override fun onResume() {
        super.onResume()
        isForeground = true
        lastResumeAtMs = SystemClock.elapsedRealtime()
    }

    override fun onPause() {
        super.onPause()
        isForeground = false
        lastPauseAtMs = SystemClock.elapsedRealtime()
    }

    /** 单个候选跳转后，等待多久判定目标页面是否留住（毫秒）。 */
    private val probeDelayMs: Long = 1100L

    /**
     * 目标页面停留超过此时长后我们才回到前台的，判定为"用户自己按了返回"而非
     * 启动即闪退——此时应视为跳转成功，不再继续尝试后续候选去打扰用户。
     */
    private val userReturnThresholdMs: Long = 700L

    /**
     * 依次尝试候选 Intent，直到某一个**真正留在前台**为止。
     *
     * 背景：跨 OEM 直达系统音效子页只能靠运行时枚举类名猜测，而猜中的 Activity
     * 可能因缺少前置参数在启动瞬间自行 finish()——用户看到的就是"点一下闪一下
     * 又回到 App"。`startActivity` 此时并不抛异常，无法据此判断成败，旧实现因此
     * 误判成功并终止候选链，永远卡在会闪退的那一个上。
     *
     * 故改为实测：每发起一个候选后等 [probeDelayMs]，若本 Activity 已退到后台，
     * 说明目标页面站住了，成功收尾；若仍在前台，说明目标闪退，继续下一个候选。
     * 候选链末尾放必定能留住的兜底（App 主入口 / 系统设置），保证不会一路闪到底。
     */
    private fun startFirstSurviving(candidates: List<Intent>, result: MethodChannel.Result) {
        // 刻意用 Handler 而非协程：本模块未显式依赖 kotlinx-coroutines-android，
        // Dispatchers.Main 不一定可用（缺失时会抛 "Module with the Main dispatcher
        // had failed to initialize"）。Handler 零依赖且天然在主线程回 result。
        val handler = Handler(Looper.getMainLooper())
        fun step(index: Int) {
            if (index >= candidates.size) {
                runCatching { result.success(false) }
                return
            }
            if (!tryStart(candidates[index])) {
                step(index + 1) // 压根起不来（Activity 不存在 / 被拒），立刻试下一个
                return
            }
            val startedAt = SystemClock.elapsedRealtime()
            handler.postDelayed({
                val survived = if (!isForeground) {
                    // 我们仍在后台 = 目标页面站住了。
                    true
                } else {
                    // 已回到前台：可能是目标闪退，也可能是用户看过页面后自己按了返回。
                    // 用"离开前台的时长"区分——闪退通常只有几百毫秒，人手返回要更久。
                    val leftAt = lastPauseAtMs
                    val stayedMs = lastResumeAtMs - leftAt
                    leftAt >= startedAt && stayedMs >= userReturnThresholdMs
                }
                if (survived) {
                    runCatching { result.success(true) }
                } else {
                    step(index + 1)
                }
            }, probeDelayMs)
        }
        step(0)
    }

    /**
     * 系统均衡器候选链：官方音效面板 → OEM EQUALIZER action → HyperOS「音质音效」
     * App 内的均衡器子页 → 该 App 主入口 → 系统设置内自发现 → 声音设置 / 主设置。
     */
    private fun equalizerCandidates(): List<Intent> {
        val list = mutableListOf<Intent>()
        // 1) Android 官方标准音频效果控制面板（Spotify 同款，非 HyperOS 设备有效）
        list.add(Intent("android.media.action.DISPLAY_AUDIO_EFFECT_CONTROL_PANEL").apply {
            putExtra("android.media.extra.PACKAGE_NAME", packageName)
            putExtra("android.media.extra.CONTENT_TYPE", 0) // MUSIC
        })
        // 2) 部分 OEM 的 EQUALIZER action
        list.add(Intent("android.media.action.EQUALIZER").apply {
            putExtra("android.media.extra.PACKAGE_NAME", packageName)
        })
        // 3) HyperOS：均衡器是「音质音效」App 的内部子页，枚举直达
        list.addAll(
            appActivityCandidates(
                "com.miui.misound",
                listOf("equalizer", "audioeffect", "soundeffect")
            )
        )
        // 4) 兜底：音质音效 App 主入口（必定能留住）
        launchPackageIntent("com.miui.misound")?.let { list.add(it) }
        // 5) 系统设置内自发现
        list.addAll(
            settingsActivityCandidates(
                listOf("equalizer", "soundeffect", "soundquality", "soundenhancement", "misound")
            )
        )
        // 6) 兜底：声音设置 → 主设置
        list.add(Intent(Settings.ACTION_SOUND_SETTINGS))
        list.add(Intent(Settings.ACTION_SETTINGS))
        return list
    }

    /**
     * 小米「音质音效 / Mi Sound」候选链：HyperOS 3.0 的「音质音效」是独立 App
     * (com.miui.misound) 的**内部子页**，直接拉起主入口只会到 App 首页
     * （用户反馈"进入的不是正确的目录"）。故优先枚举该 App 内部 Activity 按
     * 关键字直达目标子页，跳过 LAUNCHER 主页；再回退到 App 主入口 / 系统设置。
     */
    private fun miSoundCandidates(): List<Intent> {
        val list = mutableListOf<Intent>()
        // 1) 枚举 com.miui.misound 内部 Activity，按关键字直达「音质音效」子页
        //    （跳过 LAUNCHER 主页，避免又回到 App 首页）。
        list.addAll(
            appActivityCandidates(
                "com.miui.misound",
                listOf("soundquality", "soundeffect", "quality", "effect")
            )
        )
        // 2) 兜底：直接启动 App 主入口（用户在 App 内手动找音质音效）
        launchPackageIntent("com.miui.misound")?.let { list.add(it) }
        // 3) 系统设置内自发现「音质音效 / 音效」Activity
        list.addAll(
            settingsActivityCandidates(
                listOf("soundquality", "soundenhancement", "misound", "soundeffect")
            )
        )
        // 4) 已知 MIUI action（部分版本有效）
        list.add(Intent("miui.settings.SOUND_QUALITY"))
        // 5) 兜底：声音设置 → 主设置
        list.add(Intent(Settings.ACTION_SOUND_SETTINGS))
        list.add(Intent(Settings.ACTION_SETTINGS))
        return list
    }

    /** 尝试启动给定 Intent，成功返回 true；任何异常（含 Activity 不存在）静默吞掉。 */
    private fun tryStart(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 取某 App 的启动 Activity（launch intent），作为"必定能留住"的兜底候选。
     * 用于 HyperOS 的「音质音效」独立 App（com.miui.misound）。
     */
    private fun launchPackageIntent(pkg: String): Intent? {
        return try {
            packageManager.getLaunchIntentForPackage(pkg)
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * 运行时枚举 com.android.settings 内的 Activity，按关键字生成候选。
     * 跨 MIUI/HyperOS 版本自适应，避免硬编码类名猜错。
     */
    private fun settingsActivityCandidates(keywords: List<String>): List<Intent> =
        appActivityCandidates("com.android.settings", keywords)

    /**
     * 枚举指定包内 **exported** 的 Activity，按关键字匹配**简单类名**，返回按
     * 优先级排序的显式 Intent 候选列表（最多 [maxActivityCandidates] 个）。
     *
     * 用于 HyperOS 把「音质音效 / 均衡器」拆成独立 App(com.miui.misound) 的内部
     * 子页、且各子页类名随版本变化的场景：不硬编码类名，运行时自适应。
     *
     * ⚠️ 必须用**简单类名**匹配。旧实现用完整类名 `ai.name`，而包名
     * `com.miui.mi`**`sound`** 本身就含关键字 "sound"，导致该 App 的每一个
     * Activity 都被判定命中、筛选完全失效，最终随机挑到一个需要前置参数的内部
     * 子页，启动即 finish —— 表现为"点一下闪一下没进页面"。关键字同理不能过短
     * （旧的 "eq" 会误命中 Request / Sequence 之类）。
     *
     * 会跳过明显是 App 主页（类名含 main/splash/launch/home/launcher）的
     * Activity，避免直达变成回首页；主入口另由 [launchPackageIntent] 兜底。
     * 非 exported 的 Activity 启动必被系统拒绝，直接排除。
     *
     * 注意：枚举其它 App 的 Activity 需该包对本应用可见，AndroidManifest 的
     * <queries> 已声明 com.miui.misound 与 com.android.settings。
     */
    private fun appActivityCandidates(pkg: String, keywords: List<String>): List<Intent> {
        return try {
            val pi = packageManager.getPackageInfo(pkg, PackageManager.GET_ACTIVITIES)
            val kw = keywords.map { it.lowercase(Locale.ROOT) }
            val launcherLike = setOf("main", "splash", "launch", "home", "launcher")
            pi.activities
                ?.asSequence()
                ?.filter { it.exported }
                ?.mapNotNull { ai ->
                    // 只看简单类名，避开包名带来的误命中。
                    val simple = ai.name.substringAfterLast('.').lowercase(Locale.ROOT)
                    if (launcherLike.any { simple.contains(it) }) return@mapNotNull null
                    // 命中关键字里排在最前（最具体）的优先。
                    val rank = kw.indexOfFirst { simple.contains(it) }
                    if (rank < 0) null else rank to ai.name
                }
                ?.sortedBy { it.first }
                ?.take(maxActivityCandidates)
                ?.map { (_, name) -> Intent().apply { component = ComponentName(pkg, name) } }
                ?.toList()
                ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
    }

    /** 单个包内最多取几个 Activity 候选，避免全部闪退时一路闪太多次。 */
    private val maxActivityCandidates: Int = 3

    /** 单一实例持有，保证歌词行去重 / 节流状态在多次 MethodChannel 调用间保持。 */
    private val islandLyricNotification: IslandLyricNotification by lazy {
        IslandLyricNotification(applicationContext)
    }

    private val overlayTrackChange: OverlayTrackChange by lazy {
        OverlayTrackChange(applicationContext)
    }

    /** 浮窗灵动岛（官方 LOGO 常驻歌词浮窗）单一实例。 */
    private val overlayFloatingIsland: OverlayFloatingIsland by lazy {
        OverlayFloatingIsland(applicationContext)
    }

    /** Shizuku 授权探测作用域（后台协程，避免阻塞主线程导致授权时闪退）。 */
    private val shizukuScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * 跳转到 MIUI/HyperOS 息屏通知动画设置页（供息屏歌词提示用）。
     * 目标：com.miui.aod/.settings.NotificationAnimationSelectActivity。
     * 返回是否成功发起（目标组件可能不存在，如非小米设备）。
     */
    private fun openAodSettings(): Boolean {
        return try {
            val intent = Intent().apply {
                component = ComponentName(
                    "com.miui.aod",
                    "com.miui.aod.settings.NotificationAnimationSelectActivity"
                )
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // 用户提供的原始 intent 附加参数
                putExtra("REQUEST_PAGE_PREV_REF", "")
                putExtra("FLAG_FROM_RESOURCE_BROWSER", true)
                putExtra("miref", "personalize")
                putExtra("REQUEST_PAGE_REF", "personalize")
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "打开息屏通知设置失败", e)
            false
        }
    }

    /** 是否为 Android TV 设备：uiMode 类型为 TELEVISION，或设备声明 LEANBACK 特性。 */
    private fun isTvDevice(): Boolean {
        val uiMode = resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_TYPE_MASK
        return uiMode == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK)
    }

    /**
     * 是否为 HyperOS/MIUI 设备：MIUI 息屏系统包 [com.miui.aod] 存在即视为小米 HyperOS 系。
     * 用于「息屏通知设置」跳转行仅在 HyperOS 上显示（其它设备该设置项无意义）。
     */
    private fun isHyperOs(): Boolean {
        return try {
            packageManager.getPackageInfo(
                "com.miui.aod",
                0
            ) != null
        } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * 查询当前 OS 的灵动岛 / 焦点通知能力（供设置页按设备能力隐藏开关）。
     *
     * 对齐小米官方文档（dev.mi.com 焦点通知）：
     * - supportIsland: 反射读取 `persist.sys.feature.island`，是否支持岛功能；
     * - focusProtocol: `notification_focus_protocol` 系统设置，1=OS1 焦点通知模板、
     *   2=OS2 焦点通知模板、3=OS3 小米超级岛通知模板。OS2 与 OS3 模板不同，
     *   且只在 OS3 版本上支持岛（岛渲染为 OS3 特有，但 OS2 同样支持焦点通知）；
     * - focusPermission: `canShowFocus`（content provider 调用，耗时操作），
     *   当前应用焦点通知权限是否开启。权限关闭时通知不会以焦点通知/岛形式展示。
     *
     * 任一探测失败按「不支持」处理（安全降级，隐藏对应开关）。
     */
    private fun queryIslandCapabilities(): Map<String, Any> {
        val supportIsland = isSupportIsland("persist.sys.feature.island", false)
        val focusProtocol = try {
            Settings.System.getInt(
                contentResolver,
                "notification_focus_protocol",
                0
            )
        } catch (_: Throwable) {
            0
        }
        val focusPermission = hasFocusPermission()

        val result = HashMap<String, Any>(4)
        result["supportIsland"] = supportIsland
        result["focusProtocol"] = focusProtocol
        result["focusPermission"] = focusPermission
        // Android 版本号：实时通知（实况通知）需 Android 16+，供 Flutter 侧判定
        result["androidSdk"] = Build.VERSION.SDK_INT
        // 焦点通知可用：focusProtocol>=2（OS2/OS3 均支持焦点通知，模板不同）+
        // 应用焦点通知权限开启。岛渲染（supportIsland）是 OS3 特有能力，但
        // OS2 同样能渲染焦点通知，不作为焦点通知可用性的前提。
        result["focusEnabled"] = focusProtocol >= 2 && focusPermission
        return result
    }

    /** 反射读取 SystemProperties 布尔值（小米文档提供的 isSupportIsland 实现）。 */
    private fun isSupportIsland(key: String, defaultValue: Boolean): Boolean {
        return try {
            val clazz = Class.forName("android.os.SystemProperties")
            val method = clazz.getDeclaredMethod("getBoolean", String::class.java, Boolean::class.java)
            val obj = method.invoke(null, key, defaultValue)
            if (obj !is Boolean) {
                defaultValue
            } else {
                obj
            }
        } catch (_: Exception) {
            defaultValue
        }
    }

    /**
     * 查询当前应用是否开启焦点通知权限。
     *
     * 耗时操作。OS1 之前无焦点通知功能的版本返回 false；OS1/OS2/OS3 上权限
     * 关闭返回 false、开启返回 true。
     */
    private fun hasFocusPermission(): Boolean {
        return try {
            val uri = android.net.Uri.parse("content://miui.statusbar.notification.public")
            val extras = Bundle().apply {
                putString("package", packageName)
            }
            val bundle = contentResolver.call(uri, "canShowFocus", null, extras)
            bundle?.getBoolean("canShowFocus", false) ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun loadAudioThumbnail(path: String, size: Int): ByteArray? {
        val uri = findAudioUri(path) ?: return null
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            applicationContext.contentResolver.loadThumbnail(uri, android.util.Size(size, size), null)
        } else {
            MediaStore.Images.Thumbnails.getThumbnail(
                applicationContext.contentResolver,
                uri.lastPathSegment?.toLongOrNull() ?: return null,
                MediaStore.Images.Thumbnails.MINI_KIND,
                null
            )
        } ?: return null
        return java.io.ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 86, output)
            bitmap.recycle()
            output.toByteArray()
        }
    }

    private fun findAudioUri(path: String): Uri? {
        val normalizedPath = java.io.File(path).absolutePath
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection = "${MediaStore.Audio.Media.DATA}=?"
        val selectionArgs = arrayOf(normalizedPath)
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        applicationContext.contentResolver.query(
            collection,
            projection,
            selection,
            selectionArgs,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                return Uri.withAppendedPath(collection, id.toString())
            }
        }
        return null
    }

    private fun saveToDownloads(
        sourcePath: String,
        fileName: String,
        mimeType: String,
        subdirectory: String,
        overwrite: Boolean
    ): String {
        val sourceFile = java.io.File(sourcePath)
        require(sourceFile.exists()) { "源文件不存在" }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveToDownloadsWithMediaStore(sourceFile, fileName, mimeType, subdirectory, overwrite)
        } else {
            saveToDownloadsLegacy(sourceFile, fileName, subdirectory, overwrite)
        }
    }

    private fun downloadFileExists(fileName: String, subdirectory: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val relativePath = Environment.DIRECTORY_DOWNLOADS + "/" + subdirectory
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.DISPLAY_NAME}=?",
                arrayOf("$relativePath/", fileName),
                null
            )?.use { it.moveToFirst() } == true
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            java.io.File(java.io.File(downloadsDir, subdirectory), fileName).exists()
        }
    }

    private fun deleteExistingDownload(fileName: String, relativePath: String) {
        try {
            applicationContext.contentResolver.delete(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.DISPLAY_NAME}=?",
                arrayOf("$relativePath/", fileName)
            )
        } catch (_: Throwable) {
        }
    }

    private fun saveToDownloadsWithMediaStore(
        sourceFile: java.io.File,
        fileName: String,
        mimeType: String,
        subdirectory: String,
        overwrite: Boolean
    ): String {
        val resolver = applicationContext.contentResolver
        val relativePath = Environment.DIRECTORY_DOWNLOADS + "/" + subdirectory
        val actualName: String
        if (overwrite) {
            deleteExistingDownload(fileName, relativePath)
            actualName = fileName
        } else {
            actualName = nextAvailableDisplayName(fileName, relativePath)
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, actualName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("无法创建下载文件")

        resolver.openOutputStream(uri)?.use { output ->
            sourceFile.inputStream().use { input ->
                input.copyTo(output)
            }
        } ?: error("无法写入下载文件")

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    private fun saveToDownloadsLegacy(
        sourceFile: java.io.File,
        fileName: String,
        subdirectory: String,
        overwrite: Boolean
    ): String {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        val targetDir = java.io.File(downloadsDir, subdirectory)
        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }
        val targetFile = if (overwrite) {
            java.io.File(targetDir, fileName)
        } else {
            nextAvailableFile(targetDir, fileName)
        }
        sourceFile.copyTo(targetFile, overwrite = overwrite)
        return targetFile.absolutePath
    }

    private fun nextAvailableDisplayName(fileName: String, relativePath: String): String {
        val resolver = applicationContext.contentResolver
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var candidate = fileName
        var index = 1
        while (true) {
            val cursor = resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.DISPLAY_NAME}=?",
                arrayOf("$relativePath/", candidate),
                null
            )
            val exists = cursor?.use { it.moveToFirst() } == true
            if (!exists) return candidate
            candidate = "$base ($index)$ext"
            index += 1
        }
    }

    private fun nextAvailableFile(dir: java.io.File, fileName: String): java.io.File {
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var candidate = java.io.File(dir, fileName)
        var index = 1
        while (candidate.exists()) {
            candidate = java.io.File(dir, "$base ($index)$ext")
            index += 1
        }
        return candidate
    }

    private fun setLyriconEnabled(enabled: Boolean) {
        lyriconEnabled = enabled
        val provider = ensureLyriconProvider() ?: return
        if (enabled) {
            provider.register()
        } else {
            provider.unregister()
        }
    }

    private fun setLyriconPlaybackState(isPlaying: Boolean) {
        if (!lyriconEnabled) return
        lyriconProvider?.player?.setPlaybackState(isPlaying)
    }

    private fun setLyriconDisplayTranslation(display: Boolean) {
        if (!lyriconEnabled) return
        lyriconProvider?.player?.setDisplayTranslation(display)
    }

    private fun updateLyriconPosition(position: Long) {
        if (!lyriconEnabled) return
        lyriconProvider?.player?.setPosition(position)
    }

    private fun setLyriconSong(args: Map<*, *>) {
        if (!lyriconEnabled) return
        val lyrics = (args["lyrics"] as? List<*>)?.mapNotNull { item ->
            val lineMap = item as? Map<*, *> ?: return@mapNotNull null
            val begin = toLong(lineMap["begin"])
            val end = toLong(lineMap["end"])
            val words = (lineMap["words"] as? List<*>)?.mapNotNull { wordItem ->
                val wordMap = wordItem as? Map<*, *> ?: return@mapNotNull null
                LyricWord(
                    begin = toLong(wordMap["begin"]),
                    end = toLong(wordMap["end"]),
                    text = wordMap["text"] as? String
                )
            }
            RichLyricLine(
                begin = begin,
                end = end,
                text = lineMap["text"] as? String,
                translation = lineMap["translation"] as? String,
                words = words
            )
        } ?: emptyList()
        val song = Song(
            id = args["id"]?.toString(),
            name = args["name"] as? String,
            artist = args["artist"] as? String,
            duration = toLong(args["duration"]),
            lyrics = lyrics
        )
        lyriconProvider?.player?.setSong(song)
    }

    private fun ensureLyriconProvider(): LyriconProvider? {
        if (lyriconProvider == null) {
            lyriconProvider = LyriconFactory.createProvider(this)
        }
        return lyriconProvider
    }

    private fun toLong(value: Any?): Long {
        return when (value) {
            is Long -> value
            is Int -> value.toLong()
            is Double -> value.toLong()
            is Float -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    private fun checkSupport(): Boolean {
        val show = ensureTickerFlags()
        val update = flagUpdateTicker ?: 0
        return show > 0 && update > 0
    }

    private fun ensureTickerFlags(): Int {
        if (flagShowTicker != null && flagUpdateTicker != null) {
            return flagShowTicker ?: 0
        }
        return try {
            val cls = Class.forName("android.app.Notification")
            val showField = cls.getDeclaredField("FLAG_ALWAYS_SHOW_TICKER")
            val updateField = cls.getDeclaredField("FLAG_ONLY_UPDATE_TICKER")
            flagShowTicker = showField.getInt(null)
            flagUpdateTicker = updateField.getInt(null)
            flagShowTicker ?: 0
        } catch (_: Throwable) {
            flagShowTicker = 0
            flagUpdateTicker = 0
            0
        }
    }

    private fun updateLyric(text: String) {
        if (text.isBlank()) return
        if (!checkSupport()) return
        ensureNotificationChannel()
        val builder = NotificationCompat.Builder(this, notificationChannelId)
            .setPriority(Notification.PRIORITY_MAX)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("歌词")
            .setContentText(text)

        builder.setTicker(text)
        val notification = builder.build()
        notification.flags = notification.flags or Notification.FLAG_NO_CLEAR
        val showFlag = flagShowTicker ?: 0
        val updateFlag = flagUpdateTicker ?: 0
        if (showFlag > 0) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                notification.extras.putBoolean("ticker_icon_switch", false)
                notification.extras.putInt("ticker_icon", R.mipmap.ic_launcher)
            }
            notification.flags = notification.flags or showFlag
            notification.flags = notification.flags or updateFlag
        }
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
    }

    private fun stopLyric() {
        if (!checkSupport()) return
        ensureNotificationChannel()
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(notificationChannelId) != null) return
        val channel = NotificationChannel(
            notificationChannelId,
            "Lyric",
            NotificationManager.IMPORTANCE_HIGH
        )
        manager.createNotificationChannel(channel)
    }
}
