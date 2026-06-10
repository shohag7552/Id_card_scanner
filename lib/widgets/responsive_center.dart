import 'package:flutter/material.dart';

/// Centers [child] and caps its width on large (web / desktop) screens so the
/// mobile-first layouts don't stretch edge-to-edge. On narrow screens it is a
/// no-op pass-through, keeping the phone experience untouched.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
