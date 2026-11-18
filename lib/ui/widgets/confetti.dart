import 'dart:math';

import 'package:flutter/material.dart';

/// A short, dependency-free confetti burst used by update dialogs.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.count = 64,
    this.duration = const Duration(milliseconds: 1900),
  });

  final int count;
  final Duration duration;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _ConfettiPainter(
                progress: Curves.easeOut.transform(_controller.value),
                count: widget.count,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  const Color(0xFFFFB74D),
                  const Color(0xFF4CD964),
                  const Color(0xFF4A9EFF),
                  const Color(0xFFFF6B9A),
                  const Color(0xFFB388FF),
                ],
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.progress,
    required this.count,
    required this.colors,
  });

  final double progress;
  final int count;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1 || size.width <= 0 || size.height <= 0) return;
    final random = Random(7);
    final fade = progress < 0.72 ? 1.0 : (1 - progress) / 0.28;
    final origin = Offset(size.width / 2, size.height * 0.12);
    final time = progress * 1.9;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final angle = -pi * (0.15 + random.nextDouble() * 0.7);
      final speed = size.height * (0.55 + random.nextDouble() * 1.25);
      final vx = cos(angle) * speed;
      final vy = sin(angle) * speed;
      final x = origin.dx + vx * time * 0.62;
      final y = origin.dy + vy * time + 0.5 * size.height * 1.3 * time * time;
      if (x < -20 || x > size.width + 20 || y > size.height + 20) continue;
      final particleWidth = 3.5 + random.nextDouble() * 4.5;
      final particleHeight = 2.5 + random.nextDouble() * 5.5;
      final color = colors[i % colors.length].withValues(alpha: fade);
      paint.color = color;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(random.nextDouble() * pi * 2 + time * 6);
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, particleWidth * 0.7, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: particleWidth,
            height: particleHeight,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.count != count;
  }
}
