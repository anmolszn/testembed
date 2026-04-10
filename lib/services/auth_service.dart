import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  /// Sends OTP to [phoneNumber]. Calls [onCodeSent] when ready for OTP input,
  /// [onAutoVerified] on Android auto-retrieval, [onError] on failure.
  Future<void> verifyPhone({
    required String phoneNumber,
    required VoidCallback onCodeSent,
    required ValueChanged<UserCredential> onAutoVerified,
    required ValueChanged<String> onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: _resendToken,
      timeout: const Duration(seconds: 60),

      // Android auto-retrieval / instant verification
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final result = await _auth.signInWithCredential(credential);
          onAutoVerified(result);
        } catch (e) {
          onError(e.toString());
        }
      },

      verificationFailed: (FirebaseAuthException e) {
        onError(e.message ?? 'Verification failed');
      },

      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        onCodeSent();
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  /// Verifies the OTP [smsCode] entered by the user.
  Future<UserCredential> verifyOTP(String smsCode) async {
    if (_verificationId == null) {
      throw FirebaseAuthException(
        code: 'no-verification-id',
        message: 'No verification in progress. Please request OTP again.',
      );
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() => _auth.signOut();
}
