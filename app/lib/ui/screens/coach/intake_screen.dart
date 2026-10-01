import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'coach_widgets.dart';
import 'intake_options.dart';

/// The athlete profile in edit mode (specs/coach.md §2): one topic per step — goal and
/// experience, days, session length, equipment, limitations, likes/dislikes/notes. Saving
/// stamps `savedAt`/`updatedBy: 'app'` (the doc is pushed only once saved). Values outside the
/// options offered (set by Claude or an import) show as an extra, selected choice.
class AthleteIntakeScreen extends StatefulWidget {
  const AthleteIntakeScreen({super.key});

  @override
  State<AthleteIntakeScreen> createState() => _AthleteIntakeScreenState();
}

enum _Step { goal, days, length, equipment, limits, extras }

class _AthleteIntakeScreenState extends State<AthleteIntakeScreen> {
  late final AthleteProfile _initial = context.read<AppState>().athlete.copy();
  late final AthleteProfile _p = _initial.copy();
  late final _limitations = TextEditingController(text: _p.limitations);
  late final _likes = TextEditingController(text: _p.likes);
  late final _dislikes = TextEditingController(text: _p.dislikes);
  late final _notes = TextEditingController(text: _p.notes);
  var _step = _Step.goal;

  bool get _canSave => _p.goal != null && _p.experience != null;
  bool get _canNext => _step != _Step.goal || _canSave;
  bool get _last => _step == _Step.values.last;

  @override
  void dispose() {
    _limitations.dispose();
    _likes.dispose();
    _dislikes.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _edit(void Function(AthleteProfile p) fn) => setState(() => fn(_p));

  void _go(int delta) => setState(() => _step = _Step.values[_step.index + delta]);

  void _save() {
    context.read<AppState>().updateAthlete((a) {
      a
        ..goal = _p.goal
        ..experience = _p.experience
        ..daysPerWeek = _p.daysPerWeek
        ..preferredDays = ([..._p.preferredDays]..sort())
        ..sessionMin = _p.sessionMin
        ..equipment = [..._p.equipment]
        ..limitations = _limitations.text
        ..likes = _likes.text
        ..dislikes = _dislikes.text
        ..notes = _notes.text;
    });
    showToast(context, 'Guardado');
    // `pop`, not `maybePop`: the PopScope below would turn it into "previous step".
    Navigator.of(context).pop();
  }

  Widget _stepBody() => switch (_step) {
    _Step.goal => _GoalStep(profile: _p, initial: _initial, onEdit: _edit),
    _Step.days => _DaysStep(profile: _p, initial: _initial, onEdit: _edit),
    _Step.length => _LengthStep(profile: _p, initial: _initial, onEdit: _edit),
    _Step.equipment => _EquipmentStep(profile: _p, initial: _initial, onEdit: _edit),
    _Step.limits => _LimitsStep(controller: _limitations),
    _Step.extras => _ExtrasStep(likes: _likes, dislikes: _dislikes, notes: _notes),
  };

  @override
  Widget build(BuildContext context) {
    final first = _step == _Step.goal;
    return PopScope(
      canPop: first,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(-1);
      },
      child: Scaffold(
        body: PageBody(
          children: [
            ScreenHeader(
              title: 'Perfil de atleta',
              subtitle: 'Paso ${_step.index + 1} de ${_Step.values.length}',
              leading: BackChevron(onPressed: first ? null : () => _go(-1)),
              actions: [if (!_last) AppButton('Guardar', size: ButtonSize.sm, onPressed: _canSave ? _save : null)],
            ),
            _ProgressRail(step: _step.index, steps: _Step.values.length),
            _stepBody(),
            const SizedBox(height: 18),
            _StepButtons(
              showBack: !first,
              last: _last,
              canNext: _canNext,
              onBack: () => _go(-1),
              onNext: () => _go(1),
              onSave: _save,
            ),
            if (!_canNext)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Elige un objetivo y tu punto de partida para continuar.',
                  textAlign: TextAlign.center,
                  style: context.textStyles.caption,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Six bars, filled up to the current step.
class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.step, required this.steps});

  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          for (var i = 0; i < steps; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: AppMotion.med,
                height: 3,
                decoration: BoxDecoration(
                  color: i <= step ? p.acc : p.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepButtons extends StatelessWidget {
  const _StepButtons({
    required this.showBack,
    required this.last,
    required this.canNext,
    required this.onBack,
    required this.onNext,
    required this.onSave,
  });

  final bool showBack;
  final bool last;
  final bool canNext;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (showBack) ...[Expanded(child: AppButton('Atrás', onPressed: onBack)), const SizedBox(width: 10)],
      Expanded(
        child: last
            ? AppButton('Guardar', variant: ButtonVariant.primary, icon: 'check', onPressed: onSave)
            : AppButton('Siguiente', variant: ButtonVariant.primary, onPressed: canNext ? onNext : null),
      ),
    ],
  );
}

/// A step's question (`h2`).
class _Question extends StatelessWidget {
  const _Question(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: context.textStyles.sheetTitle),
  );
}

/// Grey helper text under a question.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: context.textStyles.small.copyWith(height: 1.45, color: color)),
  );
}

typedef _Edit = void Function(void Function(AthleteProfile p) fn);

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.profile, required this.initial, required this.onEdit});

  final AthleteProfile profile;
  final AthleteProfile initial;
  final _Edit onEdit;

  /// The labelled options plus a stored value outside them.
  static Map<String, String> _options(Map<String, String> labels, String? stored) => {
    ...labels,
    if (stored != null && !labels.containsKey(stored)) stored: stored,
  };

  @override
  Widget build(BuildContext context) {
    Widget choices(Map<String, String> options, String? current, void Function(AthleteProfile, String) set) => Section(
      children: [
        for (final o in options.entries)
          ListRow(
            title: o.value,
            accessory: current == o.key ? RowAccessory.check : RowAccessory.none,
            onTap: () => onEdit((p) => set(p, o.key)),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('¿Para qué entrenas?'),
        choices(_options(goalLabels, initial.goal), profile.goal, (p, v) => p.goal = v),
        const _Question('¿De dónde partes?'),
        choices(_options(experienceLabels, initial.experience), profile.experience, (p, v) => p.experience = v),
      ],
    );
  }
}

