import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Kunci & URL API dari local.properties (tidak di-commit):
//   siagasos.key=pk_test_...        siagasos.url=http://10.0.2.2:4000
val local = Properties().apply { rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) } }

android {
    namespace = "id.siagasos.sample"
    compileSdk = 35
    defaultConfig {
        applicationId = "id.demosiaga.kurir" // terdaftar di app demo "Aplikasi Kurir (Android)" (pnpm seed:demo)
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "SOS_KEY", "\"${local.getProperty("siagasos.key", "")}\"")
        buildConfigField("String", "SOS_URL", "\"${local.getProperty("siagasos.url", "http://10.0.2.2:4000")}\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }

dependencies { implementation(project(":siagasos")) }
