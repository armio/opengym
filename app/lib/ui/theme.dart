import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The eight accent colours (`settings.accent`, specs/ui.md §2.2), in the Settings order.
enum Accent {
  lime(
    swatch: Color(0xFF30D158),
    dark: Color(0xFF30D158),
    light: Color(0xFF34C759),
    pressed: Color(0xFF248A3D),
    onDark: Colors.black,
    onLight: Colors.black,
  ),
  sky(
    swatch: Color(0xFF0A84FF),
    dark: Color(0xFF0A84FF),
    light: Color(0xFF007AFF),
    pressed: Color(0xFF0060DF),
    onDark: Colors.white,
    onLight: Colors.white,
  ),
  orange(
    swatch: Color(0xFFFF9F0A),
    dark: Color(0xFFFF9F0A),
    light: Color(0xFFFF9500),
    pressed: Color(0xFFC76B00),
    onDark: Colors.black,
    onLight: Colors.black,
  ),
  violet(
    swatch: Color(0xFFBF5AF2),
    dark: Color(0xFFBF5AF2),
    light: Color(0xFFAF52DE),
    pressed: Color(0xFF8944AB),
    onDark: Colors.white,
    onLight: Colors.white,
  ),
  pink(
    swatch: Color(0xFFFF375F),
    dark: Color(0xFFFF375F),
    light: Color(0xFFFF2D55),
    pressed: Color(0xFFD70036),
    onDark: Colors.white,
    onLight: Colors.white,
  ),
  red(
    swatch: Color(0xFFFF453A),
    dark: Color(0xFFFF453A),
    light: Color(0xFFFF3B30),
    pressed: Color(0xFFD70015),
    onDark: Colors.white,
    onLight: Colors.white,
  ),
  teal(
    swatch: Color(0xFF40C8E0),
    dark: Color(0xFF40C8E0),
    light: Color(0xFF30B0C7),
    pressed: Color(0xFF0071A4),
    onDark: Colors.black,
    onLight: Colors.black,
  ),
  gold(
    swatch: Color(0xFFFFD60A),
    dark: Color(0xFFFFD60A),
    light: Color(0xFFFFCC00),
    pressed: Color(0xFFB25000),
    onDark: Colors.black,
    onLight: Colors.black,
  );

  const Accent({
    required this.swatch,
    required this.dark,
    required this.light,
    required this.pressed,
    required this.onDark,
    required this.onLight,
  });

  /// Colour of the Settings swatch (the dark-theme hex, `ACCENTS` in the original).
  final Color swatch;
  final Color dark;
  final Color light;

  /// `--acc-2`: pressed primary button.
  final Color pressed;

  /// `--on-acc`: text/icons on a filled accent surface.
  final Color onDark;
  final Color onLight;

  /// The accent stored under [key]; unknown keys render as lime.
  static Accent fromKey(String? key) => Accent.values.firstWhere((a) => a.name == key, orElse: () => Accent.lime);
}

/// Spanish names of the accents for the Settings swatches' semantics labels.
const accentNamesEs = {
  Accent.lime: 'Lima',
  Accent.sky: 'Cielo',
  Accent.orange: 'Naranja',
  Accent.violet: 'Violeta',
  Accent.pink: 'Rosa',
  Accent.red: 'Rojo',
  Accent.teal: 'Turquesa',
  Accent.gold: 'Oro',
};

/// Corner radii (specs/ui.md §2.4).
abstract final class AppRadii {
  static const double sm = 8;

  /// Buttons and fields.
  static const double r = 12;

  /// Media, timer bar, dialogs.
  static const double lg = 16;

  /// Sheet top corners.
  static const double xl = 22;

  /// Cards, list items and grouped lists.
  static const double card = 14;
}

/// Spacing constants (specs/ui.md §2.4).
abstract final class AppSpacing {
  /// Page side gutter.
  static const double gutter = 16;

  /// Maximum content width.
  static const double maxContentWidth = 560;

