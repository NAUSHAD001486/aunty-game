import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/score_service.dart';

const _kGold = Color(0xFFC9A227);
const _kGoldDeep = Color(0xFF8B6914);
const _kInkOnGold = Color(0xFF2A1F00);

/// Centered, keyboard-safe prize-claim dialog for the confirmed tournament
/// winner. Pops with confetti and validates the UPI / phone field strictly.
class WinnerClaimSheet extends StatefulWidget {
  const WinnerClaimSheet({super.key});

  /// Present as a centered dialog (auto-popup or button tap).
  static Future<bool> show(BuildContext context) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Claim your prize',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, __, ___) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return Stack(
          children: [
            // Confetti celebration behind the card.
            const Positioned.fill(
              child: IgnorePointer(child: _ConfettiOverlay()),
            ),
            Center(
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
                child: FadeTransition(
                  opacity: anim,
                  child: const WinnerClaimSheet(),
                ),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  State<WinnerClaimSheet> createState() => _WinnerClaimSheetState();
}

class _WinnerClaimSheetState extends State<WinnerClaimSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _upiCtrl.dispose();
    _photoCtrl.dispose();
    super.dispose();
  }

  String? _validateUpi(String? v) {
    const msg = 'Please enter a valid 10-digit number or UPI ID';
    final t = (v ?? '').trim();
    if (t.isEmpty) return msg;
    final isUpi = t.contains('@') && t.length >= 5;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    final isPhone = digits.length >= 10;
    if (!isUpi && !isPhone) return msg;
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok = await ScoreService.instance.submitWinnerClaim(
      fullName: _nameCtrl.text,
      upiId: _upiCtrl.text,
      profileNote: _photoCtrl.text,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = 'Could not submit claim. Try again in a moment.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    // Cap the card height so it never overflows; inner content scrolls.
    final maxCardHeight = size.height - 40;

    return Material(
      color: Colors.transparent,
      child: Padding(
        // Push the whole card above the keyboard.
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: viewInsets > 0 ? viewInsets + 12 : 12,
          top: 12,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: maxCardHeight,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF5),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x55C9A227)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _WinnerBadge(),
                    const SizedBox(height: 14),
                    const Text(
                      '🎉 You Won! Claim Your Prize',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _kGoldDeep,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Free to play — fill this once to receive your reward.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF5A6570),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _field(
                      controller: _nameCtrl,
                      label: 'Full Name',
                      hint: 'As on your UPI account',
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _upiCtrl,
                      label: 'PhonePe / Google Pay / UPI ID',
                      hint: 'name@upi or 10-digit number',
                      keyboard: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateUpi,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _photoCtrl,
                      label: 'Profile photo URL or short note',
                      hint: 'https://… or “Use my game name”',
                      maxLines: 2,
                      textInputAction: TextInputAction.done,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFC62828),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kGold,
                          foregroundColor: _kInkOnGold,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: _kInkOnGold,
                                ),
                              )
                            : const Text(
                                'Submit',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).maybePop(false),
                        child: const Text(
                          'Maybe later',
                          style: TextStyle(
                            color: Color(0xFF5A6570),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    TextInputAction? textInputAction,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboard,
      textInputAction: textInputAction,
      maxLines: maxLines,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      inputFormatters: [
        if (maxLines == 1) FilteringTextInputFormatter.singleLineFormatter,
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x33C9A227)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x33C9A227)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kGold, width: 1.4),
        ),
      ),
    );
  }
}

class _WinnerBadge extends StatelessWidget {
  const _WinnerBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFFFFE082), _kGold],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x55C9A227),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Center(
          child: Text('🏆', style: TextStyle(fontSize: 30)),
        ),
      ),
    );
  }
}

/// Floating CTA + auto-popup — mounted while
/// [ScoreService.canClaimPrizeNotifier] is true. The dialog opens automatically
/// once per session; the button remains as a fallback if dismissed.
class WinnerClaimBanner extends StatefulWidget {
  const WinnerClaimBanner({super.key});

  @override
  State<WinnerClaimBanner> createState() => _WinnerClaimBannerState();
}

class _WinnerClaimBannerState extends State<WinnerClaimBanner> {
  bool _autoShown = false;
  bool _dialogOpen = false;

  Future<void> _openDialog() async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    final ok = await WinnerClaimSheet.show(context);
    _dialogOpen = false;
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prize claim submitted. Thank you!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScoreService.instance.canClaimPrizeNotifier,
      builder: (context, canClaim, _) {
        if (!canClaim) {
          // Reset so a fresh eligibility (e.g. admin re-opens claim) re-pops.
          _autoShown = false;
          return const SizedBox.shrink();
        }

        // Auto-popup the moment the eligible winner is detected.
        if (!_autoShown) {
          _autoShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _openDialog());
        }

        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openDialog,
                  borderRadius: BorderRadius.circular(28),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE082), _kGold],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55C9A227),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      child: Text(
                        '🎉 You Won! Claim Your Prize',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _kInkOnGold,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Confetti ───────────────────────────────────────────────────────────────

/// Lightweight timer/animation-driven confetti burst. Runs once for a few
/// seconds behind the claim dialog, then goes quiet (no ongoing cost).
class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _rng = math.Random();

  static const _colors = [
    Color(0xFFC9A227),
    Color(0xFFFFE082),
    Color(0xFFE85D04),
    Color(0xFF0E8FA8),
    Color(0xFF2E7D32),
    Color(0xFFD81B60),
  ];

  @override
  void initState() {
    super.initState();
    _particles = List.generate(90, (_) => _spawn());
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();
  }

  _Particle _spawn() {
    return _Particle(
      x: _rng.nextDouble(),
      startY: -0.15 - _rng.nextDouble() * 0.4,
      speed: 0.35 + _rng.nextDouble() * 0.75,
      drift: (_rng.nextDouble() - 0.5) * 0.35,
      size: 6 + _rng.nextDouble() * 8,
      color: _colors[_rng.nextInt(_colors.length)],
      rotation: _rng.nextDouble() * math.pi,
      rotationSpeed: (_rng.nextDouble() - 0.5) * 6,
      shape: _rng.nextBool() ? _Shape.rect : _Shape.circle,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

enum _Shape { rect, circle }

class _Particle {
  _Particle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.drift,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.shape,
  });

  final double x;
  final double startY;
  final double speed;
  final double drift;
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;
  final _Shape shape;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_Particle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Fade out over the last 25% of the run.
    final fade = progress < 0.75 ? 1.0 : (1 - (progress - 0.75) / 0.25);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final y = (p.startY + progress * p.speed * 1.6) * size.height;
      if (y < -20 || y > size.height + 20) continue;
      final x = (p.x + p.drift * progress) * size.width;
      final angle = p.rotation + p.rotationSpeed * progress;

      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      if (p.shape == _Shape.rect) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.55,
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
