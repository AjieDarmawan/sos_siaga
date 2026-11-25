package id.siagasos

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import java.lang.ref.WeakReference
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

/** Hasil rekaman dari app host (kamera/mikrofon disediakan app; SDK tidak membawa library kamera). */
class CapturedMedia(val bytes: ByteArray, val contentType: String, val durationS: Double? = null)

/**
 * Kamera / perekam app host. Panggil [done] di main thread dengan hasilnya, atau null bila pengguna membatalkan.
 * Dipakai untuk video TKP setelah SOS dan foto lampiran pengaduan.
 */
fun interface MediaCapture {
    fun capture(activity: Activity, kind: MediaKind, done: (CapturedMedia?) -> Unit)
}

/** Sirene panik di HP pelapor. Suara diputar app host. Selama [isActive] tombol bulat menjadi "SENYAP" ([stop]). */
interface SosSiren {
    val isActive: Boolean
    fun start()
    fun stop()
    /** SDK memasang listener untuk memperbarui tombol saat sirene mulai / berhenti. Panggil di main thread. */
    fun setOnActiveChanged(listener: ((Boolean) -> Unit)?)
}

/**
 * Tombol SOS kecil yang melayang di atas semua Activity (padanan `SOSFloatingButton` Flutter / `DraggableSosMenu` tata-warga).
 *
 * Ketuk → **Kirim SOS** (sekali ketuk; opsional tahan N detik lewat [Options.holdSeconds]), **Telepon 110**, **Telepon 112**, dan
 * **Laporan** → Pengaduan / Riwayat laporan / Nomor darurat. Setelah SOS terkirim: sirene (opsional) dan ajakan
 * "Rekam kondisi TKP?" → [Options.onCapture] video → catatan → dikirim ke petugas.
 *
 * Pasang sekali di `Application.onCreate`:
 * ```kotlin
 * val sos = SiagaSOS.create(this, apiKey = "pk_live_...", user = SosUser(ref = uid, name = nama))
 * SOSFloatingButton.install(this, sos, SOSFloatingButton.Options().apply {
 *     onCapture = MediaCapture { activity, kind, done -> myCamera.record(activity, kind, done) } // opsional
 * })
 * ```
 * Tombol bisa digeser, menempel ke tepi kiri/kanan, posisinya diingat, dan area di luar tombol tidak menangkap sentuhan.
 */
class SOSFloatingButton private constructor(private val app: Application, val client: SiagaSOS, val options: Options) : SosListener {