  /// Space below the content, added to the bottom inset. Inside the shell the inset already
  /// includes the tab bar (the body extends behind it), so this totals ≈ 128 + safe area.
  static const double bottomClearance = 48;
}

/// Motion constants (specs/ui.md §2.5).
abstract final class AppMotion {
  static const Curve ease = Cubic(.32, .72, 0, 1);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration med = Duration(milliseconds: 220);
}

/// The colour tokens of specs/ui.md §2.1–2.2 as a [ThemeExtension]. Read with
/// `context.palette` (see [AppThemeContext]).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.bgEl,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.label,
    required this.label2,
    required this.label3,
    required this.label4,
    required this.sep,
    required this.sepOp,
    required this.blue,
    required this.green,
    required this.red,
    required this.orange,
    required this.yellow,
    required this.teal,
    required this.indigo,
    required this.pink,
    required this.purple,
    required this.mint,
    required this.brown,
    required this.grey,
    required this.acc,
    required this.acc2,
    required this.onAcc,
    required this.sheet,
    required this.dialog,
    required this.segmentTrack,
    required this.segmentThumb,
    required this.searchFill,
  });

  factory AppPalette.forTheme({required Brightness brightness, required Accent accent}) {
    final dark = brightness == Brightness.dark;
    final acc = dark ? accent.dark : accent.light;
    if (dark) {
      return AppPalette(
        brightness: brightness,
        bg: const Color(0xFF000000),
        bgEl: const Color(0xFF0E0E10),
        surface: const Color(0xFF1C1C1E),
        surface2: const Color(0xFF2C2C2E),
        surface3: const Color(0xFF3A3A3C),
        label: const Color(0xFFFFFFFF),
        label2: const Color.fromRGBO(235, 235, 245, .60),
        label3: const Color.fromRGBO(235, 235, 245, .32),
        label4: const Color.fromRGBO(235, 235, 245, .18),
        sep: const Color.fromRGBO(84, 84, 88, .60),
        sepOp: const Color.fromRGBO(84, 84, 88, .34),
        blue: const Color(0xFF0A84FF),
        green: const Color(0xFF30D158),
        red: const Color(0xFFFF453A),
        orange: const Color(0xFFFF9F0A),
        yellow: const Color(0xFFFFD60A),
        teal: const Color(0xFF40C8E0),
        indigo: const Color(0xFF5E5CE6),
        pink: const Color(0xFFFF375F),
        purple: const Color(0xFFBF5AF2),
        mint: const Color(0xFF63E6E2),
        brown: const Color(0xFFAC8E68),
        grey: const Color(0xFF8E8E93),
        acc: acc,
        acc2: accent.pressed,
        onAcc: accent.onDark,
        sheet: const Color(0xFF0E0E10),
        dialog: const Color(0xFF0E0E10),
        segmentTrack: const Color(0xFF3A3A3C),
        segmentThumb: const Color(0xFF1C1C1E),
        searchFill: const Color(0xFF2C2C2E),
      );
    }
    return AppPalette(
      brightness: brightness,
      bg: const Color(0xFFF2F2F7),
      bgEl: const Color(0xFFF7F7FA),
      surface: const Color(0xFFFFFFFF),
      surface2: const Color(0xFFECECEF),
      surface3: const Color(0xFFE3E3E8),
      label: const Color(0xFF000000),
      label2: const Color.fromRGBO(60, 60, 67, .60),
      label3: const Color.fromRGBO(60, 60, 67, .30),
      label4: const Color.fromRGBO(60, 60, 67, .16),
      sep: const Color.fromRGBO(60, 60, 67, .29),
      sepOp: const Color.fromRGBO(60, 60, 67, .20),
      blue: const Color(0xFF007AFF),
      green: const Color(0xFF34C759),
      red: const Color(0xFFFF3B30),
      orange: const Color(0xFFFF9500),
      yellow: const Color(0xFFFFCC00),
      teal: const Color(0xFF30B0C7),
      indigo: const Color(0xFF5856D6),
      pink: const Color(0xFFFF2D55),
      purple: const Color(0xFFAF52DE),
      mint: const Color(0xFF00C7BE),
      brown: const Color(0xFFA2845E),
      grey: const Color(0xFF8E8E93),
      acc: acc,
      acc2: accent.pressed,
      onAcc: accent.onLight,
      sheet: const Color(0xFFF2F2F7),
      dialog: const Color(0xFFFFFFFF),
      segmentTrack: const Color.fromRGBO(118, 118, 128, .12),
      segmentThumb: const Color(0xFFFFFFFF),
      searchFill: const Color.fromRGBO(118, 118, 128, .12),
    );
  }

  final Brightness brightness;

  /// Page background.
  final Color bg;

  /// Sheets and bars.
  final Color bgEl;

  /// Cards, list rows, grouped lists.
  final Color surface;

  /// Pressed states, nested fills, steppers.
  final Color surface2;

  /// Controls: segmented track, switch off, slider track.
  final Color surface3;

  /// Primary text.
  final Color label;

  /// Secondary text.
  final Color label2;

  /// Tertiary text, placeholders, dim.
  final Color label3;

  /// Grab handle, unchecked checkbox ring.
  final Color label4;

  /// Hairlines.
  final Color sep;

  /// Hairlines over blur, chart gridlines.
  final Color sepOp;
  final Color blue;
  final Color green;

  /// Danger; weight moving away from the goal.
  final Color red;

  /// Active workout, rescheduled days, missed muscles.
  final Color orange;

  /// Goal, PR badge, deload, effort.
  final Color yellow;
  final Color teal;
  final Color indigo;
  final Color pink;
  final Color purple;
  final Color mint;
  final Color brown;
  final Color grey;

  /// `--acc`: the live accent for this theme.
  final Color acc;

  /// `--acc-2`: pressed primary.
  final Color acc2;

  /// `--on-acc`: text/icons on a filled accent surface.
  final Color onAcc;

  /// Bottom sheet background (light sheets use `--bg`).
  final Color sheet;

  /// Centre dialog background.
  final Color dialog;
  final Color segmentTrack;
  final Color segmentThumb;
  final Color searchFill;

  bool get isDark => brightness == Brightness.dark;

  /// `--acc-soft`: accent at 16 % (tinted buttons, `.tag.acc`, trained days).
  Color get accSoft => acc.withValues(alpha: .16);

  /// `--acc-line`: accent at 38 % (superset outline).
  Color get accLine => acc.withValues(alpha: .38);

  /// Tints over transparent used by status chips (`danger` 15 %, PR 18 %, missed/resume 16 %).
  Color get redSoft => red.withValues(alpha: .15);
  Color get yellowSoft => yellow.withValues(alpha: .18);
  Color get orangeSoft => orange.withValues(alpha: .16);

  /// Activity-heatmap cell for level 0–4 (accent mixed into `--surface-2`).
  Color heatCell(int level) => _heat(surface2, level, const [0, .30, .55, .78, 1]);

  /// `--bm-base`: an untrained muscle (`--label` 11 % into `--surface`).
  Color get muscleBase => Color.lerp(surface, label, .11)!;

  /// Body-map muscle for level 0–4 (accent mixed into [muscleBase]).
  Color muscleFill(int level) => _heat(muscleBase, level, const [0, .32, .56, .78, 1]);

  /// Non-muscle parts of the body map (`--label` 18 % into `--surface`).
  Color get silhouette => Color.lerp(surface, label, .18)!;

  Color _heat(Color base, int level, List<double> mix) => Color.lerp(base, acc, mix[level.clamp(0, 4)])!;

  @override
  AppPalette copyWith({Color? acc, Color? acc2, Color? onAcc}) => AppPalette(
    brightness: brightness,
    bg: bg,
    bgEl: bgEl,
    surface: surface,
    surface2: surface2,
    surface3: surface3,
    label: label,
    label2: label2,
    label3: label3,
    label4: label4,
    sep: sep,
    sepOp: sepOp,
    blue: blue,
    green: green,
    red: red,
    orange: orange,
    yellow: yellow,
    teal: teal,
    indigo: indigo,
    pink: pink,
    purple: purple,
    mint: mint,
    brown: brown,
    grey: grey,
    acc: acc ?? this.acc,
    acc2: acc2 ?? this.acc2,
    onAcc: onAcc ?? this.onAcc,
    sheet: sheet,
    dialog: dialog,
    segmentTrack: segmentTrack,
    segmentThumb: segmentThumb,
    searchFill: searchFill,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < .5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      bgEl: l(bgEl, other.bgEl),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      label: l(label, other.label),
      label2: l(label2, other.label2),
      label3: l(label3, other.label3),
      label4: l(label4, other.label4),
      sep: l(sep, other.sep),
      sepOp: l(sepOp, other.sepOp),
      blue: l(blue, other.blue),
      green: l(green, other.green),
      red: l(red, other.red),
      orange: l(orange, other.orange),
      yellow: l(yellow, other.yellow),
      teal: l(teal, other.teal),
      indigo: l(indigo, other.indigo),
      pink: l(pink, other.pink),
      purple: l(purple, other.purple),
      mint: l(mint, other.mint),
      brown: l(brown, other.brown),
      grey: l(grey, other.grey),
      acc: l(acc, other.acc),
      acc2: l(acc2, other.acc2),
      onAcc: l(onAcc, other.onAcc),
      sheet: l(sheet, other.sheet),
      dialog: l(dialog, other.dialog),
      segmentTrack: l(segmentTrack, other.segmentTrack),
      segmentThumb: l(segmentThumb, other.segmentThumb),
      searchFill: l(searchFill, other.searchFill),
    );
  }
}

