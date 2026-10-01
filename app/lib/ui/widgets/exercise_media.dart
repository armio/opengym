import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/library.dart';
import '../theme.dart';
import 'app_icons.dart';

/// Display size of [ExerciseMedia].
enum MediaSize {
  /// 320 px — exercise detail and the workout.
  full(320),

  /// 120 px — inside superset cards.
  compact(120),

  /// 84 px — the workout's minimised animation (`settings.gifSize == 'mini'`).
  mini(84);

  const MediaSize(this.height);

  final double height;
}

/// The exercise animation (specs/ui.md §4.20): autoplaying GIF on white; a tap swaps to the
/// still JPG ("pause") and back. [minimizable] (the workout) adds the persisted
/// Minimizar/Ampliar toggle of `settings.gifSize`. Renders nothing for exercises without media
/// (custom ones). The Gym visual attribution is shown under it.
class ExerciseMedia extends StatefulWidget {
  const ExerciseMedia({
    super.key,
    required this.exercise,
    this.size = MediaSize.full,
    this.minimizable = false,
    this.showAttribution = true,
  });

  final Exercise exercise;
  final MediaSize size;
  final bool minimizable;
  final bool showAttribution;

  @override
  State<ExerciseMedia> createState() => _ExerciseMediaState();
}

class _ExerciseMediaState extends State<ExerciseMedia> {
  bool _playing = true;

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final gif = ex.gifUrl, still = ex.imageUrl;
    if (gif == null || still == null) return const SizedBox.shrink();
    final p = context.palette;
    final mini = widget.minimizable && context.select<AppState, bool>((s) => s.settings.gifSize == 'mini');
    final height = mini ? MediaSize.mini.height : widget.size.height;
    final url = _playing ? gif : still;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _playing = !_playing),
          child: Container(
            height: height,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.lg)),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  fadeInDuration: Duration.zero,
                  // Keep the frame on screen while swapping GIF ↔ JPG.
                  useOldImageOnUrlChange: true,
                  placeholder: (_, _) => const SizedBox.expand(),
                  errorWidget: (_, _, _) => Center(child: AppIcon('dumbbell', size: 34, color: Colors.black26)),
                ),
                if (widget.minimizable)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _Pill(
                      icon: mini ? 'expand' : 'minimize',
                      text: mini ? 'Ampliar' : 'Minimizar',
                      onTap: () => context.read<AppState>().updateSettings((s) => s.gifSize = mini ? 'full' : 'mini'),
                    ),
                  ),
                if (!mini)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _Pill(
                      icon: _playing ? 'pause' : 'play',
                      text: _playing ? 'toca para pausar' : 'toca para reproducir',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.showAttribution && !mini)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              mediaAttribution,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10.5, color: p.label3),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.onTap});

  final String icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
          ),
        ],
      ),
    );
    if (onTap == null) return IgnorePointer(child: pill);
    return Semantics(
      button: true,
      label: text,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// A 50 px exercise thumbnail (`Thumb`): the still JPG on white, or a placeholder tile with
/// [placeholderIcon] for exercises without media.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({super.key, this.exercise, this.placeholderIcon = 'dumbbell', this.size = 50});

  /// Null shows the placeholder (e.g. the "Crea tu propio ejercicio" row with `sparkles`).
  final Exercise? exercise;
  final String placeholderIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final url = exercise?.imageUrl;
    final radius = BorderRadius.circular(9 * size / 50);
    if (url == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: p.surface2, borderRadius: radius),
        child: Center(
          child: AppIcon(placeholderIcon, size: 21 * size / 50, color: p.label2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          memCacheWidth: (size * 3).round(),
          placeholder: (_, _) => const SizedBox.expand(),
          errorWidget: (_, _, _) => Center(
            child: AppIcon('dumbbell', size: 21 * size / 50, color: Colors.black26),
          ),
        ),
      ),
    );
  }
}