    class Options {
        var category: String = "general"
        var message: String? = null
        /**
         * Default 0 = sekali ketuk langsung kirim (seperti EWS tata-warga). Isi N > 0 untuk tahan N detik
         * (mencegah salah tekan), atau null untuk ikut `hold_seconds` dari portal.
         */
        var holdSeconds: Int? = 0
        /** Menelepon nomor darurat. Default: buka dialer (`ACTION_DIAL`, tanpa izin CALL_PHONE). null = sembunyikan tombol telepon. */
        var onCall: ((Activity, String) -> Unit)? = { a, phone -> runCatching { a.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))) } }
        /** Nomor kedua di menu. Nomor pertama memakai `fallback_phone` portal (default 110). */
        var secondaryPhone: String? = null
        var callLabel: String = "Call"
        /** Label lengkap tombol telepon pertama (mis. "Call 110 Polri"). null = "$callLabel $nomor" (+ " Polri" untuk 110). */
        var firstCallLabel: String? = null
        /** Gradien tombol telepon pertama. null = indigo default. */
        var callColors: IntArray? = intArrayOf(0xFF60A5FA.toInt(), 0xFF3B82F6.toInt(), 0xFF2563EB.toInt())
        /** Label menu Laporan Kejadian, sub-menu Buat Laporan, dan Input Nomor (nomor darurat pribadi). */
        var reportLabel: String = "Laporan Kejadian"
        var complaintLabel: String = "Buat Laporan"
        var contactsLabel: String = "Input Nomor"
        /** Kamera app host: video TKP & foto pengaduan. null = tanpa lampiran / tanpa ajakan rekam TKP. */
        var onCapture: MediaCapture? = null
        var onSent: ((ActiveReport) -> Unit)? = null
        var onComplaintSent: ((ActiveReport) -> Unit)? = null
        var onError: ((SiagaSOSException) -> Unit)? = null
        var sizeDp: Int = 48
        var color: Int = Color.parseColor("#DC2626")
        /** Label tombol kirim di menu (mis. "EWS Alert"). null = "Kirim <button_text portal>". */
        var sosLabel: String? = null
        /** Gradien tombol kirim di menu (mis. kuning EWS). null = turunan [color]. */
        var sosColors: IntArray? = intArrayOf(0xFFFF7058.toInt(), 0xFFEB334C.toInt(), 0xFFD72242.toInt())
        var complaint: Boolean = true
        var history: Boolean = true
        var emergencyContacts: Boolean = true
        var siren: SosSiren? = null
        /** Ajakan "Rekam kondisi TKP?" setelah SOS terkirim (butuh [onCapture]). */
        var tkpPrompt: Boolean = true
        var tkpSeconds: Int = 5
        /** Membuka peta / lampiran dari detail riwayat. Default `ACTION_VIEW`. */
        var onOpenUrl: ((Activity, String) -> Unit)? = { a, url -> runCatching { a.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
        /** Activity yang tidak diberi tombol (mis. login, layar kamera). */
        var hideIn: (Activity) -> Boolean = { false }
        /** Kunci SharedPreferences posisi tombol. */
        var positionKey: String = "fab.position"
    }

    companion object {
        /** Pasang tombol di semua Activity aplikasi. Panggil sekali (mis. di `Application.onCreate`). */
        @JvmStatic @JvmOverloads
        fun install(app: Application, client: SiagaSOS, options: Options = Options()): SOSFloatingButton =
            SOSFloatingButton(app, client, options).also { it.start() }

        private const val TAG_LAYER = "siagasos-floating-layer"
    }

    private val main = Handler(Looper.getMainLooper())
    private val prefs = app.getSharedPreferences("siagasos", Context.MODE_PRIVATE)
    private val layers = mutableListOf<WeakReference<Layer>>()
    private var current: WeakReference<Activity>? = null
    private var callbacks: Application.ActivityLifecycleCallbacks? = null

    // State bersama semua Activity.
    internal var cfg: SdkConfig? = null
    internal var report: ActiveReport? = null
    internal var sending = false
    internal var open = false
    internal var reportMenu = false
    internal var notice: String? = null
    internal var capturing = false
    internal var left = false
    internal var yFrac = 1f
    private var sheet: Sheet? = null

    /** false = sembunyikan tombol tanpa mencabut pemasangan (mis. saat belum login). */
    var visible: Boolean = true
        set(v) { field = v; render() }

    private fun start() {
        prefs.getString(options.positionKey, null)?.split(",")?.let { p ->
            left = p.getOrNull(0) == "L"
            yFrac = (p.getOrNull(1)?.toFloatOrNull() ?: 1f).coerceIn(0f, 1f)
        }
        client.addListener(this)
        client.getConfig { r -> r.onSuccess { c -> main.post { cfg = c; render() } } }
        options.siren?.setOnActiveChanged { main.post { render() } }
        val cb = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(a: Activity) { current = WeakReference(a); attach(a) }
            override fun onActivityDestroyed(a: Activity) { detach(a) }
            override fun onActivityCreated(a: Activity, b: Bundle?) {}
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityPaused(a: Activity) {}
            override fun onActivityStopped(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        }
        callbacks = cb
        app.registerActivityLifecycleCallbacks(cb)
    }

    /** Lepas dari semua Activity (mis. saat logout). Klien tidak di-shutdown. */
    fun uninstall() {
        callbacks?.let { app.unregisterActivityLifecycleCallbacks(it) }
        client.removeListener(this)
        options.siren?.setOnActiveChanged(null)
        sheet?.dismiss()
        layers.mapNotNull { it.get() }.forEach { (it.parent as? ViewGroup)?.removeView(it) }
        layers.clear()
    }

    /** Pasang ke satu Activity secara manual (bila tidak memakai [install] untuk semua Activity). */
    fun attach(activity: Activity) {
        if (options.hideIn(activity)) return
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val existing = content.findViewWithTag<Layer>(TAG_LAYER)
        if (existing != null) {
            // setContentView / fragment bisa menambah view di atas lapisan: pastikan tetap paling atas.
            if (content.indexOfChild(existing) != content.childCount - 1) existing.bringToFront()
            existing.render()
            return
        }
        val layer = Layer(activity, this).apply { tag = TAG_LAYER }
        content.addView(layer, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        layers.removeAll { it.get() == null }
        layers.add(WeakReference(layer))
        layer.render()
    }

    private fun detach(activity: Activity) {
        layers.removeAll { r -> r.get().let { it == null || it.context === activity } }
        if (sheet?.activity === activity) sheet = null
    }

    internal fun render() = main.post { layers.mapNotNull { it.get() }.forEach { it.render() } }

    // ------------------------------------------------------------------ SosListener
    override fun onStatus(report: ActiveReport) {
        if (report.kind != ReportKind.SOS) return
        main.post {
            if (this.report == null || this.report!!.localId == report.localId) { this.report = report; render() }
        }
    }

    // ------------------------------------------------------------------ aksi
    internal val seconds: Int get() = options.holdSeconds ?: cfg?.holdSeconds ?: 3
    internal val active: Boolean get() = report?.status?.isTerminal == false
    internal val sirenOn: Boolean get() = options.siren?.isActive == true
    private val tkp: Boolean get() = options.tkpPrompt && options.onCapture != null

    internal fun toggle() {
        open = !open
        reportMenu = false
        notice = null
        if (open && report?.status?.isTerminal == true) report = null
        render()
    }

    internal fun fire(view: View) {
        if (sending) return
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        options.siren?.start() // alarm panik tanpa menunggu server
        sending = true
        render()
        client.trigger(options.category, options.message) { res ->
            main.post {
                sending = false
                res.onSuccess { r ->
                    report = r
                    open = false
                    if (r.id != null) options.onSent?.invoke(r)
                    val a = current?.get()
                    if (tkp && a != null) openSheet(a) { TkpSheet(it, this, r) }
                }
                res.onFailure { e ->
                    options.siren?.stop() // SOS tidak terkirim: sirene menyesatkan
                    notice = e.message
                    (e as? SiagaSOSException)?.let { options.onError?.invoke(it) }
                }
                render()
            }
        }
    }

    internal fun call(activity: Activity, phone: String) {
        open = false
        render()
        options.onCall?.invoke(activity, phone)
    }

    internal fun openComplaint(a: Activity) = openSheet(a) { ComplaintSheet(it, this) }
    internal fun openHistory(a: Activity) = openSheet(a) { HistorySheet(it, this) }
    internal fun openContacts(a: Activity) = openSheet(a) { ContactsSheet(it, this) }

    private fun openSheet(a: Activity, make: (Activity) -> Sheet) {
        open = false
        reportMenu = false
        render()
        sheet?.dismiss()
        sheet = make(a).also { it.show() }
    }

    internal fun sheetClosed(s: Sheet) { if (sheet === s) sheet = null }

    internal fun markCapturing(v: Boolean) { capturing = v; render() }

    internal fun savePosition(left: Boolean, yFrac: Float) {
        this.left = left
        this.yFrac = yFrac
        prefs.edit().putString(options.positionKey, "${if (left) "L" else "R"},${"%.4f".format(Locale.US, yFrac)}").apply()
    }

    internal fun statusText(r: ActiveReport): String = r.statusMessage ?: when (r.status) {
        SosStatus.QUEUED -> "Menunggu sinyal, akan terkirim otomatis"
        SosStatus.OPEN -> "Terkirim. Menunggu petugas…"
        SosStatus.ACKNOWLEDGED -> "Petugas menerima laporan"
        SosStatus.IN_PROGRESS -> "Petugas sedang menangani"
        SosStatus.RESOLVED -> "Selesai ditangani"
        SosStatus.CANCELLED -> "Dibatalkan"
        SosStatus.FALSE_ALARM -> "Ditandai alarm palsu"
    }
}

// ====================================================================== tampilan

/** Palet terang/gelap mengikuti tema sistem. */
internal class Palette(ctx: Context) {
    val dark = (ctx.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val bg = if (dark) 0xFF111827.toInt() else Color.WHITE
    val card = if (dark) 0xFF1F2937.toInt() else 0xFFF8FAFC.toInt()
    val border = if (dark) 0xFF374151.toInt() else 0xFFE2E8F0.toInt()
    val text = if (dark) 0xFFF9FAFB.toInt() else 0xFF0F172A.toInt()
    val muted = if (dark) 0xFF9CA3AF.toInt() else 0xFF64748B.toInt()
    val danger = 0xFFDC2626.toInt()
    val primary = 0xFF2563EB.toInt()
    val ok = 0xFF16A34A.toInt()
}

internal fun Context.dp(v: Number): Int = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()
internal fun View.dp(v: Number): Int = context.dp(v)

/** Gaya tombol menu compact (sama dengan SDK Flutter): tinggi 38, sudut 16, border hitam, teks hitam 12.5sp, ikon di lingkaran putih. */
internal fun applyCompact(tv: TextView, colors: IntArray, icon: Drawable) {
    val c = tv.context
    tv.setTextColor(Color.BLACK)
    tv.textSize = 16f
    tv.typeface = Typeface.DEFAULT_BOLD
    tv.gravity = Gravity.CENTER_VERTICAL
    tv.maxLines = 1
    tv.ellipsize = TextUtils.TruncateAt.END
    tv.minHeight = c.dp(40)
    tv.setPadding(c.dp(7), 0, c.dp(16), 0)
    tv.compoundDrawablePadding = c.dp(12)
    tv.setCompoundDrawablesRelativeWithIntrinsicBounds(icon, null, null, null)
    tv.background = gradient(colors, c.dp(20).toFloat()).apply { setStroke(c.dp(1.5), Color.BLACK) }
    tv.elevation = c.dp(3).toFloat()
}

/** Lingkaran putih 24dp berisi ikon; [tint] = warna ikon (null = ikon apa adanya, mis. ilustrasi polisi). */
internal class ChipDrawable(ctx: Context, iconRes: Int, private val tint: Int?) : Drawable() {
    private val size = ctx.dp(30)
    private val icon: Drawable? = ctx.getDrawable(iconRes)?.mutate()
    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        strokeWidth = ctx.dp(1.5).toFloat()
    }
    private val clip = Path()

    override fun getIntrinsicWidth() = size
    override fun getIntrinsicHeight() = size

    override fun draw(canvas: Canvas) {
        val b = bounds
        val cx = b.exactCenterX()
        val cy = b.exactCenterY()
        val r = b.width() / 2f
        canvas.drawCircle(cx, cy, r, bg)
        val ic = icon ?: return
        canvas.save()
        clip.reset()
        clip.addCircle(cx, cy, r, Path.Direction.CW)
        canvas.clipPath(clip)
        val inset = if (tint != null) (b.width() * 0.22f).toInt() else 0
        ic.setBounds(b.left + inset, b.top + inset, b.right - inset, b.bottom - inset)
        if (tint != null) ic.setTint(tint)
        ic.draw(canvas)
        canvas.restore()
        canvas.drawCircle(cx, cy, r - ring.strokeWidth / 2f, ring)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

internal fun rounded(color: Int, radiusPx: Float, stroke: Int? = null, strokePx: Int = 0) = GradientDrawable().apply {
    setColor(color); cornerRadius = radiusPx; stroke?.let { setStroke(strokePx, it) }
}

internal fun gradient(colors: IntArray, radiusPx: Float) = GradientDrawable(GradientDrawable.Orientation.TL_BR, colors).apply { cornerRadius = radiusPx }

internal fun darken(c: Int, f: Float) = Color.rgb((Color.red(c) * (1 - f)).toInt(), (Color.green(c) * (1 - f)).toInt(), (Color.blue(c) * (1 - f)).toInt())
internal fun lighten(c: Int, f: Float) = Color.rgb((Color.red(c) + (255 - Color.red(c)) * f).toInt(), (Color.green(c) + (255 - Color.green(c)) * f).toInt(), (Color.blue(c) + (255 - Color.blue(c)) * f).toInt())

/** Lapisan per Activity: tombol bulat + menu. Tidak menangkap sentuhan di luar anak-anaknya. */
@SuppressLint("ViewConstructor")
internal class Layer(private val activity: Activity, private val c: SOSFloatingButton) : FrameLayout(activity) {
    private val fab = Fab(activity, c)
    private val menu = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private var insetTop = 0
    private var insetBottom = 0
    private val edge = dp(12)
    private val size = dp(c.options.sizeDp)

    init {
        clipChildren = false
        elevation = dp(24).toFloat()
        addView(menu, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addView(fab, LayoutParams(size + dp(8), size + dp(8)))
        @Suppress("DEPRECATION")
        setOnApplyWindowInsetsListener { _, insets ->
            insetTop = insets.systemWindowInsetTop
            insetBottom = insets.systemWindowInsetBottom
            placeFab(); render()
            insets
        }
        fab.onMoved = { x, y, done -> onFabMoved(x, y, done) }
    }

    private val minY get() = insetTop + edge
    private val maxY get() = max(minY, height - insetBottom - edge - size)
    private fun restX(left: Boolean) = if (left) edge - dp(4) else width - edge - size - dp(4)

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        post { placeFab(); render() }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestApplyInsets()
    }

    private fun placeFab() {
        if (width == 0 || fab.dragging) return
        fab.x = restX(c.left).toFloat()
        fab.y = (minY + (maxY - minY) * c.yFrac - dp(4))
    }

    private fun onFabMoved(x: Float, y: Float, done: Boolean) {
        val cx = x.coerceIn(edge.toFloat() - dp(4), (width - edge - size - dp(4)).toFloat())
        val cy = y.coerceIn(minY.toFloat() - dp(4), maxY.toFloat() - dp(4))
        if (!done) { fab.x = cx; fab.y = cy; if (c.open) { c.open = false; c.render() }; return }
        val left = cx + size / 2 < width / 2
        val frac = if (maxY > minY) ((cy + dp(4) - minY) / (maxY - minY)).coerceIn(0f, 1f) else 1f
        c.savePosition(left, frac)
        fab.animate().x(restX(left).toFloat()).y(minY + (maxY - minY) * frac - dp(4)).setDuration(220).setInterpolator(DecelerateInterpolator()).start()
        c.render()
    }

    fun render() {
        visibility = if (c.visible && !c.capturing) View.VISIBLE else View.GONE
        fab.invalidate()
        fab.contentDescription = when {
            c.sirenOn -> "Matikan sirene"
            c.open -> "Tutup menu darurat"
            else -> "Menu darurat SOS" + (c.report?.let { ". ${c.statusText(it)}" } ?: "")
        }
        menu.removeAllViews()
        if (!c.open || width == 0) { menu.visibility = View.GONE; return }
        menu.visibility = View.VISIBLE
        val fabCenterX = fab.x + fab.width / 2
        val fabY = if (fab.dragging) fab.y else minY + (maxY - minY) * c.yFrac - dp(4)
        val onLeft = fabCenterX < width / 2
        val openUp = fabY + fab.height / 2 > height / 2
        val lp = menu.layoutParams as LayoutParams
        lp.gravity = (if (onLeft) Gravity.LEFT else Gravity.RIGHT) or (if (openUp) Gravity.BOTTOM else Gravity.TOP)
        lp.leftMargin = if (onLeft) edge else 0
        lp.rightMargin = if (onLeft) 0 else edge
        lp.topMargin = if (openUp) 0 else (fabY + dp(4) + size + dp(10)).toInt()
        lp.bottomMargin = if (openUp) (height - fabY - dp(4) + dp(10)).toInt() else 0
        menu.layoutParams = lp
        menu.gravity = if (onLeft) Gravity.LEFT else Gravity.RIGHT
        val items = if (c.reportMenu) listOf(reportPanel()) else actions()
        val caption = caption()
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val ordered = if (openUp) items.reversed() else items
        ordered.forEachIndexed { i, v ->
            column.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { if (i > 0) topMargin = dp(6) })
            v.alpha = 0f; v.translationY = dp(if (openUp) 8 else -8).toFloat()
            val order = if (openUp) ordered.size - 1 - i else i
            v.animate().alpha(1f).translationY(0f).setStartDelay(order * 35L).setDuration(160).start()
        }
        val capLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        if (caption != null && openUp) menu.addView(caption, capLp.apply { bottomMargin = dp(8) })
        menu.addView(column, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        if (caption != null && !openUp) menu.addView(caption, capLp.apply { topMargin = dp(8) })
    }

    private fun caption(): View? {
        val notes = mutableListOf<String>()
        c.notice?.let { notes += it }
        c.report?.takeIf { c.active }?.let { notes += "SOS aktif: ${c.statusText(it)}" }
        if (c.client.mode == SosMode.TEST) notes += "MODE TEST"
        if (notes.isEmpty()) return null
        return TextView(context).apply {
            text = notes.joinToString(" · ")
            setTextColor(if (c.notice != null) 0xFFFCA5A5.toInt() else Color.WHITE)
            textSize = 11.5f
            maxWidth = dp(220)
            setPadding(dp(10), dp(7), dp(10), dp(7))
            background = rounded(0xE6111827.toInt(), dp(10).toFloat())
        }
    }

    /** Dari tombol bulat ke luar: Laporan, telepon kedua, telepon pertama, kirim SOS (dibalik saat membuka ke atas). */
    private fun actions(): List<View> {
        val o = c.options
        val first = c.cfg?.fallbackPhone?.ifBlank { null } ?: "110"
        val second = o.secondaryPhone?.takeIf { it != first }
        val subs = listOfNotNull(
            if (o.complaint) "complaint" else null, if (o.history) "history" else null, if (o.emergencyContacts) "contacts" else null)
        val out = mutableListOf<View>()
        if (subs.isNotEmpty()) out += pill(o.reportLabel, intArrayOf(0xFFFDBA74.toInt(), 0xFFFB923C.toInt(), 0xFFEA580C.toInt()),
            ChipDrawable(context, R.drawable.siagasos_ic_clipboard, 0xFFEA580C.toInt())) {
            if (subs.size > 1) { c.reportMenu = true; c.render() } else openSub(subs.first())
        }
        if (o.onCall != null) {
            if (second != null) out += pill("${o.callLabel} $second", intArrayOf(0xFF6EE7B7.toInt(), 0xFF34D399.toInt(), 0xFF059669.toInt()),
                ChipDrawable(context, R.drawable.siagasos_ic_warning, 0xFF059669.toInt())) { c.call(activity, second) }
            val firstLabel = o.firstCallLabel ?: "${o.callLabel} $first${if (first == "110") " Polri" else ""}"
            out += pill(firstLabel, o.callColors ?: intArrayOf(0xFF818CF8.toInt(), 0xFF6366F1.toInt(), 0xFF4F46E5.toInt()),
                ChipDrawable(context, R.drawable.siagasos_police, null)) { c.call(activity, first) }
        }
        // Server selalu mengirim button_text ('SOS' bila portal kosong): 'SOS' = bawaan → "Emergency".
        val label = o.sosLabel ?: c.cfg?.buttonText?.trim()
            ?.takeIf { it.isNotBlank() && !it.equals("SOS", ignoreCase = true) }?.let { "Kirim $it" } ?: "Emergency"
        out += HoldToSend(activity, c, label, o.sosColors ?: intArrayOf(lighten(o.color, 0.12f), darken(o.color, 0.3f)))
        return out
    }

    private fun openSub(key: String) = when (key) {
        "complaint" -> c.openComplaint(activity)
        "history" -> c.openHistory(activity)
        else -> c.openContacts(activity)
    }

    /** Sub-menu Laporan, sama dengan `_ReportPanel` di SDK Flutter: kartu putih, header ← label, lalu baris ber-ikon. */
    private fun reportPanel(): View {
        val ink = 0xFF1F2937.toInt()
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(Color.WHITE, dp(16).toFloat())
            elevation = dp(8).toFloat()
        }
        // Baris ber-padding seperti Flutter: kiri 10, kanan 18, atas-bawah 8.
        fun rowBase(onTap: () -> Unit) = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(18), dp(8))
            isClickable = true
            setOnClickListener { performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); onTap() }
        }
        val o = c.options
        // Header: ← Laporan Kejadian
        card.addView(rowBase { c.reportMenu = false; c.render() }.apply {
            addView(ImageView(context).apply { setImageResource(R.drawable.siagasos_ic_arrow_back); setColorFilter(ink) },
                LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(20) })
            addView(TextView(context).apply {
                text = o.reportLabel
                setTextColor(ink)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
        })
        card.addView(View(context).apply { setBackgroundColor(0xFFE5E7EB.toInt()) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)))
        // Baris pilihan: lingkaran ikon 30dp (warna 12% opacity) + ikon 17dp + label.
        fun row(label: String, icon: Int, color: Int, onTap: () -> Unit) = rowBase(onTap).apply {
            addView(FrameLayout(context).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor((color and 0x00FFFFFF) or (0x1F shl 24)) }
                addView(ImageView(context).apply { setImageResource(icon); setColorFilter(color) },
                    FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER))
            }, LinearLayout.LayoutParams(dp(30), dp(30)))
            addView(TextView(context).apply {
                text = label
                setTextColor(ink)
                textSize = 14f
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(10) })
        }
        if (o.complaint) card.addView(row(o.complaintLabel, R.drawable.siagasos_ic_campaign, 0xFFEA580C.toInt()) { c.openComplaint(activity) })
        if (o.history) card.addView(row("Riwayat laporan", R.drawable.siagasos_ic_history, 0xFF475569.toInt()) { c.openHistory(activity) })
        if (o.emergencyContacts) card.addView(row(o.contactsLabel, R.drawable.siagasos_ic_contact_phone, 0xFF2563EB.toInt()) { c.openContacts(activity) })
        card.addView(View(context), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(4)))
        return card
    }

    private fun dot(color: Int) = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setBounds(0, 0, dp(10), dp(10)) }

    private fun pill(label: String, colors: IntArray, icon: Drawable, onTap: () -> Unit) = TextView(context).apply {
        text = label
        applyCompact(this, colors, icon)
        isClickable = true
        setOnClickListener { performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); onTap() }
    }
}

