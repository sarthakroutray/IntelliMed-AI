import 'package:flutter/material.dart';

import '../theme.dart';

/// Single-select chip group, matching the web app's filter chip rows.
///
/// Laid out with [Wrap] rather than a horizontal scroll: every option stays
/// visible, and a long label or a narrow screen wraps instead of overflowing.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.countOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;

  /// Optional trailing count, e.g. "Analyzed (3)".
  final int? Function(T)? countOf;

  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          _Chip(
            label: _label(value),
            selected: value == selected,
            onTap: () => onSelected(value),
          ),
      ],
    );
  }

  String _label(T value) {
    final base = labelOf(value);
    final count = countOf?.call(value);
    return count == null ? base : '$base ($count)';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surface(brightness),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border(brightness),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected
                  ? AppColors.primary
                  : AppColors.textMuted(brightness),
            ),
          ),
        ),
      ),
    );
  }
}
