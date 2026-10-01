import 'package:flutter/material.dart';

import '../../data/library.dart';
import 'exercise_media.dart';
import 'formatting.dart';
import 'surfaces.dart';

/// An exercise as a list item: thumbnail, capitalised name, Spanish
/// "`{músculo o parte del cuerpo} · {equipo}`" subtitle (or a custom [subtitle]) and
/// [trailing] widgets.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.exercise,
    this.subtitle,
    this.trailing = const [],
    this.onTap,
    this.accentBar = false,
  });

  final Exercise exercise;

  /// Replaces the taxonomy subtitle (e.g. the plan's "3 × 10 · 60 kg").
  final String? subtitle;
  final List<Widget> trailing;
  final VoidCallback? onTap;

  /// Superset member marker.
  final bool accentBar;

  @override
  Widget build(BuildContext context) => ListItem(
    leading: ExerciseThumb(exercise: exercise),
    title: capitalizeWords(exercise.name),
    subtitle: subtitle ?? capitalizeFirst(exercise.subtitleEs),
    trailing: trailing,
    onTap: onTap,
    accentBar: accentBar,
  );
}