/** Tombol bulat: ketuk = buka/tutup menu (atau matikan sirene), geser = pindah. */
@SuppressLint("ViewConstructor")
internal class Fab(ctx: Context, private val c: SOSFloatingButton) : View(ctx) {
    var onMoved: ((Float, Float, Boolean) -> Unit)? = null
    var dragging = false
        private set
    private val slop = ViewConfiguration.get(ctx).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var startX = 0f
    private var startY = 0f
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.WHITE }
    private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val spinner = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.WHITE; strokeCap = Paint.Cap.ROUND }
    private val arc = RectF()
    private var spin = 0f

    init {
        isClickable = true
        isFocusable = true
        elevation = dp(8).toFloat()
        outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(view: View, outline: android.graphics.Outline) {
                val p = dp(4); outline.setOval(p, p, view.width - p, view.height - p)
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        val pad = dp(4).toFloat()
        val r = (width - pad * 2) / 2
        val cx = width / 2f
        val cy = height / 2f
        val color = c.options.color
        fill.shader = android.graphics.LinearGradient(pad, pad, width - pad, height - pad, color, darken(color, 0.28f), android.graphics.Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, r, fill)
        ring.strokeWidth = dp(2.5f).toFloat().coerceAtLeast(2f)
        canvas.drawCircle(cx, cy, r - ring.strokeWidth / 2, ring)
        if (c.sending && !c.sirenOn) {
            spinner.strokeWidth = dp(2.4f).toFloat()
            val s = r * 0.42f
            arc.set(cx - s, cy - s, cx + s, cy + s)
            canvas.drawArc(arc, spin, 270f, false, spinner)
            spin = (spin + 12f) % 360f
            postInvalidateOnAnimation()
        } else {
            val text = when { c.sirenOn -> "SENYAP"; c.open -> "TUTUP"; else -> "SOS" }
            label.textSize = r * (if (text.length > 3) 0.36f else 0.62f)
            canvas.drawText(text, cx, cy - (label.descent() + label.ascent()) / 2, label)
        }
        if (c.active && !c.sirenOn) {
            val d = dp(7).toFloat()
            dotPaint.color = Color.WHITE
            canvas.drawCircle(width - pad - d + dp(1), pad + d - dp(1), d, dotPaint)
            dotPaint.color = 0xFFF59E0B.toInt()
            canvas.drawCircle(width - pad - d + dp(1), pad + d - dp(1), d - dp(2), dotPaint)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; startX = x; startY = y; dragging = false; isPressed = true }
            MotionEvent.ACTION_MOVE -> {
                val dx = e.rawX - downX; val dy = e.rawY - downY
                if (!dragging && (abs(dx) > slop || abs(dy) > slop)) { dragging = true; parent?.requestDisallowInterceptTouchEvent(true); animate().scaleX(1.08f).scaleY(1.08f).setDuration(120).start() }
                if (dragging) onMoved?.invoke(startX + dx, startY + dy, false)
            }
            MotionEvent.ACTION_UP -> {
                isPressed = false
                if (dragging) {
                    dragging = false
                    animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                    onMoved?.invoke(startX + e.rawX - downX, startY + e.rawY - downY, true)
                } else performClick()
            }
            MotionEvent.ACTION_CANCEL -> { isPressed = false; if (dragging) { dragging = false; scaleX = 1f; scaleY = 1f; onMoved?.invoke(x, y, true) } }
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        if (c.sirenOn) { c.options.siren?.stop(); c.render() } else c.toggle()
        return true
    }
}

