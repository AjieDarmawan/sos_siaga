package id.siagasos.sample

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            addView(TextView(this@MainActivity).apply { text = "Aplikasi contoh. Tombol SOS melayang ada di pojok kanan bawah."; textSize = 18f })
            addView(Button(this@MainActivity).apply { text = "Buka halaman kedua"; setOnClickListener { startActivity(Intent(this@MainActivity, SecondActivity::class.java)) } })
        })
    }
}

class SecondActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "Halaman kedua: tombol SOS tetap tampil tanpa kode tambahan."; textSize = 18f; setPadding(48, 48, 48, 48) })
    }
}
