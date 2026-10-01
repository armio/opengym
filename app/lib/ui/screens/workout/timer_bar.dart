import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'services/workout_timers.dart';

/// `m:ss` with unbounded minutes.
String clockText(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The floating timer bar (specs/ui.md §1.6): the rest countdown (clock + bar, then −15 s,
/// +15 s and "Saltar") or, during a timed set, the hold countdown ("Cancelar" / "Listo").
/// Slides in when a timer starts; empty otherwise.
class WorkoutTimerBar extends StatelessWidget {
  const WorkoutTimerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final timers = context.watch<WorkoutTimers>();
    final hold = timers.hold, rest = timers.rest;
    final Widget? content = hold != null
        ? _HoldBar(countdown: hold, timers: timers)
        : rest != null
        ? _RestBar(countdown: rest, timers: timers)
        : null;
    return AnimatedSwitcher(
      duration: AppMotion.med,
      switchInCurve: AppMotion.ease,
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: content == null
          ? const SizedBox.shrink()
          : _Panel(key: ValueKey(hold != null), working: hold != null, child: content),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.working, required this.child});

  final bool working;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 34, offset: Offset(0, 12), spreadRadius: -8)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: .97),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: working ? Border.all(color: p.acc, width: .5) : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatelessWidget {
  const _Clock({required this.seconds, this.color});

  final int seconds;
  final Color? color;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 66),
    child: Text(clockText(seconds), style: context.textStyles.statValue.copyWith(color: color)),
  );
}

/// The depleting bar: full at the start, empty at zero (1 s linear steps).
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 4,
        color: p.surface3,
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(seconds: 1),
          widthFactor: fraction,
          heightFactor: 1,
          child: ColoredBox(color: p.acc),
        ),
      ),
    );
  }
}

class _RestBar extends StatelessWidget {
  const _RestBar({required this.countdown, required this.timers});

  final Countdown countdown;
  final WorkoutTimers timers;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          _Clock(seconds: countdown.left),
          const SizedBox(width: 12),
          Expanded(child: _Bar(fraction: countdown.fraction)),
        ],
      ),
      const SizedBox(height: 10),
      _ActionRow(
        leading: [
          AppButton('15 s', icon: 'minus', size: ButtonSize.sm, onPressed: () => timers.addRest(-15)),
          AppButton('15 s', icon: 'plus', size: ButtonSize.sm, onPressed: () => timers.addRest(15)),
        ],
        primary: AppButton('Saltar', variant: ButtonVariant.primary, size: ButtonSize.sm, onPressed: timers.stopRest),
      ),
    ],
  );
}

/// A hold counts down the set itself: clock, exercise and bar, then "Cancelar" (logs nothing)
/// and "Listo" (logs what was held). Stacked like the rest bar so the label keeps its room.
class _HoldBar extends StatelessWidget {
  const _HoldBar({required this.countdown, required this.timers});

  final Countdown countdown;
  final WorkoutTimers timers;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Clock(seconds: countdown.left, color: p.acc),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (countdown.label != null) ...[
                    Text(
                      countdown.label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.label2),
                    ),
                    const SizedBox(height: 5),
                  ],
                  _Bar(fraction: countdown.fraction),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ActionRow(
          leading: [AppButton('Cancelar', size: ButtonSize.sm, onPressed: timers.cancelHold)],
          primary: AppButton(
            'Listo',
            icon: 'check',
            variant: ButtonVariant.primary,
            size: ButtonSize.sm,
            onPressed: timers.endHoldEarly,
          ),
        ),
      ],
    );
  }
}

/// The bar's buttons: [leading] together on the left, [primary] pushed to the far edge (at
/// least 84 wide), away from the buttons tapped to adjust. Mid-set, sweaty hands: they are
/// 42 px tall instead of 36.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.leading, required this.primary});

  final List<Widget> leading;
  final Widget primary;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < leading.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Flexible(child: leading[i]),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 84), child: primary),
        ),
      ],
    ),
  );
}
