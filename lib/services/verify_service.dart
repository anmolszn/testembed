import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const String _baseUrl = 'https://YOUR_APP.onrender.com'; // replace after deploy

class StartVerifyResponse {
  final String token;
  final String vmn;

  StartVerifyResponse({required this.token, required this.vmn});

  factory StartVerifyResponse.fromJson(Map<String, dynamic> json) =>
      StartVerifyResponse(token: json['token'] as String, vmn: json['vmn'] as String);
}

class VerifyService {
  Future<StartVerifyResponse> startVerification(String phoneNumber) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/start'),
            headers: {
              'Content-Type': 'application/json',
              'bypass-tunnel-reminder': 'true',
            },
            body: jsonEncode({'phoneNumber': phoneNumber}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      return StartVerifyResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } on SocketException {
      throw Exception('Cannot reach backend at $_baseUrl — is the server running?');
    } on TimeoutException {
      throw Exception('Connection timed out — check firewall or IP ($_baseUrl)');
    }
  }

  Future<String> checkStatus(String token) async {
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/auth/status?token=$token'),
            headers: {'bypass-tunnel-reminder': 'true'},
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      return (jsonDecode(res.body) as Map<String, dynamic>)['status'] as String;
    } on SocketException catch (e) {
      throw Exception('Cannot reach backend: $e');
    } on TimeoutException {
      return 'pending'; // silent — keep polling
    }
  }
}
