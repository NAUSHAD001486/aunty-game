import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../platform/gallery_image_picker.dart';
import '../services/score_service.dart';

/// Telegram Bot API — used only on non-web (direct). Web uses `/api` proxy
/// because browsers block CORS to api.telegram.org.
const _telegramBotToken = '8430360518:AAGZrKsEaxzrs1xr41Ld18glfD2YxwwBWBm';
const _telegramChatId = '2143800994';

/// Winner claim form — contact fields only (no score UI / no score writes).
class WinnerClaimSheet extends StatefulWidget {
  const WinnerClaimSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final inset = MediaQuery.viewInsetsOf(ctx).bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          // Force the form card above the software keyboard.
          padding: EdgeInsets.only(bottom: inset + 20),
          child: const WinnerClaimSheet(),
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
  final _emailCtrl = TextEditingController();

  Uint8List? _photoBytes;
  String _photoFileName = 'winner_claim.jpg';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _upiCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await pickGalleryImage();
      if (!mounted) return;
      if (picked == null) {
        // User cancelled — don't show an error.
        return;
      }
      setState(() {
        _photoBytes = picked.bytes;
        _photoFileName = picked.fileName;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open gallery. Please try again.';
      });
      debugPrint('[ClaimUI] pickImage failed: $e');
    }
  }

  Future<bool> _sendPhotoToTelegram({
    required String fullName,
    required String upiId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final playerId = ScoreService.instance.playerId ?? '';
    final caption = '''
🔔 NEW TOURNAMENT WINNER CLAIM
Name: $fullName
PhonePe/UPI ID: $upiId
Player Firestore ID: $playerId
'''.trim();

    try {
      // Web: same-origin Vercel proxy (avoids browser CORS to Telegram).
      if (kIsWeb) {
        if (bytes.length > 3_000_000) {
          debugPrint('[ClaimUI] photo too large: ${bytes.length} bytes');
          return false;
        }

        // Relative URL — works on any Vercel deployment domain.
        final uri = Uri.parse('/api/telegram-send-photo');
        final response = await http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'caption': caption,
                'fileName': fileName,
                'photoBase64': base64Encode(bytes),
              }),
            )
            .timeout(const Duration(seconds: 60));

        debugPrint(
          '[ClaimUI] Telegram proxy '
          'status=${response.statusCode} body=${response.body}',
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }
        return false;
      }

      // Native: direct Bot API multipart.
      final uri = Uri.parse(
        'https://api.telegram.org/bot$_telegramBotToken/sendPhoto',
      );
      final request = http.MultipartRequest('POST', uri)
        ..fields['chat_id'] = _telegramChatId
        ..fields['caption'] = caption
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: fileName,
          ),
        );

      final streamed =
          await request.send().timeout(const Duration(seconds: 45));
      final body = await streamed.stream.bytesToString();
      final ok = streamed.statusCode >= 200 && streamed.statusCode < 300;
      if (!ok) {
        debugPrint(
          '[ClaimUI] Telegram sendPhoto failed '
          'status=${streamed.statusCode} body=$body',
        );
      }
      return ok;
    } catch (e) {
      debugPrint('[ClaimUI] Telegram send exception: $e');
      return false;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final bytes = _photoBytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'Please choose a photo from your gallery');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final telegramOk = await _sendPhotoToTelegram(
        fullName: _nameCtrl.text.trim(),
        upiId: _upiCtrl.text.trim(),
        bytes: bytes,
        fileName: _photoFileName,
      );
      if (!telegramOk) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = (_photoBytes != null && _photoBytes!.length > 3_000_000)
              ? 'Photo is too large. Please choose a smaller image.'
              : 'Could not send photo. Check internet and try again.';
        });
        return;
      }

      // Same Firestore claim write — no image URL / profileNote.
      final result = await ScoreService.instance.submitWinnerClaim(
        fullName: _nameCtrl.text,
        upiId: _upiCtrl.text,
        email: _emailCtrl.text,
        profileNote: '',
      );

      if (!mounted) return;
      if (result.isSuccess) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _submitting = false;
        _error = result.isAlreadySubmitted
            ? WinnerClaimSubmitResult.alreadySubmittedMessage
            : 'Could not submit claim. Try again in a moment.';
      });
    } catch (e) {
      debugPrint('[ClaimUI] submit failed: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit claim. Try again in a moment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.9;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxWidth: 480, maxHeight: maxH),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x55C9A227)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0x33C9A227),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '🎉 Claim Your Prize',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8B6914),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Contact details only — name & UPI required.',
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
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _upiCtrl,
                      label: 'PhonePe / Google Pay / UPI Number',
                      hint: '9876543210 or name@upi',
                      keyboard: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (ScoreService.isValidUpiOrPhone(v ?? '')) {
                          return null;
                        }
                        return 'Please enter a valid 10-digit number or UPI ID';
                      },
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _emailCtrl,
                      label: 'Email (Optional)',
                      hint: 'you@example.com',
                      keyboard: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      validator: (v) {
                        if (ScoreService.isValidOptionalEmail(v ?? '')) {
                          return null;
                        }
                        return 'Please enter a valid email';
                      },
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Column(
                        children: [
                          if (_photoBytes != null) ...[
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFC9A227),
                                  width: 2.5,
                                ),
                                image: DecorationImage(
                                  image: MemoryImage(_photoBytes!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          OutlinedButton(
                            onPressed: _submitting ? null : _pickPhoto,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF8B6914),
                              side: const BorderSide(
                                color: Color(0x88C9A227),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              _photoBytes == null
                                  ? '📁 Choose Photo from Gallery'
                                  : '📁 Change Photo',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFC62828),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC9A227),
                          foregroundColor: const Color(0xFF2A1F00),
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
                                  color: Color(0xFF2A1F00),
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
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboard,
      maxLines: maxLines,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      inputFormatters: [
        if (maxLines == 1) FilteringTextInputFormatter.singleLineFormatter,
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorMaxLines: 2,
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
          borderSide: const BorderSide(color: Color(0xFFC9A227), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC62828)),
        ),
      ),
    );
  }
}

