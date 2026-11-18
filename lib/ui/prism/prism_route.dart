import 'package:flutter/widgets.dart';

/// A pushed route with a soft slide + fade, matching the prism_ui shell.
Route<T> prismPageRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: const Color(0x00000000),
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.045, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
