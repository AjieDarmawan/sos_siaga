plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    `maven-publish`
}

android {
    namespace = "id.siagasos"
    compileSdk = 35
    defaultConfig {
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
        buildConfigField("String", "SDK_VERSION", "\"0.1.0\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions { unitTests.isReturnDefaultValues = true }
    publishing { singleVariant("release") { withSourcesJar() } }
}

kotlin { jvmToolchain(17) }

// Tanpa dependency runtime: HttpURLConnection + org.json bawaan Android.
dependencies {
    testImplementation("junit:junit:4.12")
    testImplementation("org.json:json:20180813") // org.json di android.jar hanya stub saat unit test JVM
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = "id.siagasos"
                artifactId = "siagasos-android"
                version = "0.1.0"
            }
        }
    }
}