/** Tombol kirim SOS di menu: tahan N detik (isi progres), atau sekali ketuk bila N = 0. */
@SuppressLint("ViewConstructor")
internal class HoldToSend(ctx: Context, private val c: SOSFloatingButton, label: String, colors: IntArray) : TextView(ctx) {
    private var progress = 0f
    private var anim: ValueAnimator? = null
    private val overlay = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x55FFFFFF }
    private val rect = RectF()

    init {
        val secs = c.seconds
        text = when {
            c.sending -> "Mengirim…"
            secs <= 0 -> label
            else -> "$label · tahan $secs dtk"
        }
        applyCompact(this, colors, ChipDrawable(ctx, R.drawable.siagasos_ic_warning, colors.last()))
        isClickable = true
        contentDescription = if (secs <= 0) "$label. Ketuk untuk mengirim." else "$label. Tahan $secs detik untuk mengirim."
    }

    override fun onDraw(canvas: Canvas) {
        if (progress > 0f) {
            rect.set(0f, 0f, width * progress, height.toFloat())
            canvas.save()
            canvas.clipRect(rect)
            canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(20).toFloat(), dp(20).toFloat(), overlay)
            canvas.restore()
        }
        super.onDraw(canvas)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (c.sending) return true
        val secs = c.seconds
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                isPressed = true
                if (secs > 0) {
                    performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                    anim = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = secs * 1000L
                        interpolator = LinearInterpolator()
                        addUpdateListener { progress = it.animatedValue as Float; invalidate() }
                        addListener(object : android.animation.AnimatorListenerAdapter() {
                            var cancelled = false
                            override fun onAnimationCancel(a: android.animation.Animator) { cancelled = true }
                            override fun onAnimationEnd(a: android.animation.Animator) { if (!cancelled) c.fire(this@HoldToSend) }
                        })
                        start()
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                isPressed = false
                if (secs <= 0) c.fire(this) else reset()
            }
            MotionEvent.ACTION_CANCEL -> { isPressed = false; reset() }
        }
        return true
    }

    // Untuk aksesibilitas (TalkBack): aksi klik langsung mengirim.
    override fun performClick(): Boolean { super.performClick(); c.fire(this); return true }

    private fun reset() { anim?.cancel(); anim = null; progress = 0f; invalidate() }
}

