package com.feiniu.music.track_change

import com.feiniu.music.R
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 浮窗灵动岛（常驻歌词浮窗）。
 *
 * 与 [OverlayTrackChange]（切歌提示，限时自动消失）不同，本浮窗在「正在播放且
 * 有歌词」期间常驻显示，收起态为顶部居中的胶囊：左侧官方应用图标
 * （[R.mipmap.ic_launcher]，全彩、不经系统 tint）+ 当前歌词（跑马灯）+
 * 歌名·歌手（次级色）+ 关闭按钮。点击胶囊主体在「收起 / 展开」间切换：展开态
 * 显示更大的官方 LOGO + 歌名（粗体）+ 歌手。
 *
 * 用途：HyperOS 实时通知的 smallIcon 会被系统强制单色 + 圆底，无法显示全彩官方
 * LOGO；焦点通知虽能显示 pic_logo 全彩图标，但需系统白名单（常需 Shizuku 绕过）。
 * 本浮窗完全绕开系统通知链路，自行绘制官方 LOGO，稳定可靠、零白名单依赖。
 *
 * 所有 WindowManager 操作 try/catch：权限被撤销 / Activity 销毁时不崩溃。
 */
class OverlayFloatingIsland(private val context: Context) {

    companion object {
        private const val TAG = "OverlayFloatingIsland"
    }

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var logoView: ImageView? = null
    private var lyricView: TextView? = null
    private var titleView: TextView? = null
    private var artistView: TextView? = null
    private var expanded = false

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
     * 显示 / 刷新浮窗。视图首次创建，后续 update 在原视图上就地刷新文本与图标，
     * 不重建窗口（保留展开/收起状态、不闪烁）。[coverPath] 暂未使用（保持官方 LOGO 恒定）。
     */
    fun show(
        title: String,
        artist: String,
        lyric: String,
        coverPath: String?,
        isPlaying: Boolean
    ) {
        if (!hasOverlayPermission()) {
            android.util.Log.w(TAG, "无悬浮窗权限，忽略 show")
            return
        }
        val density = context.resources.displayMetrics.density
        if (overlayView == null) {
            overlayView = buildView().also { view ->
                val wmParams = WindowManager.LayoutParams(
                    fixedWidth(density),
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    else
                        WindowManager.LayoutParams.TYPE_PHONE,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    android.graphics.PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    y = statusBarHeight() + 12.dpToPx(context)
                }
                try {
                    windowManager.addView(view, wmParams)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "浮窗 addView 失败", e)
                    overlayView = null
                    return
                }
            }
        }
        update(title, artist, lyric, isPlaying)
    }

    /** 就地刷新文本 / 图标，不重建窗口。视图尚未创建时先 [show] 建立。 */
    fun update(title: String, artist: String, lyric: String, isPlaying: Boolean) {
        if (overlayView == null) {
            show(title, artist, lyric, null, isPlaying)
            return
        }
        try {
            logoView?.setImageResource(R.mipmap.ic_launcher)
            lyricView?.text = lyric
            titleView?.text = title
            artistView?.text = if (artist.isEmpty()) "" else "· $artist"
            overlayView?.let { applyExpanded(it, expanded) }
            // 跑马灯需要视图可见后重新触发选中状态
            lyricView?.isSelected = isPlaying
        } catch (e: Exception) {
            android.util.Log.w(TAG, "浮窗刷新失败", e)
        }
    }

    fun hide() {
        val view = overlayView ?: return
        overlayView = null
        logoView = null
        lyricView = null
        titleView = null
        artistView = null
        try {
            windowManager.removeView(view)
        } catch (e: Exception) {
            android.util.Log.w(TAG, "浮窗 removeView 失败", e)
        }
    }

    // ---- 卡片构建 ----

    private fun buildView(): View {
        val density = context.resources.displayMetrics.density

        // 深色卡片（让官方 LOGO 的红底更醒目），圆角 + 边框 + 悬浮阴影
        val radius = 18.dp(density).toFloat()
        val cardColorTop = 0xFF2A2E35.toInt()
        val cardColorBottom = 0xFF20242A.toInt()
        val borderColor = 0x1FFFFFFF.toInt()
        val textColor = 0xFFFFFFFF.toInt()
        val secondaryColor = 0xFFB6BAC1.toInt()

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(10.dp(density), 8.dp(density), 8.dp(density), 8.dp(density))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(cardColorTop, cardColorBottom)
            ).apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = radius
                setStroke((0.8f * density).toInt(), borderColor)
            }
            elevation = 12.dp(density).toFloat()
            setOnClickListener { toggleExpand() }
        }

        // 官方全彩 LOGO：直接用应用图标资源，零处理、不被系统 tint。
        val logoSize = 38.dp(density)
        val logo = ImageView(context).apply {
            logoView = this
            setImageResource(R.mipmap.ic_launcher)
            // 圆形裁剪背景（与动态岛胶囊观感一致）；图标本身自带圆角方底，
            // 套一层圆形遮罩让它在胶囊里更协调。
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x00000000)
            }
            clipToOutline = false
        }
        root.addView(
            logo,
            LinearLayout.LayoutParams(logoSize, logoSize).apply {
                setMargins(0, 0, 10.dp(density), 0)
            }
        )

        // 文本列：歌词（主，跑马灯）+ 歌名（粗体，展开时显示）+ 歌手（次级色）
        val textColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val lyric = TextView(context).apply {
            lyricView = this
            textSize = 14f
            setTextColor(textColor)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1
            isSelected = true
        }
        val title = TextView(context).apply {
            titleView = this
            textSize = 13f
            setTextColor(textColor)
            setTypeface(null, Typeface.BOLD)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
        }
        val artist = TextView(context).apply {
            artistView = this
            textSize = 11f
            setTextColor(secondaryColor)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
        }
        textColumn.addView(lyric)
        textColumn.addView(title)
        textColumn.addView(artist)
        root.addView(
            textColumn,
            LinearLayout.LayoutParams(0, WindowManager.LayoutParams.WRAP_CONTENT, 1f)
        )

        // 关闭按钮：×，点击隐藏
        val closeBtn = TextView(context).apply {
            text = "×"
            setTextColor(secondaryColor)
            textSize = 20f
            gravity = Gravity.CENTER
            setPadding(6.dp(density), 6.dp(density), 6.dp(density), 6.dp(density))
            setOnClickListener {
                hide()
            }
        }
        // 阻止关闭按钮的点击冒泡到 root（避免误触展开）
        closeBtn.setOnClickListener {
            hide()
        }
        root.addView(
            closeBtn,
            LinearLayout.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(4.dp(density), 0, 0, 0) }
        )

        return root
    }

    private fun toggleExpand() {
        expanded = !expanded
        overlayView?.let { applyExpanded(it, expanded) }
    }

    /** 根据展开状态切换歌名/歌手可见性与 LOGO 尺寸。 */
    private fun applyExpanded(view: View, isExpanded: Boolean) {
        // 文本列是 root 的第 2 个子视图（logo 之后）
        val textColumn = (view as? LinearLayout)?.getChildAt(1) as? LinearLayout ?: return
        val lyric = textColumn.getChildAt(0) as? TextView
        val title = textColumn.getChildAt(1) as? TextView
        val artist = textColumn.getChildAt(2) as? TextView
        if (isExpanded) {
            title?.visibility = View.VISIBLE
            artist?.visibility = View.VISIBLE
            lyric?.textSize = 13f
        } else {
            title?.visibility = View.GONE
            artist?.visibility = View.GONE
            lyric?.textSize = 14f
        }
    }

    private fun fixedWidth(density: Float): Int {
        val screenW = context.resources.displayMetrics.widthPixels
        val desired = (340 * density).toInt()
        // 不超过屏幕宽度的 92%，避免窄屏溢出
        return minOf(desired, (screenW * 0.92).toInt())
    }

    private fun Int.dp(density: Float) = (this * density).toInt()

    private fun Int.dpToPx(context: Context): Int =
        (this * context.resources.displayMetrics.density).toInt()

    private fun statusBarHeight(): Int {
        val res = context.resources
        val id = res.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) res.getDimensionPixelSize(id) else 0
    }
}
