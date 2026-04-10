import 'package:flutter/material.dart';

class VerificationStatusWidget extends StatelessWidget {
  final String status; // idle | pending | verified | expired | error

  const VerificationStatusWidget({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _buildContent(key: ValueKey(status)),
    );
  }

  Widget _buildContent({required Key key}) {
    switch (status) {
      case 'pending':
        return Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Waiting for SMS...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        );

      case 'verified':
        return Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle, color: Colors.greenAccent, size: 48),
            SizedBox(height: 12),
            Text(
              'Verified!',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );

      case 'expired':
        return Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.timer_off, color: Colors.orange, size: 48),
            SizedBox(height: 12),
            Text(
              'Verification expired',
              style: TextStyle(color: Colors.orange, fontSize: 14),
            ),
          ],
        );

      case 'error':
        return Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: TextStyle(color: Colors.redAccent, fontSize: 14),
            ),
          ],
        );

      default: // idle
        return const SizedBox.shrink(key: ValueKey('idle'));
    }
  }
}
