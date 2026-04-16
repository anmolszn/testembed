import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/sim_card.dart';
import '../services/sim_service.dart';
import '../services/verify_service.dart';
import '../widgets/verification_status_widget.dart';
import 'home_screen.dart';

// ── Video IDs ─────────────────────────────────────────────────────────────────
const _videoIds = [
  'gcc-1935251d-77e4-49a9-9310-4cc91a5b8c53', // page 1
  'gcc-c5c99057-7f48-42cf-85fd-2819ea7a8be6', // page 2
  'gcc-7b7ed2c1-fcc8-4221-8b34-26826f96b97d', // page 3
];

// ── HTML builder ──────────────────────────────────────────────────────────────
// Each call gets a unique timestamp so the script URL bypasses the WebView
// disk cache, and the div ID is unique so KPoint always re-initializes fresh.
String _buildVideoHtml(String videoId, {bool loop = true}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final loopParam = loop ? '"loop":true,' : '';
  return '''<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body{width:100vw;height:100vh;background:#000;overflow:hidden}
    #kp-$ts,#kp-$ts>div,#kp-$ts iframe{
      position:fixed!important;top:0!important;left:0!important;
      width:100vw!important;height:100vh!important;object-fit:cover!important;
    }
  </style>
</head>
<body>
  <div
    id="kp-$ts"
    data-video-host="showcase-qa.zencite.in"
    data-kvideo-id="$videoId"
    data-samesite="true"
    data-ar="9:16"
    data-video-params='{"autoplay":true,"muted":true,"playsinline":true,$loopParam"showPlayIconOnMobile":"false","showMuteIconOnMobile":"false"}'
    class="kpoint-embedded-video"
    style="width:100vw;height:100vh">
  </div>
  <script src="https://showcase-qa.zencite.in/assets/orca/media/embed/player-silk.js?_=$ts"></script>
  <script>
    function hideUnmuteControls(root){
      if(!root) return;
      const selectors = [
        '[aria-label*="mute" i]',
        '[aria-label*="volume" i]',
        '[title*="mute" i]',
        '[title*="volume" i]',
        '[class*="mute" i]',
        '[class*="volume" i]',
        '[id*="mute" i]',
        '[id*="volume" i]'
      ];
      selectors.forEach(function(sel){
        root.querySelectorAll(sel).forEach(function(el){
          el.style.display = 'none';
          el.style.visibility = 'hidden';
          el.style.opacity = '0';
          el.style.pointerEvents = 'none';
        });
      });
    }

    function hideAll(){
      hideUnmuteControls(document);
      document.querySelectorAll('iframe').forEach(function(frame){
        try{
          hideUnmuteControls(frame.contentDocument || frame.contentWindow.document);
        }catch(e){}
      });
    }

    setInterval(hideAll, 400);
    setTimeout(hideAll, 100);
  </script>
</body>
</html>''';
}

// ── Mock comments ─────────────────────────────────────────────────────────────
const _mockComments = [
  _Comment('Riya S.', 'This app is super smooth! 🔥', '2m ago'),
  _Comment('Arjun M.', 'SIM binding works perfectly on my Redmi.', '5m ago'),
  _Comment('Sneha K.', 'Love the circular video player ❤️', '12m ago'),
  _Comment('Dev T.', 'Finally an app that does OTP without pain.', '18m ago'),
  _Comment('Priya R.', 'Clean UI. Great work!', '25m ago'),
];

class _Comment {
  final String name;
  final String text;
  final String time;
  const _Comment(this.name, this.text, this.time);
}

