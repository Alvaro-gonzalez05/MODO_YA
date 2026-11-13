package com.modoya.modo_ya_repartidor

import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal "modoya/actualizaciones": lo usa el aviso de version nueva
 * (packages/my_ui/lib/src/actualizaciones) para abrir el instalador de Android
 * con el APK que bajo la app. Android siempre le pide confirmacion al usuario.
 */
class MainActivity : FlutterActivity() {
    /** El APK dentro de cacheDir: si vino de otra carpeta se copia, porque el
     *  FileProvider solo puede compartir lo que esta ahi. */
    private fun enCache(apk: File): File {
        val cache = cacheDir.canonicalFile
        if (apk.canonicalPath.startsWith(cache.path + File.separator)) return apk
        val copia = File(cache, apk.name)
        apk.copyTo(copia, overwrite = true)
        apk.delete()
        return copia
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "modoya/actualizaciones")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "instalarApk" -> {
                        val ruta = call.argument<String>("ruta")
                        if (ruta == null) {
                            result.error("sin_ruta", "Falta la ruta del APK", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(this, "$packageName.actualizaciones", enCache(File(ruta)))
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("instalar", e.message, null)
                        }
                    }
                    // Donde bajar el APK. Tiene que ser cacheDir, que es lo
                    // unico que comparte el FileProvider (res/xml/rutas_actualizacion):
                    // la carpeta temporal de Dart en Android es code_cache, y con
                    // ella el instalador fallaba con "Failed to find configured
                    // root" (v1.15 -> v1.16).
                    "carpetaDescargas" -> result.success(cacheDir.absolutePath)
                    // Para elegir el APK de 32 o 64 bits.
                    "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                    else -> result.notImplemented()
                }
            }
    }
}
