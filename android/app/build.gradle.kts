import java.util.Properties
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}
val credentials = Properties().apply {
    val env = rootProject.file("../.env")
    if (env.exists()) env.inputStream().use { load(it) }
}
fun credential(name: String) = System.getenv(name) ?: credentials.getProperty(name, "").trim().trim('"', '\'')
android {
    namespace = "ad.neko.telisten"
    compileSdk = 36
    defaultConfig {
        applicationId = "ad.neko.player"
        minSdk = 26
        targetSdk = 36
        versionCode = System.getenv("ANDROID_VERSION_CODE")?.toInt() ?: 3
        versionName = "1.1.0"
        buildConfigField("int", "TELEGRAM_API_ID", credential("TELEGRAM_API_ID").toIntOrNull()?.toString() ?: "0")
        buildConfigField("String", "TELEGRAM_API_HASH", "\"${credential("TELEGRAM_API_HASH").replace("\\", "\\\\").replace("\"", "\\\"")}\"")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    buildTypes { release { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }
}
dependencies {
    implementation("com.github.pedroSG94.RootEncoder:rtmp:2.6.4")
    implementation(files("libs/tdlib-0.1.0.aar"))
    implementation(platform("androidx.compose:compose-bom:2025.09.01"))
    implementation("androidx.compose.material3:material3:1.5.0-alpha04")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-session:1.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.google.zxing:core:3.5.3")
    testImplementation("junit:junit:4.13.2")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
val verifyTdlib by tasks.registering {
    doLast { check(file("libs/tdlib-0.1.0.aar").isFile) { "TDLib is missing. Run ./scripts/setup-tdlib.sh from android/ first." } }
}
tasks.named("preBuild") { dependsOn(verifyTdlib) }
