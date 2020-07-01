package org.fitrecord.android

import android.util.Log
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

class ChannelEngineProxy(from: DartExecutor, to: DartExecutor, name: String) {

    private lateinit var toChannel: MethodChannel
    private lateinit var fromChannel: MethodChannel

    init {
        fromChannel = MethodChannel(from.binaryMessenger, name).apply {
            setMethodCallHandler { call, result -> passCall(toChannel, call, result) }

        }
        toChannel = MethodChannel(to.binaryMessenger, name).apply {
            setMethodCallHandler { call, result -> passCall(fromChannel, call, result) }
        }
    }

    private fun passCall(channel: MethodChannel, call: MethodCall, result: Result) {
        val handler = object : Result {
            override fun notImplemented() {
                Log.w("ChannelEngineProxy", "Not implemented: ${call.method}")
                result.error("Not implemented", "Not implemented: ${call.method}", null)
            }

            override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                Log.w("ChannelEngineProxy", "Error: ${call.method} - $errorCode, $errorMessage")
                result.error(errorCode, errorMessage, errorDetails)
            }

            override fun success(res: Any?) {
                result.success(res)
            }

        }
        channel.invokeMethod(call.method, call.arguments, handler)
    }

}