// ====================================================================== lembar dari bawah

/** Lembar dari bawah berbasis Dialog (tanpa AndroidX). Isi bisa diganti ([setBody]). */
internal abstract class Sheet(val activity: Activity, protected val c: SOSFloatingButton) {
    protected val p = Palette(activity)
    protected val dialog = android.app.Dialog(activity)
    private val titleView = TextView(activity)
    private val subtitleView = TextView(activity)
    private val bodyHolder = FrameLayout(activity)
    protected val main = Handler(Looper.getMainLooper())
    @Volatile protected var closed = false
    protected fun dp(v: Number): Int = activity.dp(v)

    init {
        dialog.requestWindowFeature(android.view.Window.FEATURE_NO_TITLE)
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(p.bg)
                val r = dp(20).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
            }
            setPadding(dp(20), dp(10), dp(20), dp(20))
        }
        root.addView(View(activity).apply { background = rounded(p.border, dp(3).toFloat()) },
            LinearLayout.LayoutParams(dp(40), dp(5)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(12) })
        val head = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val titles = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        titleView.apply { setTextColor(p.text); textSize = 18f; typeface = Typeface.DEFAULT_BOLD }
        subtitleView.apply { setTextColor(p.muted); textSize = 13f; visibility = View.GONE }
        titles.addView(titleView); titles.addView(subtitleView)
        head.addView(titles, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        head.addView(textButton("Tutup") { dismiss() })
        root.addView(head)
        val scroll = ScrollView(activity).apply { isFillViewport = false; addView(bodyHolder) }
        root.addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(14) })
        dialog.setContentView(root)
        dialog.setOnDismissListener { closed = true; c.sheetClosed(this); onClosed() }
        dialog.window?.apply {
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
            setGravity(Gravity.BOTTOM)
            setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
            @Suppress("DEPRECATION")
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            attributes = attributes.apply { windowAnimations = android.R.style.Animation_InputMethod }
        }
    }

    fun show() { dialog.show(); start() }
    fun dismiss() { if (dialog.isShowing) runCatching { dialog.dismiss() } }
    protected abstract fun start()
    protected open fun onClosed() {}

    protected fun setTitle(t: String, sub: String? = null) {
        titleView.text = t
        subtitleView.text = sub ?: ""
        subtitleView.visibility = if (sub.isNullOrEmpty()) View.GONE else View.VISIBLE
    }

    protected fun setBody(v: View) {
        bodyHolder.removeAllViews()
        bodyHolder.addView(v)
    }

    protected fun ui(block: () -> Unit) = main.post { if (!closed) block() }

    // ---- komponen kecil
    protected fun column() = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }

    protected fun LinearLayout.gap(h: Int) = addView(View(activity), LinearLayout.LayoutParams(1, dp(h)))

    protected fun label(t: String, size: Float = 14f, color: Int = p.text, bold: Boolean = false) = TextView(activity).apply {
        text = t; textSize = size; setTextColor(color); if (bold) typeface = Typeface.DEFAULT_BOLD; setLineSpacing(0f, 1.15f)
    }

    protected fun button(t: String, color: Int = p.danger, filled: Boolean = true, onTap: () -> Unit) = TextView(activity).apply {
        text = t
        textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        minHeight = dp(48)
        setPadding(dp(16), 0, dp(16), 0)
        setTextColor(if (filled) Color.WHITE else color)
        background = if (filled) rounded(color, dp(12).toFloat()) else rounded(Color.TRANSPARENT, dp(12).toFloat(), color, dp(1))
        isClickable = true
        setOnClickListener { performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); onTap() }
    }

    protected fun textButton(t: String, color: Int = p.primary, onTap: () -> Unit) = TextView(activity).apply {
        text = t; textSize = 14f; typeface = Typeface.DEFAULT_BOLD; setTextColor(color)
        setPadding(dp(10), dp(8), dp(10), dp(8)); isClickable = true
        setOnClickListener { onTap() }
    }

    protected fun View.enabled(on: Boolean) = apply { isEnabled = on; alpha = if (on) 1f else 0.45f }

    protected fun input(hint: String, multi: Boolean = false, type: Int = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES) = EditText(activity).apply {
        this.hint = hint
        setHintTextColor(p.muted)
        setTextColor(p.text)
        textSize = 15f
        inputType = if (multi) type or InputType.TYPE_TEXT_FLAG_MULTI_LINE else type
        if (multi) { minLines = 3; gravity = Gravity.TOP or Gravity.START }
        setPadding(dp(12), dp(10), dp(12), dp(10))
        background = rounded(p.card, dp(10).toFloat(), p.border, dp(1))
    }

    protected fun card() = column().apply {
        background = rounded(p.card, dp(12).toFloat(), p.border, dp(1))
        setPadding(dp(14), dp(12), dp(14), dp(12))
    }

    protected fun chip(t: String, selected: Boolean, onTap: (() -> Unit)? = null) = TextView(activity).apply {
        text = t; textSize = 13f
        setTextColor(if (selected) Color.WHITE else p.text)
        setPadding(dp(12), dp(7), dp(12), dp(7))
        background = if (selected) rounded(0xFFEA580C.toInt(), dp(16).toFloat()) else rounded(p.card, dp(16).toFloat(), p.border, dp(1))
        if (onTap != null) { isClickable = true; setOnClickListener { onTap() } }
    }

    protected fun progress() = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }

    protected fun error(t: String?) = label(t ?: "", 13f, p.danger).apply { visibility = if (t.isNullOrEmpty()) View.GONE else View.VISIBLE }

    protected fun onText(e: EditText, f: (String) -> Unit) = e.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: Editable?) { f(s?.toString() ?: "") }
    })

    protected fun capture(kind: MediaKind, done: (CapturedMedia?) -> Unit) {
        val cap = c.options.onCapture ?: return done(null)
        c.markCapturing(true)
        try {
            cap.capture(activity, kind) { m -> main.post { c.markCapturing(false); done(m) } }
        } catch (e: Exception) {
            c.markCapturing(false); done(null)
        }
    }

    companion object {
        private val dayFmt get() = SimpleDateFormat("d MMM yyyy, HH.mm", Locale("id", "ID"))
        fun formatTime(ms: Long?): String = if (ms == null || ms <= 0) "-" else dayFmt.format(Date(ms))

        /** Label & warna status (sama dengan Flutter). */
        fun statusLabel(s: SosStatus): Pair<String, Int> = when (s) {
            SosStatus.QUEUED -> "Menunggu sinyal" to 0xFF64748B.toInt()
            SosStatus.OPEN -> "Terkirim" to 0xFFDC2626.toInt()
            SosStatus.ACKNOWLEDGED -> "Diterima petugas" to 0xFF2563EB.toInt()
            SosStatus.IN_PROGRESS -> "Ditangani" to 0xFFD97706.toInt()
            SosStatus.RESOLVED -> "Selesai" to 0xFF16A34A.toInt()
            SosStatus.CANCELLED -> "Dibatalkan" to 0xFF64748B.toInt()
            SosStatus.FALSE_ALARM -> "Ditutup" to 0xFF64748B.toInt()
        }
    }
}

