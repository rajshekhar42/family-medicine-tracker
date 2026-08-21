import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A premium animated overlay that teaches the user about swipe gestures.
///
/// Shows:
/// - "Swipe right to take" with an animated arrow sliding right (green)
/// - "Swipe left to skip" with an animated arrow sliding left (red)
/// - "Double-tap logged dose to update status" at the bottom
///
/// The overlay auto-dismisses after ~2.5 seconds, or the user can tap to dismiss.
class SwipeTutorialOverlay extends StatefulWidget {
  /// Called when the animation completes or the user dismisses the overlay.
  final VoidCallback onDismissed;

  const SwipeTutorialOverlay({
    super.key,
    required this.onDismissed,
  });

  @override
  State<SwipeTutorialOverlay> createState() => _SwipeTutorialOverlayState();
}

class _SwipeTutorialOverlayState extends State<SwipeTutorialOverlay>
    with TickerProviderStateMixin {
  // Master opacity for the entire overlay (fade in / fade out)
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // Arrow slide animation — right arrow (take)
  late final AnimationController _rightArrowController;
  late final Animation<Offset> _rightArrowSlide;
  late final Animation<double> _rightArrowOpacity;

  // Arrow slide animation — left arrow (skip)
  late final AnimationController _leftArrowController;
  late final Animation<Offset> _leftArrowSlide;
  late final Animation<double> _leftArrowOpacity;

  // Bottom text fade
  late final AnimationController _textController;
  late final Animation<double> _textOpacity;

  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _runSequence();
  }

  void _setupAnimations() {
    // 1. Master fade — 250ms in, 300ms out
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    // 2. Right arrow (swipe-to-take): slides from center to the right
    _rightArrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rightArrowSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.35, 0),
    ).animate(CurvedAnimation(
      parent: _rightArrowController,
      curve: Curves.easeInOutCubic,
    ));
    _rightArrowOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 20),
    ]).animate(_rightArrowController);

    // 3. Left arrow (swipe-to-skip): slides from center to the left
    _leftArrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _leftArrowSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.35, 0),
    ).animate(CurvedAnimation(
      parent: _leftArrowController,
      curve: Curves.easeInOutCubic,
    ));
    _leftArrowOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 20),
    ]).animate(_leftArrowController);

    // 4. Bottom text
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _textOpacity = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeIn,
    );
  }

  Future<void> _runSequence() async {
    // Light haptic at start
    HapticFeedback.lightImpact();

    // Phase 1: Fade in the overlay
    await _fadeController.forward();
    if (_dismissed) return;

    // Phase 2: Animate right arrow (swipe to take)
    await Future.delayed(const Duration(milliseconds: 300));
    if (_dismissed) return;
    await _rightArrowController.forward();
    if (_dismissed) return;

    // Phase 3: Animate left arrow (swipe to skip)
    await Future.delayed(const Duration(milliseconds: 300));
    if (_dismissed) return;
    await _leftArrowController.forward();
    if (_dismissed) return;

    // Phase 4: Show bottom text
    await Future.delayed(const Duration(milliseconds: 200));
    if (_dismissed) return;
    await _textController.forward();
    if (_dismissed) return;

    // Phase 5: Hold, then fade out (~5s total)
    await Future.delayed(const Duration(milliseconds: 2100));
    if (_dismissed) return;
    _dismiss();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _fadeController.reverse().then((_) {
      if (mounted) {
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _rightArrowController.dispose();
    _leftArrowController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greenColor =
        isDark ? const Color(0xFF66BB6A) : const Color(0xFF43A047);
    final redColor =
        isDark ? const Color(0xFFEF5350) : const Color(0xFFE53935);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: _dismiss,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withOpacity(0.65)
                    : Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.06),
                  width: 1,
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Swipe arrows row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left arrow — skip (slides left)
                        Expanded(
                          child: SlideTransition(
                            position: _leftArrowSlide,
                            child: FadeTransition(
                              opacity: _leftArrowOpacity,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back_rounded,
                                      color: redColor, size: 20),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Swipe to Skip',
                                    style: TextStyle(
                                      color: redColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Divider dot
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.3)
                                : Colors.black.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                        ),

                        // Right arrow — take (slides right)
                        Expanded(
                          child: SlideTransition(
                            position: _rightArrowSlide,
                            child: FadeTransition(
                              opacity: _rightArrowOpacity,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Swipe to Take',
                                    style: TextStyle(
                                      color: greenColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_rounded,
                                      color: greenColor, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Bottom hint text
                    FadeTransition(
                      opacity: _textOpacity,
                      child: Text(
                        'Double-tap logged dose to update status',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withOpacity(0.55)
                              : Colors.black.withOpacity(0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
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
}
