import 'package:flutter/services.dart';
import '../models/sim_card.dart';

class SimService {
  static const _channel =
      MethodChannel('com.example.testembed_flutter/sim_sender');

  Future<List<SimCard>> getSimList() async {
    final List<dynamic> result = await _channel.invokeMethod('getSimList');
    return result.map((e) => SimCard.fromMap(e as Map)).toList();
  }

  Future<bool> sendVerificationSms({
    required int subscriptionId,
    required String toNumber,
    required String token,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('sendSms', {
        'subscriptionId': subscriptionId,
        'toNumber': toNumber,
        'message': 'VERIFY_$token',
      });
      return result;
    } on PlatformException {
      return false;
    }
  }
}
