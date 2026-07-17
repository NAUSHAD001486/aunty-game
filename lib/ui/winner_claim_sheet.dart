import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/score_service.dart';

/// Modal form for the confirmed 12h tournament winner to claim their prize.
class WinnerClaimSheet extends StatefulWidget {
  const WinnerClaimSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WinnerClaimSheet(),
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

  Future<void> _submit() async {
    if (_submitting) return;
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _upiCtrl,
                    label: 'PhonePe / Google Pay / UPI ID',
                    hint: 'name@upi',
                    keyboard: TextInputType.emailAddress,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Required';
                      if (!t.contains('@') && t.length < 10) {
                        return 'Enter a valid UPI ID or number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _photoCtrl,
                    label: 'Profile photo URL or short note',
                    hint: 'https://… or “Use my game name”',
                    maxLines: 2,
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
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboard,
      maxLines: maxLines,
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
          borderSide: const BorderSide(color: Color(0xFFC9A227), width: 1.4),
        ),
      ),
    );
  }
}

/// Floating CTA — only mounted when [ScoreService.canClaimPrizeNotifier] is true.
class WinnerClaimBanner extends StatelessWidget {
  const WinnerClaimBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScoreService.instance.canClaimPrizeNotifier,
      builder: (context, canClaim, _) {
        if (!canClaim) return const SizedBox.shrink();
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    final ok = await WinnerClaimSheet.show(context);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Prize claim submitted. Thank you!'),
                        ),
                      );
                    }
                  },
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
                        '🎉 You Won! Claim Your Prize',
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
