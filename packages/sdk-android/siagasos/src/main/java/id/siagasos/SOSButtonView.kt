package id.siagasos

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.animation.LinearInterpolator
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Tombol SOS siap pakai: tahan N detik (default dari portal) untuk mengirim, cincin progres, getar, dan teks status.
 *
 * ```kotlin
 * sosButton.bind(sos, category = "kriminal") { result -> ... }
 * ```
 * Di XML: `<id.siagasos.SOSButtonView android:layout_width="200dp" android:layout_height="200dp" />`
 */
class SOSButtonView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs), SosListener {
    var color: Int = Color.parseColor("#DC2626")
        set(v) { field = v; invalidate() }
    var holdSeconds: Int? = null

    private var client: SiagaSOS? = null
    private var category = "general"
    private var message: String? = null
    private var onResult: ((Result<ActiveReport>) -> Unit)? = null
    private var report: ActiveReport? = null
    private var sending = false
    private var label = "SOS"
    private var progress = 0f
    private var animator: ValueAnimator? = null

    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textAlign = Paint.Align.CENTER; isFakeBoldText = true }
    private val arc = RectF()

    init {
        isClickable = true
        isFocusable = true
        contentDescription = "Tombol darurat. Tahan untuk mengirim laporan SOS."
    }

    /** Hubungkan ke klien. [onResult] dipanggil di main thread setelah laporan terkirim / masuk antrian / gagal. */
    @JvmOverloads
    fun bind(client: SiagaSOS, category: String = "general", message: String? = null, onResult: ((Result<ActiveReport>) -> Unit)? = null) {
        this.client?.removeListener(this)
        this.client = client
        this.category = category
        this.message = message
        this.onResult = onResult
        client.addListener(this)
        client.getConfig { r -> r.onSuccess { cfg -> label = cfg.buttonText.ifBlank { "SOS" }; if (holdSeconds == null) holdSeconds = cfg.holdSeconds; invalidate() } }
    }

    override fun onDetachedFromWindow() {
        client?.removeListener(this)
        animator?.cancel()
        super.onDetachedFromWindow()
    }

    override fun onStatus(report: ActiveReport) {
        if (this.report == null || this.report?.localId == report.localId) post { this.report = report; invalidate() }
    }

    private val active get() = report?.status?.isTerminal == false

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (client == null || active || sending) return super.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { startHold(); return true }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { if (progress < 1f) cancelHold(); return true }
        }
        return super.onTouchEvent(e)
    }

    private fun startHold() {
        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        animator?.cancel()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = (holdSeconds ?: 3) * 1000L
            interpolator = LinearInterpolator()
            addUpdateListener { progress = it.animatedValue as Float; invalidate(); if (progress >= 1f) fire() }
            start()
        }
    }

    private fun cancelHold() {
        animator?.cancel()
        ValueAnimator.ofFloat(progress, 0f).apply { duration = 200; addUpdateListener { progress = it.animatedValue as Float; invalidate() }; start() }
    }

    private fun fire() {
        if (sending) return
        sending = true
        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        invalidate()
        client?.trigger(category, message) { r ->
            sending = false
            progress = 0f
            r.onSuccess { report = it }
            onResult?.invoke(r)
            invalidate()
        }
    }

    private fun statusText(): String {
        if (sending) return "Mengirim…"
        val r = report ?: return label
        return r.statusMessage ?: when (r.status) {
            SosStatus.QUEUED -> "Menunggu sinyal…"
            SosStatus.OPEN -> "Terkirim. Menunggu petugas…"
            SosStatus.ACKNOWLEDGED -> "Petugas menerima laporan"
            SosStatus.IN_PROGRESS -> "Petugas menangani"
            SosStatus.RESOLVED -> "Selesai"
            SosStatus.CANCELLED -> "Dibatalkan"
            SosStatus.FALSE_ALARM -> "Alarm palsu"
        }
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val r = minOf(width, height) / 2f
        val stroke = r * 0.08f
        ring.strokeWidth = stroke
        ring.color = (color and 0x00FFFFFF) or 0x33000000
        arc.set(cx - r + stroke, cy - r + stroke, cx + r - stroke, cy + r - stroke)
        canvas.drawOval(arc, ring)
        if (progress > 0f) { ring.color = color; canvas.drawArc(arc, -90f, 360f * progress, false, ring) }
        fill.color = if (active) Color.parseColor("#475569") else color
        canvas.drawCircle(cx, cy, r * (0.74f - progress * 0.04f), fill)
        val t = if (active || sending) statusText() else label
        text.textSize = if (t.length <= 4) r * 0.34f else r * 0.12f
        val lines = if (t.length <= 4) listOf(t) else wrap(t, 16)
        val lh = text.textSize * 1.2f
        lines.forEachIndexed { i, line -> canvas.drawText(line, cx, cy - (lines.size - 1) * lh / 2 + i * lh - (text.ascent() + text.descent()) / 2, text) }
    }

    private fun wrap(s: String, max: Int): List<String> = s.split(' ').fold(mutableListOf("")) { acc, w ->
        if ((acc.last() + " " + w).trim().length > max) acc.add(w) else acc[acc.lastIndex] = (acc.last() + " " + w).trim(); acc
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.stateDescription = statusText().takeIf { android.os.Build.VERSION.SDK_INT >= 30 }
    }
}