/// The type scale of specs/ui.md §2.3 (tabular figures everywhere, tracking in em).
/// Read with `context.textStyles`.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.largeTitle,
    required this.sheetTitle,
    required this.bigNumber,
    required this.statValue,
    required this.weightReadout,
    required this.rowTitle,
    required this.itemTitle,
    required this.body,
    required this.button,
    required this.subtitle,
    required this.caption,
    required this.small,
    required this.tag,
    required this.microCaps,
    required this.tabLabel,
  });

  factory AppTextStyles.forPalette(AppPalette p) {
    TextStyle s(double size, FontWeight weight, double trackingEm, Color color, {double? height}) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * trackingEm,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return AppTextStyles(
      largeTitle: s(34, FontWeight.w700, -.028, p.label, height: 1.12),
      sheetTitle: s(20, FontWeight.w600, -.021, p.label),
      bigNumber: s(30, FontWeight.w600, -.026, p.label, height: 1.1),
      statValue: s(26, FontWeight.w600, -.026, p.label),
      weightReadout: s(52, FontWeight.w600, -.035, p.label),
      rowTitle: s(17, FontWeight.w400, -.012, p.label),
      itemTitle: s(16, FontWeight.w400, -.009, p.label),
      body: s(17, FontWeight.w400, -.01, p.label, height: 1.29),
      button: s(17, FontWeight.w600, -.01, p.label),
      subtitle: s(15, FontWeight.w400, -.01, p.label2),
      caption: s(13, FontWeight.w400, -.004, p.label2),
      small: s(13, FontWeight.w400, 0, p.label2, height: 1.38),
      tag: s(12, FontWeight.w500, 0, p.label2),
      microCaps: s(11, FontWeight.w500, .04, p.label3),
      tabLabel: s(10, FontWeight.w500, 0, p.label3),
    );
  }

  /// 34/700 — screen headers.
  final TextStyle largeTitle;

  /// 20/600 — sheet titles.
  final TextStyle sheetTitle;

  /// 30/600 — card numbers (body weight, today's routine).
  final TextStyle bigNumber;

  /// 26/600 — tiles, timer clock.
  final TextStyle statValue;

  /// 52/600 — WeightInput readout.
  final TextStyle weightReadout;

  /// 17/400 — grouped list rows.
  final TextStyle rowTitle;

  /// 16/400 — list items.
  final TextStyle itemTitle;

  /// 17/400 — body text.
  final TextStyle body;

  /// 17/600 — buttons.
  final TextStyle button;

  /// 15/400 label-2 — header subtitles.
  final TextStyle subtitle;

  /// 13/400 label-2 — section captions and footers (not uppercase).
  final TextStyle caption;

  /// 13 label-2 — `.small`.
  final TextStyle small;

  /// 12/500 — tags.
  final TextStyle tag;

  /// 11/500 label-3 — uppercase micro labels (apply `.toUpperCase()` to the text).
  final TextStyle microCaps;

  /// 10/500 — tab bar labels.
  final TextStyle tabLabel;

  @override
  AppTextStyles copyWith() => this;

  @override
  AppTextStyles lerp(AppTextStyles? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTextStyles(
      largeTitle: l(largeTitle, other.largeTitle),
      sheetTitle: l(sheetTitle, other.sheetTitle),
      bigNumber: l(bigNumber, other.bigNumber),
      statValue: l(statValue, other.statValue),
      weightReadout: l(weightReadout, other.weightReadout),
      rowTitle: l(rowTitle, other.rowTitle),
      itemTitle: l(itemTitle, other.itemTitle),
      body: l(body, other.body),
      button: l(button, other.button),
      subtitle: l(subtitle, other.subtitle),
      caption: l(caption, other.caption),
      small: l(small, other.small),
      tag: l(tag, other.tag),
      microCaps: l(microCaps, other.microCaps),
      tabLabel: l(tabLabel, other.tabLabel),
    );
  }
}

