import 'package:flutter/material.dart';

import '../theme.dart';

/// Rounded primary square standing in for the web app's logo mark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(
        Icons.monitor_heart_outlined,
        size: size * 0.6,
        color: AppColors.onPrimary,
      ),
    );
  }
}

/// Brand mark plus the product name, as shown atop the web sidebar.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.markSize = 32});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 12),
        Text(
          'IntelliMed-AI',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
