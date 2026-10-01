import 'package:flutter/material.dart';

/// The original's icon names (specs/ui.md §2.6) mapped to Material icons, so screens can keep
/// the spec's vocabulary: `AppIcon('dumbbell')`, `AppIcons.of('trophy')`.
abstract final class AppIcons {
  static const Map<String, IconData> byName = {
    // navigation
    'house': Icons.home_rounded,
    'calendar': Icons.calendar_today_rounded,
    'chart': Icons.bar_chart_rounded,
    'magnifier': Icons.search_rounded,
    'gear': Icons.settings_outlined,
    // training
    'dumbbell': Icons.fitness_center_rounded,
    'barbell': Icons.fitness_center_outlined,
    'figureRun': Icons.directions_run_rounded,
    'figureStrength': Icons.accessibility_new_rounded,
    'scale': Icons.monitor_weight_outlined,
    'flame': Icons.local_fire_department_outlined,
    'timer': Icons.timer_outlined,
    'clock': Icons.schedule_rounded,
    // status
    'trophy': Icons.emoji_events_outlined,
    'medal': Icons.military_tech_outlined,
    'target': Icons.track_changes_rounded,
    'star': Icons.star_outline_rounded,
    'starFill': Icons.star_rounded,
    'crown': Icons.workspace_premium_outlined,
    'bolt': Icons.bolt_rounded,
    'shield': Icons.shield_outlined,
    'heart': Icons.favorite_border_rounded,
    'rocket': Icons.rocket_launch_outlined,
    'sparkles': Icons.auto_awesome_outlined,
    'lightbulb': Icons.lightbulb_outline_rounded,
    // routine glyphs
    'arm': Icons.sports_gymnastics_rounded,
    'abs': Icons.grid_view_rounded,
    'legs': Icons.directions_walk_rounded,
    'pullup': Icons.accessibility_rounded,
    'kettlebell': Icons.shopping_bag_outlined,
    'plate': Icons.album_outlined,
    'machine': Icons.dns_outlined,
    'bike': Icons.directions_bike_rounded,
    'swim': Icons.pool_rounded,
    'boxing': Icons.sports_mma_outlined,
    'stretch': Icons.self_improvement_rounded,
    // actions
    'plus': Icons.add_rounded,
    'minus': Icons.remove_rounded,
    'check': Icons.check_rounded,
    'checkCircle': Icons.check_circle_outline_rounded,
    'xmark': Icons.close_rounded,
    'pencil': Icons.edit_outlined,
    'trash': Icons.delete_outline_rounded,
    'link': Icons.link_rounded,
    'play': Icons.play_arrow_rounded,
    'pause': Icons.pause_rounded,
    'reset': Icons.restart_alt_rounded,
    'bell': Icons.notifications_none_rounded,
    'bellSlash': Icons.notifications_off_outlined,
    'chevronRight': Icons.chevron_right_rounded,
    'chevronLeft': Icons.chevron_left_rounded,
    'chevronDown': Icons.expand_more_rounded,
    'chevronUp': Icons.expand_less_rounded,
    'arrowUp': Icons.arrow_upward_rounded,
    'arrowDown': Icons.arrow_downward_rounded,
    'expand': Icons.open_in_full_rounded,
    'minimize': Icons.close_fullscreen_rounded,
    // objects
    'person': Icons.person_outline_rounded,
    'personCircle': Icons.account_circle_outlined,
    'clipboard': Icons.assignment_outlined,
    'list': Icons.format_list_bulleted_rounded,
    'folder': Icons.folder_outlined,
    'globe': Icons.language_rounded,
    'moon': Icons.dark_mode_outlined,
    'sun': Icons.light_mode_outlined,
    'key': Icons.key_outlined,
    'lock': Icons.lock_outline_rounded,
    'download': Icons.download_rounded,
    'upload': Icons.upload_rounded,
    'wrench': Icons.build_outlined,
    'flag': Icons.sports_score_rounded,
    'chartLine': Icons.show_chart_rounded,
    'dot': Icons.circle,
    'history': Icons.history_rounded,
    'signOut': Icons.logout_rounded,
    'shuffle': Icons.shuffle_rounded,
    'info': Icons.info_outline_rounded,
  };

  /// Aliases of the original icon set.
  static const Map<String, String> aliases = {
    'search': 'magnifier',
    'settings': 'gear',
    'exercises': 'magnifier',
    'weight': 'scale',
    'streak': 'flame',
    'done': 'check',
  };

  /// All icon names (`ICON_NAMES`), aliases excluded.
  static Iterable<String> get names => byName.keys;

  static bool has(String name) => byName.containsKey(name) || aliases.containsKey(name);

  /// The icon for [name] (or an alias); a neutral dot when unknown.
  static IconData of(String name) => byName[name] ?? byName[aliases[name]] ?? Icons.circle_outlined;
}

/// An icon from [AppIcons] by its spec name.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size, this.color, this.semanticLabel});

  final String name;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Icon(AppIcons.of(name), size: size, color: color, semanticLabel: semanticLabel);
}
