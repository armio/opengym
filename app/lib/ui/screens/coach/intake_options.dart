/// The options of the athlete intake (specs/coach.md §2) with their Spanish labels.
library;

import '../../../data/models/models.dart';
import '../../../data/taxonomy_es.dart';

/// `goal` values, in the intake's order.
const goalLabels = {
  'strength': 'Ganar fuerza',
  'muscle': 'Ganar músculo',
  'general': 'Forma física general',
  'fatloss': 'Perder grasa',
  'endurance': 'Resistencia',
};

/// `experience` values, in the intake's order.
const experienceLabels = {
  'new': 'Empiezo con las pesas',
  'returning': 'Vuelvo tras un parón',
  'regular': 'Entreno con regularidad',
};

/// `daysPerWeek` choices the intake offers (the doc allows 1–7).
const dayOptions = [2, 3, 4, 5, 6];

/// `sessionMin` choices the intake offers (the doc allows 15–180).
const sessionOptions = [30, 45, 60, 75, 90];

/// Weekdays in display order, Monday first (0 = Sunday).
const weekdaysMondayFirst = [1, 2, 3, 4, 5, 6, 0];

/// The 14 most common library equipment values, most common first (specs/coach.md §2).
const equipmentOptions = [
  'body weight', 'dumbbell', 'cable', 'barbell', 'leverage machine', 'band', 'smith machine', //
  'kettlebell', 'weighted', 'stability ball', 'ez barbell', 'assisted', 'sled machine', 'medicine ball',
];

/// Text limits of the free-text answers.
const limitationsMax = 600;
const likesMax = 300;
const dislikesMax = 300;
const notesMax = 600;

/// Spanish label of an equipment value (unknown values as they are).
String equipmentLabel(String value) => equipmentEs[value] ?? value;

/// [options] plus the values outside them that [current] holds (so a value Claude or an import
/// set still shows, selected), sorted.
List<int> withExtras(List<int> options, Iterable<int> current) => {...options, ...current}.toList()..sort();

/// The profile row's subtitle: `"Ganar músculo · 3 días a la semana · 45 min"`, or
/// "Sin configurar" before the first save.
String athleteSummary(AthleteProfile a) {
  if (a.savedAt == null) return 'Sin configurar';
  final parts = [
    if (a.goal != null) goalLabels[a.goal] ?? a.goal!,
    a.daysPerWeek == 1 ? '1 día a la semana' : '${a.daysPerWeek} días a la semana',
    '${a.sessionMin} min',
  ];
  return parts.join(' · ');
}