class _DaysStep extends StatelessWidget {
  const _DaysStep({required this.profile, required this.initial, required this.onEdit});

  final AthleteProfile profile;
  final AthleteProfile initial;
  final _Edit onEdit;

  @override
  Widget build(BuildContext context) {
    final options = withExtras(dayOptions, [initial.daysPerWeek, profile.daysPerWeek]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('¿Cuántos días a la semana?'),
        Segmented<int>(
          segments: [for (final n in options) Segment(n, '$n')],
          value: profile.daysPerWeek,
          onChanged: (v) => onEdit((p) => p.daysPerWeek = v),
        ),
        const SizedBox(height: 18),
        const _Hint('¿Qué días te van bien? (opcional)'),
        Row(
          children: [
            for (final d in weekdaysMondayFirst) ...[
              if (d != weekdaysMondayFirst.first) const SizedBox(width: 6),
              Expanded(
                child: _DayToggle(
                  label: dayLetters[d],
                  name: dayNames[d],
                  selected: profile.preferredDays.contains(d),
                  onTap: () => onEdit((p) {
                    if (!p.preferredDays.remove(d)) p.preferredDays = [...p.preferredDays, d]..sort();
                  }),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.name, required this.selected, required this.onTap});

  final String label;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: name,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        pressedScale: .92,
        color: selected ? p.acc : p.surface,
        borderRadius: BorderRadius.circular(AppRadii.r),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? p.onAcc : p.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LengthStep extends StatelessWidget {
  const _LengthStep({required this.profile, required this.initial, required this.onEdit});

  final AthleteProfile profile;
  final AthleteProfile initial;
  final _Edit onEdit;

  @override
  Widget build(BuildContext context) {
    final options = withExtras(sessionOptions, [initial.sessionMin, profile.sessionMin]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('¿Cuánto dura una sesión?'),
        Segmented<int>(
          segments: [for (final n in options) Segment(n, '$n min')],
          value: profile.sessionMin,
          onChanged: (v) => onEdit((p) => p.sessionMin = v),
        ),
        const SizedBox(height: 14),
        const _Hint('Claude ajusta el volumen al tiempo del que dispones, incluido el descanso entre series.'),
      ],
    );
  }
}

class _EquipmentStep extends StatelessWidget {
  const _EquipmentStep({required this.profile, required this.initial, required this.onEdit});

  final AthleteProfile profile;
  final AthleteProfile initial;
  final _Edit onEdit;

  @override
  Widget build(BuildContext context) {
    final options = {...equipmentOptions, ...initial.equipment, ...profile.equipment};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('¿Con qué puedes entrenar?'),
        const _Hint('Marca todo lo que tengas a mano. Si lo dejas vacío, Claude usará toda la biblioteca.'),
        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: [
            for (final e in options)
              AppChip(
                equipmentLabel(e),
                selected: profile.equipment.contains(e),
                onTap: () => onEdit((p) {
                  if (!p.equipment.remove(e)) p.equipment = [...p.equipment, e];
                }),
              ),
          ],
        ),
      ],
    );
  }
}

class _LimitsStep extends StatelessWidget {
  const _LimitsStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Question('¿Algo que haya que tener en cuenta?'),
      const _Hint(
        'Lesiones, articulaciones molestas, movimientos que no puedes hacer o límites prácticos '
        'como entrenar a las 6 de la mañana en un piso.',
      ),
      _AnswerField(
        controller: controller,
        maxLength: limitationsMax,
        minLines: 4,
        hint: 'p. ej. «hombro izquierdo delicado: nada de press militar con barra»',
      ),
      const SizedBox(height: 6),
      _Hint(
        'Si algo duele de verdad, consulta a un profesional: Claude programará de forma '
        'conservadora, pero no puede diagnosticar nada.',
        color: context.palette.yellow,
      ),
    ],
  );
}

class _ExtrasStep extends StatelessWidget {
  const _ExtrasStep({required this.likes, required this.dislikes, required this.notes});

  final TextEditingController likes;
  final TextEditingController dislikes;
  final TextEditingController notes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Question('¿Algo más?'),
      const _Hint('Ejercicios que te encantan'),
      _AnswerField(controller: likes, maxLength: likesMax, hint: 'p. ej. «peso muerto, cualquier cosa con kettlebell»'),
      const SizedBox(height: 8),
      const _Hint('Ejercicios que preferirías evitar'),
      _AnswerField(controller: dislikes, maxLength: dislikesMax, hint: 'p. ej. «odio las zancadas»'),
      const SizedBox(height: 8),
      const _Hint('Algo que quieras que sepa Claude'),
      _AnswerField(
        controller: notes,
        maxLength: notesMax,
        minLines: 3,
        hint: 'p. ej. «quiero ver progreso en los brazos para la primavera»',
      ),
    ],
  );
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({required this.controller, required this.maxLength, required this.hint, this.minLines = 2});

  final TextEditingController controller;
  final int maxLength;
  final String hint;
  final int minLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: maxLength,
    minLines: minLines,
    maxLines: minLines + 4,
    textCapitalization: TextCapitalization.sentences,
    style: context.textStyles.body.copyWith(fontSize: 16),
    decoration: InputDecoration(hintText: hint, hintMaxLines: 3),
  );
}
