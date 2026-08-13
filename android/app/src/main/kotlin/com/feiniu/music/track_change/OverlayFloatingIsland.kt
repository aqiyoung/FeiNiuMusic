package com.feiniu.music.track_change

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * 桌面歌词浮窗。
 *
 * 取代原「浮窗灵动岛」胶囊，改为屏幕底部居中的桌面歌词横条：大号居中歌词
 * （跑马灯）+ 次要色的歌名·歌手 + 关闭按钮。整体半透明，透明度由 [opacity]
 * （0.0~1.0）控制。
 *
 * 交互：
 * - 拖动：手指按住浮窗可移动位置（更新 [WindowManager] 布局参数 x/y）。
 * - 双击：锁定 / 解锁。锁定后禁止拖动并隐藏关闭按钮，避免误触；再次双击解锁。
 * - 单击关闭按钮：隐藏浮窗。
 *
 * 完全绕开系统通知链路，稳定可靠、零白名单依赖。所有 [WindowManager] 操作均
 * try/catch：权限被撤销 / Activity 销毁时不崩溃。
 */
class OverlayFloatingIsland(private val context: Context) {

    companion object {
        private const val TAG = "OverlayFloatingIsland"
        /** 双击判定窗口（毫秒）。 */
        private const val DOUBLE_TAP_MS = 300L
        /** 触发拖动的位移阈值（像素）。 */
        private const val DRAG_THRESHOLD_PX = 6
    }

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var lyricView: TextView? = null
    private var subView: TextView? = null
    private var closeView: View? = null
    private var lockIndicator: View? = null
    private var wmParams: WindowManager.LayoutParams? = null
    private var barWidth = 0
    private var locked = false

    // 拖动 / 双击状态
    private var dragging = false
    private var lastTouchX = 0f
    private var lastTouchY = 0f
    private var downX = 0f
    private var downY = 0f
    private var lastTapTime = 0L

    fun hasOverlayPermission(): Boolean = Settings.canDrawOverlays(context)

    fun openOverlaySettings(): Boolean = try {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        android.util.Log.w(TAG, "打开悬浮窗权限设置失败", e)
        false
    }