// ── Screen ────────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final WebViewController _wvc;
  late final PageController _pageController;
  int _currentPage = 0;

  final _simService = SimService();
  final _verifyService = VerifyService();
  List<SimCard> _sims = [];
  bool _loadingSims = false;
  SimCard? _selectedSim;
  final _phoneCtrl = TextEditingController();

  // Android SIM verification state
  String _verifyStatus = 'idle';
  String? _token;
  int _countdown = 60;
  Timer? _pollTimer;
  Timer? _countdownTimer;

  // iOS Firebase OTP state
  final _iosPhoneCtrl = TextEditingController();
  final _iosOtpCtrl = TextEditingController();
  String? _verificationId;
  bool _otpSent = false;
  bool _otpLoading = false;
  String? _otpError;

  // ── WebView setup ────────────────────────────────────────────────────────
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

    _wvc = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setMediaPlaybackRequiresUserGesture(false);
    _pageController = PageController();
    _loadPage(0);
  }

  Future<void> _loadPage(int page) async {
    // Wipe localStorage so KPoint doesn't reuse stale video-init state
    await _wvc.clearLocalStorage();
    await _wvc.loadHtmlString(
      _buildVideoHtml(_videoIds[page], loop: page != 1),
      baseUrl: 'https://showcase-qa.zencite.in',
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _phoneCtrl.dispose();
    _iosPhoneCtrl.dispose();
    _iosOtpCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(page,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    setState(() => _currentPage = page);
    _loadPage(page);
  }

  // ── SIM ──────────────────────────────────────────────────────────────────
  Future<void> _loadSims() async {
    setState(() => _loadingSims = true);
    final s = await [Permission.phone, Permission.sms].request();
    if (s[Permission.phone] != PermissionStatus.granted ||
        s[Permission.sms] != PermissionStatus.granted) {
      setState(() => _loadingSims = false);
      _snack('Phone and SMS permissions are required.');
      return;
    }
    try {
      final sims = await _simService.getSimList();
      setState(() { _sims = sims; _loadingSims = false; });
    } catch (e) {
      setState(() => _loadingSims = false);
      _snack('Could not read SIM list: $e');
    }
  }

  // ── Verification ─────────────────────────────────────────────────────────
  Future<void> _startVerification(SimCard sim) async {
    final phone = _phoneCtrl.text.trim().isNotEmpty
        ? _phoneCtrl.text.trim() : sim.phoneNumber;
    if (phone.isEmpty) { _snack('Please enter your phone number.'); return; }
    setState(() { _selectedSim = sim; _verifyStatus = 'pending'; _countdown = 60; });
    try {
      final resp = await _verifyService.startVerification(phone);
      _token = resp.token;
      final sent = await _simService.sendVerificationSms(
        subscriptionId: sim.subscriptionId,
        toNumber: resp.vmn,
        token: resp.token,
      );
      if (!sent) {
        setState(() => _verifyStatus = 'error');
        _snack('Failed to send SMS. Check SEND_SMS permission.');
        return;
      }
      _startPolling();
      _startCountdown();
    } catch (e) {
      setState(() => _verifyStatus = 'error');
      _snack('Verification failed: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_token == null) return;
      try {
        final status = await _verifyService.checkStatus(_token!);
        setState(() => _verifyStatus = status);
        if (status == 'verified') {
          _stopTimers();
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        } else if (status == 'expired') { _stopTimers(); }
      } catch (_) {}
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_countdown <= 0) {
        _countdownTimer?.cancel();
        if (_verifyStatus == 'pending') setState(() => _verifyStatus = 'expired');
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _stopTimers() { _pollTimer?.cancel(); _countdownTimer?.cancel(); }

  void _resetVerification() {
    _stopTimers();
    setState(() { _verifyStatus = 'idle'; _selectedSim = null; _token = null; _countdown = 60; });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // Background video
        Positioned.fill(child: WebViewWidget(controller: _wvc)),

        // Gradient
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.75),
                  ],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Content
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildDots(),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [_buildPage1(), _buildPage2(), _buildPage3()],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDots() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(3, (i) {
      final active = i == _currentPage;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: active ? 20 : 8, height: 8,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white38,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }),
  );

  // ── Page 1 ───────────────────────────────────────────────────────────────
  Widget _buildPage1() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Spacer(flex: 3),
      const Text('OTP +\nVideo Test',
          style: TextStyle(color: Colors.white, fontSize: 42,
              fontWeight: FontWeight.bold, height: 1.15)),
      const SizedBox(height: 16),
      Text('Firebase Phone Auth · Circular Video Player · SIM Binding',
          style: TextStyle(color: Colors.white.withOpacity(0.75),
              fontSize: 14, height: 1.5)),
      const Spacer(flex: 2),
      SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: () => _goToPage(1),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Get Started',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 32),
    ]),
  );

  // ── Page 2 ───────────────────────────────────────────────────────────────
  Widget _buildPage2() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Spacer(flex: 2),
      const Text("What's Inside",
          style: TextStyle(color: Colors.white, fontSize: 34,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 24),
      _FeatureTile(icon: Icons.verified_user_outlined,
          title: 'SIM Binding Auth',
          subtitle: 'Verify silently via your own SIM — no OTP needed'),
      const SizedBox(height: 16),
      _FeatureTile(icon: Icons.circle,
          title: 'Circular Video Player',
          subtitle: 'Spotlight-focus embed with blur backdrop'),
      const SizedBox(height: 16),
      _FeatureTile(icon: Icons.comment_outlined,
          title: 'Rich UI Components',
          subtitle: 'Cards, sheets, and smooth animations'),
      const Spacer(flex: 2),
      SizedBox(
        width: double.infinity, height: 54,
        child: OutlinedButton.icon(
          onPressed: _showComments,
          icon: const Icon(Icons.comment_rounded, color: Colors.white),
          label: const Text('View Comments',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: () => _goToPage(2),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Continue →',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 32),
    ]),
  );

  void _showComments() {
    // Stop the page-2 video loop now that user opened comments
    _wvc.runJavaScript(
      'document.querySelectorAll("video").forEach(function(v){v.loop=false;});');

    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Comments',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Divider(color: Colors.white12, height: 16),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _mockComments.length,
                itemBuilder: (_, i) {
                  final c = _mockComments[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.deepPurple.shade300,
                          child: Text(c.name[0],
                              style: const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(c.name,
                                  style: const TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text(c.time,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                            ]),
                            const SizedBox(height: 4),
                            Text(c.text,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14)),
                          ],
                        )),
                        const Icon(Icons.favorite_border,
                            color: Colors.white38, size: 18),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: 16, right: 16, top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Row(children: [
                const CircleAvatar(
                  radius: 16, backgroundColor: Colors.deepPurple,
                  child: Icon(Icons.person, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true, fillColor: Colors.white10,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () { ctrl.clear(); Navigator.pop(ctx); },
                  child: const Text('Post',
                      style: TextStyle(color: Colors.deepPurpleAccent,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── iOS Firebase OTP ─────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final phone = _iosPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _otpError = 'Enter your phone number');
      return;
    }
    setState(() { _otpLoading = true; _otpError = null; });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone.startsWith('+') ? phone : '+91$phone',
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential cred) async {
        // Auto-verification (Android only, won't fire on iOS)
        await FirebaseAuth.instance.signInWithCredential(cred);
        if (mounted) Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() { _otpLoading = false; _otpError = e.message ?? 'Verification failed'; });
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() { _verificationId = verificationId; _otpSent = true; _otpLoading = false; });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _verifyOtp() async {
    final code = _iosOtpCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _otpError = 'Enter the 6-digit OTP');
      return;
    }
    setState(() { _otpLoading = true; _otpError = null; });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() { _otpLoading = false; _otpError = e.message ?? 'Invalid OTP'; });
    }
  }

  // ── Page 3 ───────────────────────────────────────────────────────────────
  Widget _buildPage3() => Platform.isIOS ? _buildPage3Ios() : _buildPage3Android();

  // ── Page 3 iOS — Firebase OTP ─────────────────────────────────────────────
  Widget _buildPage3Ios() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      const Text('Verify Your\nNumber',
          style: TextStyle(color: Colors.white, fontSize: 36,
              fontWeight: FontWeight.bold, height: 1.2)),
      const SizedBox(height: 8),
      Text('We\'ll send a one-time code to your phone number.',
          style: TextStyle(color: Colors.white.withOpacity(0.7),
              fontSize: 13, height: 1.5)),
      const SizedBox(height: 28),

      if (!_otpSent) ...[
        TextField(
          controller: _iosPhoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Phone number',
            labelStyle: const TextStyle(color: Colors.white60),
            hintText: '+91XXXXXXXXXX',
            hintStyle: const TextStyle(color: Colors.white30),
            prefixIcon: const Icon(Icons.phone, color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white30),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _otpLoading ? null : _sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _otpLoading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send OTP',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: Colors.white)),
          ),
        ),
      ],

      if (_otpSent) ...[
        const Text('Enter the 6-digit code sent to your number',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 16),
        TextField(
          controller: _iosOtpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(color: Colors.white, fontSize: 24,
              letterSpacing: 8, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            filled: true, fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _otpLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _otpLoading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify OTP',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: Colors.white)),
          ),
        ),
        TextButton(
          onPressed: () => setState(() { _otpSent = false; _iosOtpCtrl.clear(); }),
          child: const Text('Change number',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ],

      if (_otpError != null) ...[
        const SizedBox(height: 12),
        Text(_otpError!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
      ],

      const SizedBox(height: 32),
      Center(
        child: TextButton(
          onPressed: () => Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen())),
          child: const Text('Skip for now',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ),
      const SizedBox(height: 24),
    ]),
  );

  // ── Page 3 Android — SIM binding ──────────────────────────────────────────
  Widget _buildPage3Android() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      const Text('Verify Your\nSIM',
          style: TextStyle(color: Colors.white, fontSize: 36,
              fontWeight: FontWeight.bold, height: 1.2)),
      const SizedBox(height: 8),
      Text('We\'ll silently send a verification SMS from your SIM.\nNo OTP needed.',
          style: TextStyle(color: Colors.white.withOpacity(0.7),
              fontSize: 13, height: 1.5)),
      const SizedBox(height: 28),

      if (_verifyStatus == 'idle') ...[
        if (_sims.isEmpty)
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: _loadingSims ? null : _loadSims,
              icon: _loadingSims
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.sim_card),
              label: Text(_loadingSims ? 'Loading SIMs...' : 'Load SIM Cards'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        if (_sims.isNotEmpty) ...[
          const Text('Select a SIM to verify with:',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          ..._sims.map((sim) => _SimTile(
            sim: sim,
            selected: _selectedSim?.subscriptionId == sim.subscriptionId,
            onTap: () {
              setState(() => _selectedSim = sim);
              _phoneCtrl.text = sim.phoneNumber;
            },
          )),
          const SizedBox(height: 16),
          if (_selectedSim != null) ...[
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Your phone number',
                labelStyle: const TextStyle(color: Colors.white60),
                hintText: '+91XXXXXXXXXX',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.phone, color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () => _startVerification(_selectedSim!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Start Verification',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ],
      ],

      if (_verifyStatus != 'idle')
        Center(child: Column(children: [
          const SizedBox(height: 16),
          VerificationStatusWidget(status: _verifyStatus),
          if (_verifyStatus == 'pending') ...[
            const SizedBox(height: 16),
            Text('Expires in $_countdown s',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
          if (_verifyStatus == 'expired' || _verifyStatus == 'error') ...[
            const SizedBox(height: 20),
            TextButton(
              onPressed: _resetVerification,
              child: const Text('Try Again',
                  style: TextStyle(color: Colors.white,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ])),

      const SizedBox(height: 32),
      Center(
        child: TextButton(
          onPressed: () => Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen())),
          child: const Text('Skip for now',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ),
      const SizedBox(height: 24),
    ]),
  );
}

// ── Helper widgets ────────────────────────────────────────────────────────────
class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white12, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
    const SizedBox(width: 16),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w600, fontSize: 14)),
        Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    )),
  ]);
}

class _SimTile extends StatelessWidget {
  final SimCard sim;
  final VoidCallback onTap;
  final bool selected;
  const _SimTile({required this.sim, required this.onTap, required this.selected});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? Colors.deepPurple.withOpacity(0.4) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? Colors.deepPurpleAccent : Colors.white24),
      ),
      child: Row(children: [
        Icon(Icons.sim_card,
            color: selected ? Colors.deepPurpleAccent : Colors.white54),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${sim.displayName}  ·  SIM ${sim.slotIndex + 1}',
                style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600, fontSize: 14)),
            if (sim.phoneNumber.isNotEmpty)
              Text(sim.phoneNumber,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        )),
        if (selected)
          const Icon(Icons.check_circle,
              color: Colors.deepPurpleAccent, size: 20),
      ]),
    ),
  );
}
