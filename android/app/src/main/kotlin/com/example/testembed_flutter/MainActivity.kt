package com.example.testembed_flutter

import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.testembed_flutter/sim_sender"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "getSimList" -> {
                        try {
                            val sm = getSystemService(TELEPHONY_SUBSCRIPTION_SERVICE)
                                    as SubscriptionManager
                            val subs: List<SubscriptionInfo> =
                                sm.activeSubscriptionInfoList ?: emptyList()

                            val simList = subs.map { sub ->
                                mapOf(
                                    "slotIndex"      to sub.simSlotIndex,
                                    "carrierName"    to (sub.carrierName?.toString() ?: "SIM ${sub.simSlotIndex + 1}"),
                                    "subscriptionId" to sub.subscriptionId,
                                    "phoneNumber"    to (sub.number ?: ""),
                                )
                            }
                            result.success(simList)
                        } catch (e: SecurityException) {
                            result.error("PERMISSION_DENIED", "READ_PHONE_STATE permission required", null)
                        } catch (e: Exception) {
                            result.error("SIM_ERROR", e.message, null)
                        }
                    }

                    "sendSms" -> {
                        try {
                            val subscriptionId = call.argument<Int>("subscriptionId")!!
                            val toNumber      = call.argument<String>("toNumber")!!
                            val message       = call.argument<String>("message")!!

                            @Suppress("DEPRECATION")
                            val smsManager = SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                            smsManager.sendTextMessage(toNumber, null, message, null, null)
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("PERMISSION_DENIED", "SEND_SMS permission required", null)
                        } catch (e: Exception) {
                            result.error("SMS_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
