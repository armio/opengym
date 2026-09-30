import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/sync.dart';
import 'screens/coach/coach_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/plan/plan_screen.dart';
import 'screens/progress/progress_screen.dart';
import 'theme.dart';
import 'widgets/widgets.dart';
import 'workout_launcher.dart';

/// The four tabs around the centre "Entrenar" button (contract §6).
enum AppTab {
  home('Inicio', 'house'),
  plan('Plan', 'calendar'),
  progress('Progreso', 'chart'),
  coach('Coach', 'sparkles');

  const AppTab(this.label, this.icon);

  final String label;

  /// [AppIcons] name.
  final String icon;
}

/// Switches tabs from anywhere under the shell: `context.read<ShellController>().goTo(AppTab.plan)`.
class ShellController extends ChangeNotifier {
  ShellController([this._tab = AppTab.home]);

  AppTab _tab;
  final Map<AppTab, GlobalKey<NavigatorState>> _navigators = {
    for (final t in AppTab.values) t: GlobalKey<NavigatorState>(debugLabel: 'tab-${t.name}'),
  };

  AppTab get tab => _tab;

  /// The nested navigator of [tab] (each tab keeps its own stack under the tab bar).
  NavigatorState? navigatorOf(AppTab tab) => _navigators[tab]!.currentState;

  /// Shows [tab]; with [popToRoot] (or when it is already selected) its stack returns to the
  /// tab's root screen.
  void goTo(AppTab tab, {bool popToRoot = false}) {
    if (popToRoot || tab == _tab) navigatorOf(tab)?.popUntil((r) => r.isFirst);
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }
}

/// The signed-in app: four tab stacks, the tab bar with the raised "Entrenar" button, sync on
/// start and resume, a sync banner when offline, and toasts for sync conflicts/rejections.
class Shell extends StatefulWidget {
  const Shell({super.key, this.initialTab = AppTab.home});

  final AppTab initialTab;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final ShellController _controller = ShellController(widget.initialTab);
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<SyncNotice>? _notices;
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.confirmUploadLocalData = (summary) => confirmUploadLocalOnly(context, summary);
    _notices = _app.notices.listen((n) {
      if (mounted) showToast(context, n.message);
    });
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_app.onResumed()),
      onHide: () => unawaited(_app.onPaused()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_app.sync()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _notices?.cancel();
    _app.confirmUploadLocalData = null;
    _controller.dispose();
    super.dispose();
  }

  Widget _screenFor(AppTab tab) => switch (tab) {
    AppTab.home => const HomeScreen(),
    AppTab.plan => const PlanScreen(),
    AppTab.progress => const ProgressScreen(),
    AppTab.coach => const CoachScreen(),
  };

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<ShellController>(
        builder: (context, shell, _) => Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: shell.tab.index,
            children: [
              for (final tab in AppTab.values)
                NavigatorPopHandler<Object?>(
                  enabled: tab == shell.tab,
                  onPopWithResult: (_) => shell.navigatorOf(tab)?.maybePop(),
                  child: Navigator(
                    key: shell._navigators[tab],
                    onGenerateRoute: (settings) =>
                        MaterialPageRoute<void>(settings: settings, builder: (_) => _screenFor(tab)),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SyncStatusBanner(),
              AppTabBar(
                current: shell.tab,
                onTab: shell.goTo,
                onStart: () => context.read<WorkoutLauncher>().launch(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom bar (specs/ui.md §1.2): Inicio, Plan, the raised Entrenar button, Progreso,
/// Coach. Blurred `--bg-el` background with a hairline on top. While a workout is active the
/// centre disc turns orange with a pulsing ring and reads "Seguir".
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.current, required this.onTab, required this.onStart});

  final AppTab current;
  final ValueChanged<AppTab> onTab;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final hasActive = context.select<AppState, bool>((s) => s.active != null);
    final pendingCoach = context.select<AppState, int>((s) => s.pendingProposals.length);
    Widget item(AppTab tab) => Expanded(
      child: _TabItem(
        tab: tab,
        selected: tab == current,
        badge: tab == AppTab.coach && pendingCoach > 0,
        onTap: () => onTab(tab),
      ),
    );
    // The raised disc sits inside the bar's box (in a transparent band above the blurred
    // background) so all of it is tappable; the band itself lets taps through.
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: _raise,
          bottom: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.isDark ? p.bgEl.withValues(alpha: .72) : const Color.fromRGBO(249, 249, 251, .78),
                  border: Border(top: BorderSide(color: p.sepOp, width: .5)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(6, 7, 6, 6 + bottom),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              item(AppTab.home),
              item(AppTab.plan),
              Expanded(
                child: _StartButton(active: hasActive, onTap: onStart),
              ),
              item(AppTab.progress),
              item(AppTab.coach),
            ],
          ),
        ),
      ],
    );
  }

  /// Height of the transparent band the centre disc rises into (disc 52 + label vs. 44 px
  /// tab items).
  static const double _raise = 24;
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.selected, required this.onTap, this.badge = false});

  final AppTab tab;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.acc : p.label;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppIcon(tab.icon, size: 25, color: color),
                  if (badge)
                    Positioned(
                      right: -3,
                      top: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: p.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.bgEl, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(tab.label, style: context.textStyles.tabLabel.copyWith(color: selected ? p.acc : p.label3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The raised centre disc: accent with a dumbbell ("Entrenar"), or orange with a play glyph and
/// a pulsing ring while a workout is active ("Seguir").
class _StartButton extends StatefulWidget {
  const _StartButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ping = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));

  @override
  void initState() {
    super.initState();
    _syncPing();
  }

  @override
  void didUpdateWidget(_StartButton old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncPing();
  }

  void _syncPing() {
    if (widget.active) {
      _ping.repeat();
    } else {
      _ping
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final disc = widget.active ? p.orange : p.acc;
    final glyph = widget.active ? Colors.black : p.onAcc;
    final label = widget.active ? 'Seguir' : 'Entrenar';
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: widget.onTap,
        pressedScale: .93,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 52,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (widget.active && !reduceMotion)
                    AnimatedBuilder(
                      animation: _ping,
                      builder: (_, _) => Transform.scale(
                        scale: 1 + .45 * _ping.value,
                        child: Opacity(
                          opacity: .7 * (1 - _ping.value),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.orange, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: disc,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: disc.withValues(alpha: .55),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Center(child: AppIcon(widget.active ? 'play' : 'dumbbell', size: 26, color: glyph)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: context.textStyles.tabLabel.copyWith(color: disc, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