/** Baris pembungkus (chip kategori). */
internal class FlowLayout(ctx: Context, private val gap: Int) : ViewGroup(ctx) {
    override fun onMeasure(wSpec: Int, hSpec: Int) {
        val maxW = MeasureSpec.getSize(wSpec) - paddingLeft - paddingRight
        var x = 0; var y = 0; var rowH = 0
        for (i in 0 until childCount) {
            val ch = getChildAt(i)
            ch.measure(MeasureSpec.makeMeasureSpec(maxW, MeasureSpec.AT_MOST), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
            if (x > 0 && x + ch.measuredWidth > maxW) { x = 0; y += rowH + gap; rowH = 0 }
            x += ch.measuredWidth + gap
            rowH = max(rowH, ch.measuredHeight)
        }
        setMeasuredDimension(MeasureSpec.getSize(wSpec), y + rowH + paddingTop + paddingBottom)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val maxW = r - l - paddingLeft - paddingRight
        var x = 0; var y = 0; var rowH = 0
        for (i in 0 until childCount) {
            val ch = getChildAt(i)
            if (x > 0 && x + ch.measuredWidth > maxW) { x = 0; y += rowH + gap; rowH = 0 }
            ch.layout(paddingLeft + x, paddingTop + y, paddingLeft + x + ch.measuredWidth, paddingTop + y + ch.measuredHeight)
            x += ch.measuredWidth + gap
            rowH = max(rowH, ch.measuredHeight)
        }
    }
}

// ---------------------------------------------------------------------- Pengaduan

internal class ComplaintSheet(a: Activity, c: SOSFloatingButton) : Sheet(a, c) {
    private val categories = c.cfg?.complaintCategories?.takeIf { it.isNotEmpty() } ?: complaintCategoryLabels.keys.toList()
    private var category = categories.first()
    private var text = ""
    private var photo: CapturedMedia? = null
    private var sending = false
    private var err: String? = null
    private val message = input("Apa yang terjadi, di mana, sejak kapan?", multi = true)

    override fun start() {
        setTitle("Laporan pengaduan", "Bukan untuk keadaan darurat")
        onText(message) { text = it; renderForm(keepInput = true) }
        renderForm()
    }

    private val valid get() = text.trim().length >= 5

    private var sendBtn: View? = null
    private fun renderForm(keepInput: Boolean = false) {
        if (keepInput) { sendBtn?.enabled(valid && !sending); return }
        val col = column()
        col.addView(label("Jenis pengaduan", 13f, p.muted, bold = true))
        col.gap(8)
        val flow = FlowLayout(activity, dp(8))
        categories.forEach { slug -> flow.addView(chip(complaintCategoryLabel(slug), slug == category) { category = slug; renderForm() }) }
        col.addView(flow)
        col.gap(16)
        col.addView(label("Uraian", 13f, p.muted, bold = true))
        col.gap(8)
        (message.parent as? ViewGroup)?.removeView(message)
        col.addView(message)
        if (c.options.onCapture != null) {
            col.gap(12)
            val ph = photo
            if (ph == null) col.addView(button("Lampirkan foto (opsional)", p.primary, filled = false) {
                capture(MediaKind.IMAGE) { m -> if (m != null) { photo = m; renderForm() } }
            }) else {
                val row = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
                row.addView(label("Foto terlampir (${ph.bytes.size / 1024} KB)", 14f, p.ok, bold = true), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                row.addView(textButton("Hapus", p.danger) { photo = null; renderForm() })
                col.addView(row)
            }
        }
        col.gap(12)
        col.addView(error(err))
        col.gap(4)
        sendBtn = button(if (sending) "Mengirim…" else "Kirim pengaduan", 0xFFEA580C.toInt()) { send() }.enabled(valid && !sending)
        col.addView(sendBtn)
        setBody(col)
    }

    private fun send() {
        if (!valid || sending) return
        sending = true; err = null; renderForm()
        c.client.complain(category, text) { res ->
            ui {
                res.onFailure { e -> sending = false; err = e.message; renderForm(); (e as? SiagaSOSException)?.let { c.options.onError?.invoke(it) } }
                res.onSuccess { r ->
                    if (r.id != null) c.options.onComplaintSent?.invoke(r)
                    val ph = photo
                    if (ph == null) renderDone(r, null) else upload(r, ph)
                }
            }
        }
    }

    private fun upload(r: ActiveReport, ph: CapturedMedia) {
        val col = column()
        col.addView(label("Mengunggah foto…", 14f, p.text, bold = true))
        col.gap(8)
        val bar = progress()
        col.addView(bar)
        setBody(col)
        c.client.attach(r.localId, ph.bytes, ph.contentType, progress = { v -> ui { bar.progress = (v * 100).toInt() } }) { res ->
            ui { renderDone(r, res.exceptionOrNull()?.let { "Pengaduan terkirim, tetapi foto gagal diunggah: ${it.message}" }) }
        }
    }

    private fun renderDone(r: ActiveReport, warn: String?) {
        val queued = r.status == SosStatus.QUEUED
        setTitle(if (queued) "Pengaduan disimpan" else "Pengaduan terkirim")
        val col = column()
        col.addView(label(when (r.status) {
            SosStatus.QUEUED -> "Belum ada sinyal. Pengaduan disimpan dan dikirim otomatis."
            else -> "Pengaduan terkirim. Petugas akan menindaklanjuti."
        }, 15f))
        r.id?.let { col.gap(8); col.addView(label("No. ${it.take(8).uppercase()} · ${complaintCategoryLabel(r.category)}", 13f, p.muted)) }
        if (warn != null) { col.gap(8); col.addView(error(warn)) }
        col.gap(16)
        col.addView(button("Selesai", p.primary) { dismiss() })
        setBody(col)
    }
}

// ---------------------------------------------------------------------- Riwayat + detail

internal class HistorySheet(a: Activity, c: SOSFloatingButton) : Sheet(a, c) {
    override fun start() = list(refresh = true)

    private fun loading() = setBody(column().apply { gravity = Gravity.CENTER; setPadding(0, dp(24), 0, dp(24)); addView(ProgressBar(activity)) })

    private fun list(refresh: Boolean) {
        setTitle("Riwayat laporan", "SOS & pengaduan dari perangkat ini")
        loading()
        c.client.history(refresh) { res -> ui { renderList(res.getOrDefault(emptyList())) } }
    }

    private fun renderList(items: List<ReportRecord>) {
        val col = column()
        if (items.isEmpty()) {
            col.addView(label("Belum ada laporan", 15f, bold = true))
            col.gap(4)
            col.addView(label("SOS dan pengaduan yang kamu kirim akan muncul di sini.", 14f, p.muted))
        }
        items.forEachIndexed { i, r ->
            if (i > 0) col.gap(8)
            col.addView(tile(r))
        }
        col.gap(12)
        col.addView(button("Muat ulang", p.primary, filled = false) { list(refresh = true) })
        setBody(col)
    }

    private fun title(kind: ReportKind, category: String) = if (kind == ReportKind.SOS) "SOS darurat" else complaintCategoryLabel(category)