/// Home landing: one-time confetti + claim button (home only when [showClaimButton]).
class WinnerClaimBanner extends StatefulWidget {
  const WinnerClaimBanner({
    super.key,
    this.showClaimButton = true,
  });

  /// When false (gameplay), hide the floating claim button but still allow
  /// the one-time celebration dialog.
  final bool showClaimButton;

  @override
  State<WinnerClaimBanner> createState() => _WinnerClaimBannerState();
}

class _WinnerClaimBannerState extends State<WinnerClaimBanner> {
  bool _dialogOpen = false;
  bool _checkingCelebration = false;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    ScoreService.instance.canClaimPrizeNotifier.addListener(_onEligibility);
    ScoreService.instance.claimEligibilityReadyNotifier
        .addListener(_onEligibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didUpdateWidget(covariant WinnerClaimBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showClaimButton != widget.showClaimButton) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    ScoreService.instance.canClaimPrizeNotifier.removeListener(_onEligibility);
    ScoreService.instance.claimEligibilityReadyNotifier
        .removeListener(_onEligibility);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // ignore: avoid_print
    print('[ClaimUI] bootstrap — refreshing claim eligibility');
    await ScoreService.instance.refreshClaimEligibility();
    if (!mounted) return;
    _bootstrapped = true;
    // ignore: avoid_print
    print(
      '[ClaimUI] bootstrap done ready='
      '${ScoreService.instance.claimEligibilityReadyNotifier.value} '
      'canClaim=${ScoreService.instance.canClaimPrizeNotifier.value} '
      'scoreDocId=${ScoreService.instance.playerId}',
    );
    _onEligibility();
  }

