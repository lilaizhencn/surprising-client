package com.surprising.surprising_client

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat

class MainActivity : FlutterFragmentActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val permissionRequestCode = 7241

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "surprising/kyc-permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestCameraAndMicrophone") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (permissionResult != null) {
                    result.error("PERMISSION_REQUEST_PENDING", "A permission request is already in progress", null)
                    return@setMethodCallHandler
                }
                val permissions = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
                if (permissions.all { ActivityCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }) {
                    result.success(true)
                } else {
                    permissionResult = result
                    ActivityCompat.requestPermissions(this, permissions, permissionRequestCode)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
    }
}