    private fun tile(r: ReportRecord): View {
        val box = card().apply { isClickable = true; setOnClickListener { detail(r.id) } }
        val head = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        head.addView(label(title(r.kind, r.category), 15f, bold = true), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        head.addView(badge(r.status))
        box.addView(head)
        box.gap(4)
        box.addView(label(formatTime(r.createdAtMs), 12.5f, p.muted))
        (r.statusMessage ?: r.message)?.let { box.gap(4); box.addView(label(it, 13.5f).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END }) }
        if (r.kind == ReportKind.SOS && r.status == SosStatus.OPEN) {
            box.gap(8)
            box.addView(textButton("Batalkan (salah tekan)", p.danger) { confirmCancel(r.id) { list(refresh = true) } })
        }
        return box
    }

    private fun badge(s: SosStatus) = statusLabel(s).let { (t, col) ->
        TextView(activity).apply {
            text = t; textSize = 12f; typeface = Typeface.DEFAULT_BOLD; setTextColor(col)
            setPadding(dp(8), dp(3), dp(8), dp(3))
            background = rounded(Color.argb(30, Color.red(col), Color.green(col), Color.blue(col)), dp(10).toFloat())
        }
    }

    private fun confirmCancel(id: String, after: () -> Unit) {
        android.app.AlertDialog.Builder(activity)
            .setTitle("Batalkan SOS?")
            .setMessage("Hanya untuk salah tekan. Petugas yang sudah menerima tidak bisa dibatalkan dari sini.")
            .setNegativeButton("Tidak", null)
            .setPositiveButton("Ya, batalkan") { _, _ ->
                c.client.cancel(id, "salah tekan") { res ->
                    ui {
                        res.onFailure { android.widget.Toast.makeText(activity, "Gagal membatalkan. Periksa koneksi lalu coba lagi.", android.widget.Toast.LENGTH_LONG).show() }
                        after()
                    }
                }
            }.show()
    }

    private fun detail(id: String) {
        setTitle("Detail laporan")
        loading()
        c.client.reportDetail(id) { res ->
            ui {
                res.onSuccess { renderDetail(it) }
                res.onFailure {
                    val col = column()
                    col.addView(label("Detail belum bisa dimuat. Periksa koneksi lalu coba lagi.", 14f, p.muted))
                    col.gap(12)
                    col.addView(button("Muat ulang", p.primary, filled = false) { detail(id) })
                    col.gap(8)
                    col.addView(button("Kembali", p.muted, filled = false) { list(refresh = false) })
                    setBody(col)
                }
            }
        }
    }

    private fun renderDetail(d: ReportDetail) {
        setTitle(title(d.kind, d.category), "No. ${d.id.take(8).uppercase()}")
        val col = column()
        col.addView(textButton("‹ Kembali") { list(refresh = false) }.apply { setPadding(0, 0, 0, dp(8)) })
        val status = card()
        val (st, stColor) = statusLabel(d.status)
        status.addView(label(st, 16f, stColor, bold = true))
        d.statusMessage?.let { status.gap(4); status.addView(label(it, 14f)) }
        col.addView(status)
        col.gap(12)
        fun field(name: String, value: String) {
            col.addView(label(name, 12.5f, p.muted, bold = true)); col.gap(2); col.addView(label(value, 14.5f)); col.gap(10)
        }
        field("Dikirim", formatTime(d.createdAtMs))
        d.acknowledgedAtMs?.let { field("Diterima", formatTime(it)) }
        d.resolvedAtMs?.let { field("Selesai", formatTime(it)) }
        d.message?.let { field("Uraian", it) }
        d.location?.let { loc ->
            field("Lokasi", "%.5f, %.5f".format(Locale.US, loc.lat, loc.lng))
            c.options.onOpenUrl?.let { open ->
                col.addView(button("Buka peta", p.primary, filled = false) { open(activity, "https://www.google.com/maps?q=${loc.lat},${loc.lng}") })
                col.gap(12)
            }
        }
        if (d.media.isNotEmpty()) {
            col.addView(label("Lampiran (${d.media.size})", 12.5f, p.muted, bold = true))
            col.gap(6)
            d.media.forEach { m ->
                val name = when (m.kind) { MediaKind.IMAGE -> "Foto"; MediaKind.VIDEO -> "Video TKP"; MediaKind.AUDIO -> "Rekaman suara" } +
                    (m.durationS?.let { " · ${it.toInt()} dtk" } ?: "") + if (m.uploadedBy == "user") " · dari petugas" else ""
                val row = card().apply {
                    addView(label(name, 14f, bold = true))
                    val url = m.url
                    val open = c.options.onOpenUrl
                    if (url != null && open != null) { isClickable = true; setOnClickListener { open(activity, url) } }
                }
                col.addView(row); col.gap(6)
            }
            col.gap(6)
        }
        if (d.timeline.isNotEmpty()) {
            col.addView(label("Riwayat status", 12.5f, p.muted, bold = true))
            col.gap(6)
            d.timeline.forEach { e ->
                val t = when (e.type) {
                    "created" -> "Laporan dikirim"
                    "status_changed" -> e.toStatus?.let { statusLabel(it).first } ?: "Status diperbarui"
                    "cancelled" -> "Dibatalkan"
                    "note" -> "Catatan"
                    "media" -> "Lampiran"
                    "whatsapp" -> "WhatsApp"
                    "push" -> "Notifikasi petugas"
                    else -> e.type
                }
                val row = column().apply { setPadding(dp(12), dp(6), 0, dp(6)); background = leftRule() }
                row.addView(label("$t · ${e.actor}", 14f, bold = true))
                row.addView(label(formatTime(e.createdAtMs), 12f, p.muted))
                e.note?.let { row.addView(label(it, 13.5f)) }
                col.addView(row)
            }
        }
        if (d.kind == ReportKind.SOS && d.status == SosStatus.OPEN) {
            col.gap(12)
            col.addView(button("Batalkan (salah tekan)", p.danger, filled = false) { confirmCancel(d.id) { detail(d.id) } })
        }
        setBody(col)
    }

    /** Garis vertikal tipis di kiri baris timeline. */
    private fun leftRule() = object : android.graphics.drawable.Drawable() {
        private val paint = Paint().apply { color = p.border }
        override fun draw(canvas: Canvas) { canvas.drawRect(0f, 0f, activity.dp(2).toFloat(), bounds.height().toFloat(), paint) }
        override fun setAlpha(alpha: Int) {}
        override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
        @Deprecated("Deprecated in Java") override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }
}

// ---------------------------------------------------------------------- Nomor darurat

internal class ContactsSheet(a: Activity, c: SOSFloatingButton) : Sheet(a, c) {
    private var items = c.client.emergencyContacts()
    private var err: String? = null
    private var syncNote: String? = null
    private var adding = false

    override fun start() {
        setTitle("Nomor darurat", "Dikabari WhatsApp setiap kamu menekan SOS")
        render()
    }

    private fun save(next: List<EmergencyContact>) {
        err = null
        c.client.setEmergencyContacts(next) { res ->
            ui {
                res.onSuccess { synced -> items = c.client.emergencyContacts(); syncNote = if (synced) "Tersimpan" else "Tersimpan di perangkat, disinkronkan saat online" }
                res.onFailure { e -> err = e.message }
                render()
            }
        }
    }