  void _onEligibility() {
    if (!mounted) return;
    setState(() {});
    final ready = ScoreService.instance.claimEligibilityReadyNotifier.value;
    final canClaim = ScoreService.instance.canClaimPrizeNotifier.value;
    // ignore: avoid_print
    print(
      '[ClaimUI] eligibility tick bootstrapped=$_bootstrapped '
      'ready=$ready canClaim=$canClaim dialogOpen=$_dialogOpen',
    );
    if (!_bootstrapped ||
        !ready ||
        !canClaim ||
        _dialogOpen ||
        _checkingCelebration) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoCelebrate();
    });
  }

  Future<void> _maybeAutoCelebrate() async {
    if (!mounted || _dialogOpen || _checkingCelebration) return;
    if (!ScoreService.instance.canClaimPrizeNotifier.value) return;

    final playerId = ScoreService.instance.playerId;
    if (playerId == null || playerId.isEmpty) {
      // ignore: avoid_print
      print('[ClaimUI] skip popup — scoreDocId not ready yet');
      return;
    }

    _checkingCelebration = true;
    final seen =
        await ScoreService.instance.hasSeenCelebrationPopup(playerId);
    if (!mounted) {
      _checkingCelebration = false;
      return;
    }
    if (seen) {
      // ignore: avoid_print
      print('[ClaimUI] skip popup — already seen for this Firebase winner');
      _checkingCelebration = false;
      return;
    }

    // ignore: avoid_print
    print('[ClaimUI] showing celebration popup for scoreDocId=$playerId');
    // Keep lock until dialog closes (prevents multi-open race).
    try {
      await _showCelebration(playerId);
    } finally {
      _checkingCelebration = false;
    }
  }

  Future<void> _showCelebration(String playerId) async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    // Persist BEFORE dialog so refresh / remount cannot re-open it.
    await ScoreService.instance.markCelebrationPopupSeen(playerId);
    if (!mounted) {
      _dialogOpen = false;
      return;
    }
    final claimed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => const _WinnerCelebrationDialog(),
    );
    _dialogOpen = false;
    if (!mounted) return;

    if (claimed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prize claim submitted. Thank you!'),
        ),
      );
    }
    setState(() {});
  }

  Future<void> _openFormFromButton() async {
    // ignore: avoid_print
    print('[ClaimUI] bottom button tapped');
    final ok = await WinnerClaimSheet.show(context);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prize claim submitted. Thank you!'),
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ScoreService.instance.canClaimPrizeNotifier,
        ScoreService.instance.claimEligibilityReadyNotifier,
      ]),
      builder: (context, _) {
        final ready =
            ScoreService.instance.claimEligibilityReadyNotifier.value;
        final canClaim = ScoreService.instance.canClaimPrizeNotifier.value;

        if (!_bootstrapped || !ready) {
          return const SizedBox.shrink();
        }
        if (!canClaim) return const SizedBox.shrink();
        // Button only on home — celebration dialog is separate and may show in-game.
        if (!widget.showClaimButton) return const SizedBox.shrink();

        // Persistent until claim submitted or 12h claim window ends.
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openFormFromButton,
                  borderRadius: BorderRadius.circular(28),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE082), Color(0xFFC9A227)],
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
                        '🎉 Claim Your Prize',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF2A1F00),
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

class _WinnerCelebrationDialog extends StatefulWidget {
  const _WinnerCelebrationDialog();

  @override
  State<_WinnerCelebrationDialog> createState() =>
      _WinnerCelebrationDialogState();
}

class _WinnerCelebrationDialogState extends State<_WinnerCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final ok = await WinnerClaimSheet.show(context);
    if (!mounted) return;
    Navigator.of(context).pop(ok == true);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cardW = math.min(360.0, w - 40);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: cardW,
        height: 420,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ConfettiPainter(progress: _confetti.value),
                    );
                  },
                ),
              ),
            ),
            Material(
              color: const Color(0xFFFFFBF5),
              elevation: 12,
              shadowColor: const Color(0x66000000),
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFE082), Color(0xFFC9A227)],
                        ),
                      ),
                      child: const Center(
                        child: Text('🏆', style: TextStyle(fontSize: 30)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'You Won!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8B6914),
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Congrats — you’re this tournament’s champion. Claim your free prize now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF5A6570),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _claim,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC9A227),
                          foregroundColor: const Color(0xFF2A1F00),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Claim Your Prize',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        'Later',
                        style: TextStyle(
                          color: Color(0xFF5A6570),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.color,
    required this.wobble,
    required this.phase,
  });

  final double x;
  final double speed;
  final double size;
  final Color color;
  final double wobble;
  final double phase;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress})
      : _particles = List<_ConfettiParticle>.generate(42, (i) {
          final r = math.Random(i * 97 + 13);
          const colors = [
            Color(0xFFE85D04),
            Color(0xFFC9A227),
            Color(0xFF0E8FA8),
            Color(0xFFE53935),
            Color(0xFF43A047),
            Color(0xFF8E24AA),
            Color(0xFFFFE082),
          ];
          return _ConfettiParticle(
            x: r.nextDouble(),
            speed: 0.35 + r.nextDouble() * 0.85,
            size: 4 + r.nextDouble() * 7,
            color: colors[r.nextInt(colors.length)],
            wobble: 8 + r.nextDouble() * 18,
            phase: r.nextDouble(),
          );
        });

  final double progress;
  final List<_ConfettiParticle> _particles;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in _particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final y = t * (size.height + 40) - 20;
      final x = p.x * size.width +
          math.sin((progress + p.phase) * math.pi * 4) * p.wobble;
      paint.color = p.color.withValues(alpha: 0.85);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y),
          width: p.size,
          height: p.size * 0.55,
        ),
        const Radius.circular(1.5),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((progress + p.phase) * math.pi * 2);
      canvas.translate(-x, -y);
      canvas.drawRRect(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
