import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const String _embedHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .kpoint-embedded-video { width: 100% !important; }
  </style>
</head>
<body>
  <div
    data-video-host="showcase-qa.zencite.in"
    data-kvideo-id="gcc-1935251d-77e4-49a9-9310-4cc91a5b8c53"
    data-samesite="true"
    data-ar="9:16"
    data-video-params='{"autoplay":true,"muted":false,"loop":true,"playsinline":true,"showPlayIconOnMobile":"false"}'
    class="kpoint-embedded-video"
    style="width:320px">
  </div>
  <script type="text/javascript"
    src="https://showcase-qa.zencite.in/assets/orca/media/embed/player-silk.js">
  </script>
</body>
</html>
''';

class CircularVideoPopup extends StatefulWidget {
  // videoUrl kept for API compatibility but unused — embed is hardcoded above
  final String videoUrl;
  const CircularVideoPopup({super.key, required this.videoUrl});

  @override
  State<CircularVideoPopup> createState() => _CircularVideoPopupState();
}

class _CircularVideoPopupState extends State<CircularVideoPopup> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadHtmlString(_embedHtml, baseUrl: 'https://showcase-qa.zencite.in');
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Blurred + dimmed background ──────────────────────────────────
        Positioned.fill(
          child: GestureDetector(
            onTap: _close,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.35)),
            ),
          ),
        ),

        // ── Circular video ───────────────────────────────────────────────
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.25),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.4),
                      blurRadius: 60,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: WebViewWidget(controller: _controller),
                ),
              ),
              const SizedBox(height: 24),
              // ── Close button ─────────────────────────────────────────
              GestureDetector(
                onTap: _close,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Close',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