    private fun render() {
        val col = column()
        col.addView(label("Petugas keamanan & penerima SOS yang diatur pengelola tetap dikabari. Pesan berisi nama, lokasi, dan link peta.", 13f, p.muted))
        col.gap(12)
        if (items.isEmpty()) {
            col.addView(label("Belum ada nomor darurat. Tambahkan keluarga, rekan, atau satpam (maks. $MAX_ACTIVE_EMERGENCY_CONTACTS aktif) yang perlu tahu saat kamu menekan SOS.", 14f))
            col.gap(12)
        }
        items.forEachIndexed { i, ct ->
            val row = card().apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            val info = column()
            info.addView(label(ct.name + (ct.role?.let { " · $it" } ?: ""), 15f, bold = true))
            info.addView(label("+${ct.phone}", 13f, p.muted))
            row.addView(info, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            @Suppress("DEPRECATION")
            val sw = Switch(activity).apply {
                isChecked = ct.active
                contentDescription = "Aktif"
                setOnCheckedChangeListener { _, on ->
                    if (on && items.count { it.active } >= MAX_ACTIVE_EMERGENCY_CONTACTS) {
                        err = "Maksimal $MAX_ACTIVE_EMERGENCY_CONTACTS nomor aktif. Hapus atau nonaktifkan salah satu untuk mengganti."
                        render(); return@setOnCheckedChangeListener
                    }
                    save(items.mapIndexed { j, x -> if (j == i) x.copy(active = on) else x })
                }
            }
            row.addView(sw)
            row.addView(textButton("Hapus", p.danger) { save(items.filterIndexed { j, _ -> j != i }) })
            col.addView(row)
            col.gap(8)
        }
        col.addView(error(err))
        syncNote?.let { col.addView(label(it, 12.5f, p.muted)) }
        col.gap(8)
        if (adding) col.addView(form()) else if (items.size < MAX_EMERGENCY_CONTACTS) col.addView(button("Tambah nomor", p.primary) { adding = true; err = null; render() })
        setBody(col)
    }

    private fun form(): View {
        val col = card()
        val name = input("Nama")
        val role = input("Mis. Istri, Kakak, Pemilik toko")
        val phone = input("Nomor WhatsApp", type = InputType.TYPE_CLASS_PHONE)
        col.addView(name); col.gap(8); col.addView(role); col.gap(8); col.addView(phone); col.gap(12)
        val row = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(button("Batal", p.muted, filled = false) { adding = false; render() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { rightMargin = dp(8) })
        row.addView(button("Simpan", p.primary) {
            val n = toWhatsAppNumber(phone.text.toString())
            err = when {
                name.text.isBlank() -> "Nama kontak wajib diisi"
                n == null -> "Nomor WhatsApp tidak valid (contoh 0812xxxxxxx)"
                items.any { it.phone == n } -> "Nomor ini sudah ada di daftar."
                else -> null
            }
            if (err != null) { render(); return@button }
            val active = items.count { it.active } < MAX_ACTIVE_EMERGENCY_CONTACTS
            adding = false
            save(items + EmergencyContact(name.text.toString().trim(), n!!, role.text.toString().trim().ifEmpty { null }, active))
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        col.addView(row)
        return col
    }
}

// ---------------------------------------------------------------------- Rekam TKP

internal class TkpSheet(a: Activity, c: SOSFloatingButton, private var report: ActiveReport) : Sheet(a, c), SosListener {
    private enum class Phase { PROMPT, NOTE, SENDING, DONE }
    private var phase = Phase.PROMPT
    private var video: CapturedMedia? = null
    private var uploaded = false
    private var err: String? = null
    private val note = input("Catatan singkat", multi = true)
    private var bar: ProgressBar? = null

    override fun start() {
        c.client.addListener(this)
        dialog.setCancelable(false)
        render()
    }

    override fun onClosed() { c.client.removeListener(this) }

    override fun onStatus(report: ActiveReport) {
        if (report.localId == this.report.localId) ui { this.report = report; if (phase == Phase.PROMPT) render() }
    }

    private fun header(col: LinearLayout) {
        val queued = report.status == SosStatus.QUEUED
        setTitle(if (queued) "SOS disimpan" else "SOS terkirim",
            if (queued) "Belum ada sinyal, terkirim otomatis" else c.cfg?.recipientText?.ifBlank { null } ?: "Petugas keamanan sudah diberi tahu")
        if (c.sirenOn) {
            col.addView(button("Matikan sirene", p.danger, filled = false) { c.options.siren?.stop(); c.render(); render() })
            col.gap(12)
        }
    }

    private fun render() {
        val col = column()
        header(col)
        when (phase) {
            Phase.PROMPT -> {
                col.addView(label("Rekam kondisi TKP?", 17f, bold = true))
                col.gap(4)
                col.addView(label("Video singkat membantu petugas memahami situasi sebelum tiba di lokasi.", 14f, p.muted))
                col.gap(10)
                val chips = FlowLayout(activity, dp(8))
                listOf("Maks. ${c.options.tkpSeconds} dtk", "Lokasi otomatis", "Catatan").forEach { chips.addView(chip(it, false)) }
                col.addView(chips)
                col.gap(16)
                col.addView(button("Ya, Rekam Sekarang", c.options.color) { record() })
                col.gap(8)
                col.addView(button("Tidak, nanti saja", p.muted, filled = false) { dismiss() })
            }
            Phase.NOTE -> {
                val v = video!!
                val row = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
                row.addView(label("Rekaman siap dikirim" + (v.durationS?.let { " · ${it.toInt()} dtk" } ?: ""), 15f, p.ok, bold = true),
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                row.addView(textButton("Rekam ulang") { record() })
                col.addView(row)
                col.gap(12)
                col.addView(label("Catatan kejadian", 13f, p.muted, bold = true))
                col.gap(6)
                (note.parent as? ViewGroup)?.removeView(note)
                col.addView(note)
                col.gap(8)
                col.addView(error(err))
                col.gap(8)
                col.addView(button("Kirim ke Petugas", c.options.color) { send() })
                col.gap(8)
                col.addView(button("Batal", p.muted, filled = false) { confirmDrop() })
            }
            Phase.SENDING -> {
                col.addView(label(if (uploaded) "Menyimpan catatan…" else "Mengirim rekaman…", 15f, bold = true))
                col.gap(8)
                bar = progress().also { col.addView(it) }
            }
            Phase.DONE -> {
                col.addView(label("Rekaman TKP terkirim", 17f, p.ok, bold = true))
                col.gap(4)
                col.addView(label("Video dan catatanmu sudah diterima petugas keamanan.", 14f, p.muted))
                col.gap(16)
                col.addView(button("Selesai", p.primary) { dismiss() })
            }
        }
        setBody(col)
    }

    private fun record() {
        capture(MediaKind.VIDEO) { m ->
            if (closed || m == null) return@capture
            video = m; uploaded = false; err = null; phase = Phase.NOTE
            render()
        }
    }

    private fun confirmDrop() {
        android.app.AlertDialog.Builder(activity)
            .setTitle("Batalkan rekaman?")
            .setMessage("Rekaman TKP belum dikirim. SOS tetap sudah terkirim ke petugas.")
            .setNegativeButton("Lanjut kirim", null)
            .setPositiveButton("Ya, batalkan") { _, _ -> dismiss() }
            .show()
    }

    private fun send() {
        val v = video ?: return
        phase = Phase.SENDING; err = null; render()
        val text = note.text.toString().trim()
        fun fail(e: Throwable) = ui {
            (e as? SiagaSOSException)?.let { c.options.onError?.invoke(it) }
            err = e.message ?: "Rekaman gagal dikirim. Periksa koneksi lalu coba lagi."
            phase = Phase.NOTE; render()
        }
        fun afterUpload() {
            if (text.isEmpty()) { ui { phase = Phase.DONE; render() }; return }
            c.client.addNote(report.localId, text) { r -> r.onSuccess { ui { phase = Phase.DONE; render() } }; r.onFailure { fail(it) } }
        }
        if (uploaded) afterUpload() else c.client.attach(report.localId, v.bytes, v.contentType, v.durationS,
            progress = { pr -> ui { bar?.progress = (pr * 100).toInt() } }) { r ->
            r.onSuccess { uploaded = true; afterUpload() }
            r.onFailure { fail(it) }
        }
    }
}
