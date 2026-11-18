import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A lightweight, dependency-free shimmer used while local aggregates load.
/// It mirrors the real card rhythm instead of showing a blank spinner.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 0.9,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.muted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                const SkeletonBox(width: 58, height: 34, radius: 9),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  Row(
                    children: [
                      const SkeletonBox(width: 66, height: 12),
                      const Spacer(),
                      const SkeletonBox(width: 52, height: 12),
                    ],
                  ),
                  const SizedBox(height: 9),
                  const SkeletonBox(height: 7, radius: 99),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const SkeletonBox(width: 78, height: 9),
                      const Spacer(),
                      const SkeletonBox(width: 92, height: 9),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SkeletonBox(width: 88, height: 14),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.65,
            children: const [
              SkeletonBox(height: 90, radius: 14),
              SkeletonBox(height: 90, radius: 14),
              SkeletonBox(height: 90, radius: 14),
              SkeletonBox(height: 90, radius: 14),
            ],
          ),
          const SizedBox(height: 18),
          const SkeletonBox(height: 210, radius: 16),
        ],
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 5, this.rowHeight = 108});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return Container(
            height: rowHeight,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SkeletonBox(width: 92, height: 13),
                    const Spacer(),
                    const SkeletonBox(width: 48, height: 11),
                  ],
                ),
                const SizedBox(height: 10),
                const SkeletonBox(width: 130, height: 9),
                const Spacer(),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      const Expanded(child: SkeletonBox(height: 20, radius: 6)),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
