import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'effort_help_sheet.dart';

/// Rest-timer choices (`settings.restSec`).
const restTimerOptions = [60, 90, 120, 150, 180];

/// The live settings, and one change written through [AppState.updateSettings].
extension on BuildContext {
  Settings get settings => select<AppState, Settings>((s) => s.settings);

  void editSettings(void Function(Settings s) fn) => read<AppState>().updateSettings(fn);
}

/// "General": weight unit and goal weight.
class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final p = context.palette;
    final goal = s.targetW;
    return Section(
      title: 'General',
      footer: 'Nota: cambiar la unidad solo cambia la etiqueta — los números registrados no se convierten.',
      children: [
        ListRow(
          icon: 'scale',
          iconTint: p.teal,
          title: 'Unidad de peso',
          trailing: Segmented<String>(
            inline: true,
            segments: const [Segment('kg', 'kg'), Segment('lb', 'lb')],
            value: s.unit,
            onChanged: (v) => context.editSettings((s) => s.unit = v),
          ),
        ),
        ListRow(
          icon: 'flag',
          iconTint: p.green,
          title: 'Peso objetivo',
          value: goal == null ? 'Sin meta' : formatWeight(goal, s.unit),
          accessory: RowAccessory.chevron,
          onTap: () => showGoalSheet(context),
        ),
      ],
    );
  }
}

/// "Durante el entrenamiento": rest timer, keep awake, sounds, effort scale, animation size.
class WorkoutSection extends StatelessWidget {
  const WorkoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final p = context.palette;
    return Section(
      title: 'Durante el entrenamiento',
      footer:
          'La pantalla se mantiene encendida mientras hay un entrenamiento en curso, así no tienes que '
          'desbloquear el móvil entre series.',
      children: [
        SelectRow<int>(
          icon: 'timer',
          iconTint: p.orange,
          title: 'Temporizador de descanso',
          value: s.restSec,
          options: [for (final sec in restTimerOptions) SelectOption(sec, '$sec s')],
          onChanged: (v) => context.editSettings((s) => s.restSec = v),
        ),
        SwitchRow(
          icon: 'sun',
          iconTint: p.yellow,
          title: 'Mantener la pantalla encendida',
          value: s.keepAwake,
          onChanged: (v) => context.editSettings((s) => s.keepAwake = v),
        ),
        SwitchRow(
          icon: 'bell',
          iconTint: p.pink,
          title: 'Sonidos',
          value: s.sound,
          onChanged: (v) => context.editSettings((s) => s.sound = v),
        ),
        _StackedRow(
          icon: 'target',
          iconTint: p.purple,
          title: 'Esfuerzo por serie',
          // The (i) sits before the control: read on the way to the choice, not after it.
          titleTrailing: AppIconButton(
            icon: 'info',
            tooltip: '¿Qué son RIR y RPE?',
            size: 30,
            iconSize: 17,
            background: Colors.transparent,
            color: p.label3,
            onPressed: () => showEffortHelpSheet(context),
          ),
          child: Segmented<String>(
            segments: const [Segment('none', 'No'), Segment('rir', 'RIR'), Segment('rpe', 'RPE')],
            value: s.effortScale,
            onChanged: (v) => context.editSettings((s) => s.setEffortScale(v)),
          ),
        ),
        ListRow(
          icon: 'minimize',
          iconTint: p.teal,
          title: 'Animación del ejercicio',
          trailing: Segmented<String>(
            inline: true,
            segments: const [Segment('full', 'Grande'), Segment('mini', 'Mini')],
            value: s.gifSize == 'mini' ? 'mini' : 'full',
            onChanged: (v) => context.editSettings((s) => s.gifSize = v),
          ),
        ),
      ],
    );
  }
}

/// "Apariencia": theme, body diagram and accent colour.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final p = context.palette;
    return Section(
      title: 'Apariencia',
      children: [
        ListRow(
          icon: 'moon',
          iconTint: p.indigo,
          title: 'Tema',
          trailing: Segmented<String>(
            inline: true,
            segments: const [
              Segment('dark', 'Oscuro', icon: 'moon'),
              Segment('light', 'Claro', icon: 'sun'),
            ],
            value: s.isLight ? 'light' : 'dark',
            onChanged: (v) => context.editSettings((s) => s.theme = v),
          ),
        ),
        // Only how the muscle map is drawn — nothing else reads this.
        ListRow(
          icon: 'figureStrength',
          iconTint: p.teal,
          title: 'Diagrama corporal',
          trailing: Segmented<String>(
            inline: true,
            segments: const [Segment('male', 'Masculino'), Segment('female', 'Femenino')],
            value: s.body == 'female' ? 'female' : 'male',
            onChanged: (v) => context.editSettings((s) => s.body = v),
          ),
        ),
        _StackedRow(
          icon: 'sparkles',
          iconTint: p.acc,
          title: 'Color de acento',
          child: _AccentSwatches(
            selected: Accent.fromKey(s.accent),
            onChanged: (a) => context.editSettings((s) => s.accent = a.name),
          ),
        ),
      ],
    );
  }
}

/// A grouped row whose control sits under its title, full width — for controls too wide to
/// share a phone-width line with the title.
class _StackedRow extends StatelessWidget implements GroupedRow {
  const _StackedRow({
    required this.icon,
    required this.iconTint,
    required this.title,
    required this.child,
    this.titleTrailing,
  });

  final String icon;
  final Color iconTint;
  final String title;
  final Widget? titleTrailing;
  final Widget child;

  @override
  bool get hasIcon => true;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(icon: icon, tint: iconTint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 29),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: context.textStyles.rowTitle)),
                    ?titleTrailing,
                  ],
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Color de acento": the eight swatches; the selected one carries a ring.
class _AccentSwatches extends StatelessWidget {
  const _AccentSwatches({required this.selected, required this.onChanged});

  final Accent selected;
  final ValueChanged<Accent> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    // Room for the selection ring, which is drawn outside the swatch.
    padding: const EdgeInsets.all(6),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final accent in Accent.values)
          _Swatch(accent: accent, selected: accent == selected, onTap: () => onChanged(accent)),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.accent, required this.selected, required this.onTap});

  final Accent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: accentNamesEs[accent],
    child: Pressable(
      onTap: onTap,
      pressedScale: .9,
      button: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: accent.swatch, shape: BoxShape.circle),
          ),
          // A 2 px ring 4 px outside the swatch.
          if (selected)
            Positioned(
              left: -6,
              top: -6,
              right: -6,
              bottom: -6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.palette.label, width: 2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