    /**
     * 显示 / 刷新桌面歌词。视图首次创建，后续 update 在原视图上就地刷新文本、
     * 透明度与锁定态，不重建窗口（保留拖动位置、不闪烁）。
     */
    fun show(
        title: String,
        artist: String,
        lyric: String,
        coverPath: String?,
        isPlaying: Boolean,
        opacity: Float
    ) {
        if (!hasOverlayPermission()) {
            android.util.Log.w(TAG, "无悬浮窗权限，忽略 show")
            return
        }
        val density = context.resources.displayMetrics.density
        if (overlayView == null) {
            overlayView = buildView().also { view ->
                val w = fixedWidth(density)
                barWidth = w
                wmParams = WindowManager.LayoutParams(
                    w,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    else
                        WindowManager.LayoutParams.TYPE_PHONE,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    x = 0
                    y = (16 * density).toInt() // 距屏幕底部 16dp
                }
                try {
                    windowManager.addView(view, wmParams)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "浮窗 addView 失败", e)
                    overlayView = null
                    wmParams = null
                    return
                }
            }
        }
        update(title, artist, lyric, isPlaying, opacity)
    }

    /** 就地刷新文本 / 透明度 / 锁定态，不重建窗口。视图尚未创建时先 [show]。 */
    fun update(
        title: String,
        artist: String,
        lyric: String,
        isPlaying: Boolean,
        opacity: Float
    ) {
        if (overlayView == null) {
            show(title, artist, lyric, null, isPlaying, opacity)
            return
        }
        try {
            lyricView?.text = lyric
            lyricView?.isSelected = isPlaying
            val sub = if (title.isEmpty() && artist.isEmpty()) {
                ""
            } else {
                "$title${if (artist.isEmpty()) "" else " · $artist"}"
            }
            subView?.text = sub
            // 整体半透明：透明度作用于根视图，歌词与背景一并可调。
            overlayView?.alpha = opacity.coerceIn(0f, 1f)
            applyLocked(locked)
        } catch (e: Exception) {
            android.util.Log.w(TAG, "浮窗刷新失败", e)
        }
    }

    fun hide() {
        val view = overlayView ?: return
        overlayView = null
        lyricView = null
        subView = null
        closeView = null
        lockIndicator = null
        wmParams = null
        locked = false
        dragging = false
        try {
            windowManager.removeView(view)
        } catch (e: Exception) {
            android.util.Log.w(TAG, "浮窗 removeView 失败", e)
        }
    }

    // ---- 卡片构建 ----

    private fun buildView(): View {
        val density = context.resources.displayMetrics.density

        // 深色卡片（让歌词更醒目），圆角 + 边框 + 悬浮阴影
        val radius = 16.dp(density).toFloat()
        val cardColorTop = 0xFF2A2E35.toInt()
        val cardColorBottom = 0xFF20242A.toInt()
        val borderColor = 0x1FFFFFFF.toInt()
        val textColor = 0xFFFFFFFF.toInt()
        val secondaryColor = 0xFFB6BAC1.toInt()

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(16.dp(density), 12.dp(density), 12.dp(density), 12.dp(density))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(cardColorTop, cardColorBottom)
            ).apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = radius
                setStroke((0.8f * density).toInt(), borderColor)
            }
            elevation = 12.dp(density).toFloat()
            setOnTouchListener(touchListener)
        }

        // 文本列：大号居中歌词 + 次要色歌名·歌手（桌面歌词居中观感）
        val textColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        val lyric = TextView(context).apply {
            lyricView = this
            textSize = 18f
            setTextColor(textColor)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1
            isSelected = true
        }
        val sub = TextView(context).apply {
            subView = this
            textSize = 12f
            setTextColor(secondaryColor)
            gravity = Gravity.CENTER
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
        }
        textColumn.addView(lyric)
        textColumn.addView(sub)
        root.addView(
            textColumn,
            LinearLayout.LayoutParams(0, WindowManager.LayoutParams.WRAP_CONTENT, 1f)
        )

        // 锁定指示（默认隐藏）：锁定态显示，提示「双击解锁」
        val lock = TextView(context).apply {
            lockIndicator = this
            text = "锁"
            textSize = 13f
            setTextColor(secondaryColor)
            gravity = Gravity.CENTER
            visibility = View.GONE
        }
        root.addView(
            lock,
            LinearLayout.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(8.dp(density), 0, 0, 0) }
        )

        // 关闭按钮：×，点击隐藏
        val close = TextView(context).apply {
            closeView = this
            text = "×"
            setTextColor(secondaryColor)
            textSize = 22f
            gravity = Gravity.CENTER
            setPadding(8.dp(density), 8.dp(density), 8.dp(density), 8.dp(density))
            setOnClickListener { hide() }
        }
        root.addView(
            close,
            LinearLayout.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(4.dp(density), 0, 0, 0) }
        )

        return root
    }

    /** 触摸监听：拖动移动位置、双击锁定 / 解锁。 */
    private val touchListener = View.OnTouchListener { view, event ->
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                if (!locked) {
                    downX = event.rawX
                    downY = event.rawY
                    lastTouchX = event.rawX
                    lastTouchY = event.rawY
                    dragging = false
                }
                true
            }
            MotionEvent.ACTION_MOVE -> {
                if (locked) return@OnTouchListener true
                val dx = event.rawX - lastTouchX
                val dy = event.rawY - lastTouchY
                if (!dragging &&
                    (abs(event.rawX - downX) > DRAG_THRESHOLD_PX ||
                        abs(event.rawY - downY) > DRAG_THRESHOLD_PX)
                ) {
                    dragging = true
                }
                if (dragging && wmParams != null) {
                    wmParams!!.x += dx.toInt()
                    // BOTTOM 重力下，y 为距底部偏移，手指下移（dy>0）应使 y 减小
                    wmParams!!.y -= dy.toInt()
                    clampParams(wmParams!!)
                    windowManager.updateViewLayout(view, wmParams)
                }
                lastTouchX = event.rawX
                lastTouchY = event.rawY
                true
            }
            MotionEvent.ACTION_UP -> {
                val now = System.currentTimeMillis()
                if (!dragging && now - lastTapTime < DOUBLE_TAP_MS) {
                    toggleLock()
                    lastTapTime = 0
                } else {
                    lastTapTime = if (dragging) 0 else now
                }
                dragging = false
                true
            }
            else -> false
        }
    }

    private fun toggleLock() {
        locked = !locked
        applyLocked(locked)
    }

    /** 锁定态：隐藏关闭按钮、显示锁定指示；解锁反之。 */
    private fun applyLocked(isLocked: Boolean) {
        closeView?.visibility = if (isLocked) View.GONE else View.VISIBLE
        lockIndicator?.visibility = if (isLocked) View.VISIBLE else View.GONE
    }

    /** 限制拖动范围：水平不超过屏幕两侧，垂直不越过屏幕 80% 高度且不低于底部。 */
    private fun clampParams(p: WindowManager.LayoutParams) {
        val screenW = context.resources.displayMetrics.widthPixels
        val screenH = context.resources.displayMetrics.heightPixels
        val maxX = (p.width / 2).coerceAtMost((screenW / 2))
        p.x = p.x.coerceIn(-maxX, maxX)
        p.y = p.y.coerceIn(0, (screenH * 0.8).toInt())
    }

    private fun fixedWidth(density: Float): Int {
        val screenW = context.resources.displayMetrics.widthPixels
        val desired = (340 * density).toInt()
        // 不超过屏幕宽度的 92%，避免窄屏溢出
        return minOf(desired, (screenW * 0.92).toInt())
    }

    private fun Int.dp(density: Float) = (this * density).toInt()
}
