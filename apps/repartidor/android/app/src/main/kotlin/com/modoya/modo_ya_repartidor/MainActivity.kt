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
                            val uri = FileProvider.getUriForFile(this, "$packageName.actualizaciones", File(ruta))
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("instalar", e.message, null)
                        }
                    }
                    // Para elegir el APK de 32 o 64 bits.
                    "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                    else -> result.notImplemented()
                }
            }
    }
}
