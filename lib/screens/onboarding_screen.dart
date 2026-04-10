import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/sim_card.dart';
import '../services/sim_service.dart';
import '../services/verify_service.dart';
import '../widgets/verification_status_widget.dart';
import 'home_screen.dart';

// ── Background video HTML (KPoint embed, no blur, full screen) ────────────────
const String _bgVideoHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    html, body { width:100vw; height:100vh; background:#000; overflow:hidden; }
    .kpoint-embedded-video { width:100% !important; height:100vh !important; }
    .kpoint-embedded-video iframe { width:100% !important; height:100% !important; }
  </style>
</head>
<body>
  <div
    data-video-host="showcase-qa.zencite.in"
    data-kvideo-id="gcc-1935251d-77e4-49a9-9310-4cc91a5b8c53"
    data-samesite="true"
    data-ar="9:16"
    data-video-params='{"autoplay":true,"muted":true,"loop":true,"showPlayIconOnMobile":"false"}'
    class="kpoint-embedded-video"
    style="width:100%;height:100vh">
  </div>
  <script type="text/javascript"
    src="https://showcase-qa.zencite.in/assets/orca/media/embed/player-silk.js">
  </script>
  <script>
    setTimeout(function() {
      document.querySelectorAll('video').forEach(function(v) {
        if (v.paused) { v.muted = true; v.play().catch(function(){}); }
      });
    }, 2500);
  </script>
</body>
</html>
''';

// ── Mock comments for Instagram-style card ────────────────────────────────────
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

// ── Main widget ───────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final WebViewController _bgController;
  late final PageController _pageController;
  int _currentPage = 0;

  // SIM verification state
  final _simService = SimService();
  final _verifyService = VerifyService();
  List<SimCard> _sims = [];
  bool _loadingSims = false;
  SimCard? _selectedSim;
  final _phoneController = TextEditingController();

  String _verifyStatus = 'idle'; // idle | pending | verified | expired | error
  String? _token;
  int _countdown = 60;
  Timer? _pollTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _bgController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _bgController.runJavaScript('''
          setTimeout(function() {
            document.querySelectorAll('video').forEach(function(v) {
              if (v.paused) { v.muted = true; v.play().catch(function(){}); }
            });
          }, 2500);
        '''),
      ))
      ..loadHtmlString(_bgVideoHtml, baseUrl: 'https://showcase-qa.zencite.in');
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = page);
  }

  // ── Page 3: Load SIMs ────────────────────────────────────────────────────
  Future<void> _loadSims() async {
    setState(() => _loadingSims = true);

    final statuses = await [Permission.phone, Permission.sms].request();
    if (statuses[Permission.phone] != PermissionStatus.granted ||
        statuses[Permission.sms] != PermissionStatus.granted) {
      setState(() => _loadingSims = false);
      _showSnack('Phone and SMS permissions are required.');
      return;
    }

    try {
      final sims = await _simService.getSimList();
      setState(() {
        _sims = sims;
        _loadingSims = false;
      });
    } catch (e) {
      setState(() => _loadingSims = false);
      _showSnack('Could not read SIM list: $e');
    }
  }

  // ── Page 3: Start verification ───────────────────────────────────────────
  Future<void> _startVerification(SimCard sim) async {
    final phone = _phoneController.text.trim().isNotEmpty
        ? _phoneController.text.trim()
        : sim.phoneNumber;

    if (phone.isEmpty) {
      _showSnack('Please enter your phone number.');
      return;
    }

    setState(() {
      _selectedSim = sim;
      _verifyStatus = 'pending';
      _countdown = 60;
    });

    try {
      final response = await _verifyService.startVerification(phone);
      _token = response.token;

      final sent = await _simService.sendVerificationSms(
        subscriptionId: sim.subscriptionId,
        toNumber: response.vmn,
        token: response.token,
      );

      if (!sent) {
        setState(() => _verifyStatus = 'error');
        _showSnack('Failed to send SMS. Check SEND_SMS permission.');
        return;
      }

      _startPolling();
      _startCountdown();
    } catch (e) {
      setState(() => _verifyStatus = 'error');
      _showSnack('Verification failed: $e');
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
          _stopPolling();
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        } else if (status == 'expired') {
          _stopPolling();
        }
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

  void _stopPolling() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
  }

  void _resetVerification() {
    _stopPolling();
    setState(() {
      _verifyStatus = 'idle';
      _selectedSim = null;
      _token = null;
      _countdown = 60;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Background video (full screen, no blur)
          SizedBox.expand(
            child: WebViewWidget(controller: _bgController),
          ),

          // 2. Gradient overlay — subtle dark fade at bottom for readability
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

          // 3. Page content
          SafeArea(
            child: Column(
              children: [
                // Page indicator dots
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _buildDots(),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildPage1(),
                      _buildPage2(),
                      _buildPage3(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Page 1: Welcome ──────────────────────────────────────────────────────
  Widget _buildPage1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 3),
          const Text(
            'OTP +\nVideo Test',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Firebase Phone Auth · Circular Video Player · SIM Binding',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const Spacer(flex: 2),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => _goToPage(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Page 2: Features + Instagram card ───────────────────────────────────
  Widget _buildPage2() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          const Text(
            'What\'s Inside',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          _FeatureTile(
            icon: Icons.verified_user_outlined,
            title: 'SIM Binding Auth',
            subtitle: 'Verify silently via your own SIM — no OTP needed',
          ),
          const SizedBox(height: 16),
          _FeatureTile(
            icon: Icons.circle,
            title: 'Circular Video Player',
            subtitle: 'Spotlight-focus embed with blur backdrop',
          ),
          const SizedBox(height: 16),
          _FeatureTile(
            icon: Icons.comment_outlined,
            title: 'Rich UI Components',
            subtitle: 'Cards, sheets, and smooth animations',
          ),
          const Spacer(flex: 2),
          // Instagram card button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _showInstagramCard,
              icon: const Icon(Icons.comment_rounded, color: Colors.white),
              label: const Text(
                'View Comments',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => _goToPage(2),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Continue →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showInstagramCard() {
    final commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Comments',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Divider(color: Colors.white12, height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
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
                            child: Text(
                              c.name[0],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      c.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      c.time,
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c.text,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.favorite_border,
                              color: Colors.white38, size: 18),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Comment input
              Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  top: 8,
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.deepPurple,
                      child: Icon(Icons.person, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: commentController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
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
                      onTap: () {
                        commentController.clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        'Post',
                        style: TextStyle(
                          color: Colors.deepPurpleAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Page 3: SIM Verification ─────────────────────────────────────────────
  Widget _buildPage3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Verify Your\nSIM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'ll silently send a verification SMS from your SIM.\nNo OTP needed.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          if (_verifyStatus == 'idle') ...[
            // ── Step 1: Load SIMs ──────────────────────────────────────
            if (_sims.isEmpty)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _loadingSims ? null : _loadSims,
                  icon: _loadingSims
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.sim_card),
                  label: Text(_loadingSims ? 'Loading SIMs...' : 'Load SIM Cards'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

            // ── Step 2: SIM list ───────────────────────────────────────
            if (_sims.isNotEmpty) ...[
              const Text(
                'Select a SIM to verify with:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ..._sims.map((sim) => _SimTile(
                    sim: sim,
                    onTap: () {
                      setState(() => _selectedSim = sim);
                      if (sim.phoneNumber.isEmpty) {
                        _phoneController.clear();
                      } else {
                        _phoneController.text = sim.phoneNumber;
                      }
                    },
                    selected: _selectedSim?.subscriptionId == sim.subscriptionId,
                  )),
              const SizedBox(height: 16),

              if (_selectedSim != null) ...[
                // Phone number field (prefilled if available, else manual)
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Your phone number',
                    labelStyle: const TextStyle(color: Colors.white60),
                    hintText: '+91XXXXXXXXXX',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon:
                        const Icon(Icons.phone, color: Colors.white54),
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
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _startVerification(_selectedSim!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Start Verification',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ],

          // ── Verification in progress / done ────────────────────────
          if (_verifyStatus != 'idle') ...[
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  VerificationStatusWidget(status: _verifyStatus),
                  if (_verifyStatus == 'pending') ...[
                    const SizedBox(height: 16),
                    Text(
                      'Expires in $_countdown s',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                  if (_verifyStatus == 'expired' || _verifyStatus == 'error') ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _resetVerification,
                      child: const Text(
                        'Try Again',
                        style: TextStyle(
                            color: Colors.white,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Skip for now (testing)
          Center(
            child: TextButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              child: const Text(
                'Skip for now',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimTile extends StatelessWidget {
  final SimCard sim;
  final VoidCallback onTap;
  final bool selected;

  const _SimTile({
    required this.sim,
    required this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.withOpacity(0.4) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.deepPurpleAccent : Colors.white24,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.sim_card,
                color: selected ? Colors.deepPurpleAccent : Colors.white54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sim.displayName}  ·  SIM ${sim.slotIndex + 1}',
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (sim.phoneNumber.isNotEmpty)
                    Text(
                      sim.phoneNumber,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: Colors.deepPurpleAccent, size: 20),
          ],
        ),
      ),
    );
  }
}