/// Builds the app's [ThemeData] for a theme setting and accent key.
abstract final class AppTheme {
  /// `settings.theme`: `'light'` → light, anything else → dark (the default).
  static ThemeData fromSettings({required String theme, required String accent}) =>
      build(brightness: theme == 'light' ? Brightness.light : Brightness.dark, accent: Accent.fromKey(accent));

  static ThemeData build({required Brightness brightness, Accent accent = Accent.lime}) {
    final p = AppPalette.forTheme(brightness: brightness, accent: accent);
    final t = AppTextStyles.forPalette(p);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.acc,
      onPrimary: p.onAcc,
      secondary: p.acc,
      onSecondary: p.onAcc,
      error: p.red,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.label,
      onSurfaceVariant: p.label2,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.bgEl,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface2,
      surfaceContainerHighest: p.surface3,
      outline: p.sep,
      outlineVariant: p.sepOp,
    );
    final textTheme = TextTheme(
      displayLarge: t.largeTitle,
      headlineMedium: t.largeTitle,
      titleLarge: t.sheetTitle,
      titleMedium: t.rowTitle,
      titleSmall: t.itemTitle,
      bodyLarge: t.body,
      bodyMedium: t.body.copyWith(fontSize: 15),
      bodySmall: t.small,
      labelLarge: t.button,
      labelMedium: t.tag,
      labelSmall: t.microCaps,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [p, t],
      // iOS-style feedback: presses scale/tint, nothing ripples.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: p.surface2.withValues(alpha: .5),
      dividerColor: p.sep,
      dividerTheme: DividerThemeData(color: p.sep, thickness: .5, space: .5),
      iconTheme: IconThemeData(color: p.label, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.label,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: t.rowTitle.copyWith(fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.sheet,
        modalBackgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.dialog,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        titleTextStyle: t.sheetTitle,
        contentTextStyle: t.body.copyWith(color: p.label2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: t.body.copyWith(color: p.label3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.r), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.r), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r),
          borderSide: BorderSide(color: p.acc, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r),
          borderSide: BorderSide(color: p.red, width: 1),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.acc,
        selectionColor: p.acc.withValues(alpha: .3),
        selectionHandleColor: p.acc,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.acc, linearTrackColor: p.surface3),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: CupertinoThemeData(brightness: brightness, primaryColor: p.acc),
    );
  }
}

/// `context.palette` / `context.textStyles` shortcuts.
extension AppThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  AppTextStyles get textStyles => Theme.of(this).extension<AppTextStyles>()!;
}
