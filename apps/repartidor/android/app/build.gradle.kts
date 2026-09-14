import java.io.FileInputStream
import java.util.Properties

// Firma de release. La clave NO esta en el repo: se lee de key.properties
// (ruta en la variable MY_KEY_PROPERTIES, o android/key.properties). En GitHub
// Actions la arma el workflow con los secretos ANDROID_KEYSTORE_*.
//
// Siempre la misma clave: Android no deja instalar una actualizacion firmada
// con otra, y la app se actualiza sola desde los Releases.
val firma = Properties().apply {
    val archivo = file(System.getenv("MY_KEY_PROPERTIES") ?: rootProject.file("key.properties").path)
    if (archivo.exists()) FileInputStream(archivo).use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.modoya.modo_ya_repartidor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.modoya.modo_ya_repartidor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (firma.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(firma.getProperty("storeFile"))
                storePassword = firma.getProperty("storePassword")
                keyAlias = firma.getProperty("keyAlias")
                keyPassword = firma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sin key.properties (desarrollo) firma con la clave de debug.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider, para pasarle el APK descargado al instalador.
    implementation("androidx.core:core-ktx:1.13.1")
}
