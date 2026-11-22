import 'dart:math' as math;

import 'package:flutter/material.dart';

Duration luxuryDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

AnimationStyle luxuryOverlayMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: Duration(milliseconds: 320),
        reverseDuration: Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

Future<T?> showLuxuryDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
  animationStyle: luxuryOverlayMotion(context),
  builder: builder,
);

class LuxuryReveal extends StatefulWidget {
  const LuxuryReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.hover = false,
    this.section = false,
  });

  final Widget child;
  final int index;
  final bool hover;
  final bool section;

  @override
  State<LuxuryReveal> createState() => _LuxuryRevealState();
}

class _LuxuryRevealState extends State<LuxuryReveal> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final entrance = widget.section ? 340 : 260;
    final delay = math.min(widget.index, 5) * 26;
    final reveal = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: entrance + delay),
      curve: Interval(
        delay / (entrance + delay),
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, progress, child) => Transform.translate(
        offset: Offset(0, (1 - progress) * (widget.section ? 18 : 11)),
        child: Opacity(opacity: .64 + .36 * progress, child: child),
      ),
      child: widget.child,
    );
    if (!widget.hover) return reveal;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.015 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: reveal,
      ),
    );
  }
}
