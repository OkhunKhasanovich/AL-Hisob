import 'package:flutter/material.dart';

/// Круглый аватар с первой буквой имени. Hero-тег связывает список и карточку.
class DebtorAvatar extends StatelessWidget {
  const DebtorAvatar({super.key, required this.id, required this.name, this.radius = 24});

  final String id;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Hero(
      tag: 'debtor-$id',
      child: CircleAvatar(
        radius: radius,
        backgroundColor: scheme.secondaryContainer,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w600,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
