import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/json.dart' show jsNum;
import '../theme.dart';
import 'app_icons.dart';
import 'pressable.dart';
import 'surfaces.dart';

/// Result of parsing what the user typed into a [NumberField].
class NumberInput {
  const NumberInput(this.draft, this.value);

  /// The sanitised text to keep on screen while editing (e.g. `"33."` for `"33,"`).
  final String draft;

  /// The committed number (null only for nullable fields).
  final num? value;
}

/// The NumberField keystroke rule (specs/ui.md §2.8): `,` is a decimal separator, anything
/// but digits and one dot is dropped, integer fields cut at the dot, empty → 0 (or null when
/// [nullable]). Never negative.
NumberInput parseNumberInput(String raw, {bool decimal = true, bool nullable = false}) {
  var s = raw.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
  final i = s.indexOf('.');
  if (i != -1) {
    s = decimal ? s.substring(0, i + 1) + s.substring(i + 1).replaceAll('.', '') : s.substring(0, i);
  }
  if (s.isEmpty || s == '.') return NumberInput(s, nullable ? null : 0);
  final parsed = double.tryParse(s.startsWith('.') ? '0$s' : s) ?? 0;
  return NumberInput(s, jsNum(math.max(0, parsed)));
}

/// How a number is shown in an input: the raw value, no locale formatting (`62.5`, `60`).
String formatInputNumber(num? value) => value == null ? '' : '${jsNum(value)}';

/// Numeric text input accepting `,` as decimal separator. While focused it keeps the typed
/// draft (so `"33,"` survives); on blur it shows the committed value. Selects all on focus.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decimal = true,
    this.nullable = false,
    this.style,
    this.textAlign = TextAlign.center,
    this.hint,
    this.semanticLabel,
  });

  final num? value;
  final ValueChanged<num?> onChanged;

  /// Decimal keyboard and decimals allowed.
  final bool decimal;

  /// Empty clears to null (the caller deletes the key) instead of 0.
  final bool nullable;
  final TextStyle? style;
  final TextAlign textAlign;
  final String? hint;
  final String? semanticLabel;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _controller = TextEditingController(text: formatInputNumber(widget.value));
  final _focus = FocusNode();
  num? _committed;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _committed = widget.value;
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _editing = true;
      _committed = widget.value;
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    } else {
      _editing = false;
      _setText(formatInputNumber(widget.value));
    }
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    // Our own keystroke coming back keeps the draft ("33," stays "33."); any other change
    // (a stepper tap, a prescription) replaces it with the new value.
    if (_editing && widget.value == _committed) return;
    final text = formatInputNumber(widget.value);
    if (_controller.text != text) _setText(text);
    _committed = widget.value;
  }

  void _onChanged(String raw) {
    final input = parseNumberInput(raw, decimal: widget.decimal, nullable: widget.nullable);
    if (input.draft != raw) _setText(input.draft);
    _committed = input.value;
    widget.onChanged(input.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onChanged: _onChanged,
        textAlign: widget.textAlign,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: widget.style ?? TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: p.label),
        cursorColor: p.acc,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.hint,
          hintStyle: TextStyle(color: p.label3),
        ),
      ),
    );
  }
}

/// Default ± step: `max(0, round((value ?? 0) + dir * step, 2 decimals))`.
num stepValue(num? value, num step, int dir) => jsNum(math.max(0, (((value ?? 0) + dir * step) * 100).round() / 100));

/// `[−] value [+]` (specs/ui.md §2.8): `--surface-2` container, NumberField in the middle,
/// optional label above and unit after the value. [stepper] overrides the ± rule (effort uses
/// `stepEffort`).
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.decimal = true,
    this.nullable = false,
    this.label,
    this.unit,
    this.stepper,
    this.buttonWidth = 40,
    this.height = 44,
    this.valueStyle,
  });

  final num? value;
  final ValueChanged<num?> onChanged;
  final num step;
  final bool decimal;
  final bool nullable;

  /// Caption above (13 px label-2, centred).
  final String? label;

  /// Suffix after the number.
  final String? unit;

  /// Custom `(current, dir) → next` for the ± buttons.
  final num? Function(num? current, int dir)? stepper;

  /// 40 by default; set rows use 32, three-column rows 23 or 20.
  final double buttonWidth;
  final double height;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    num? next(int dir) => stepper != null ? stepper!(value, dir) : stepValue(value, step, dir);
    Widget button(String icon, int dir, String semantic) => Pressable(
      onTap: () => onChanged(next(dir)),
      pressedScale: .92,
      semanticLabel: semantic,
      child: SizedBox(
        width: buttonWidth,
        height: height,
        child: Center(child: AppIcon(icon, size: 16, color: p.label)),
      ),
    );
    final stepperBox = Container(
      height: height,
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          button('minus', -1, 'Menos'),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: NumberField(
                    value: value,
                    onChanged: onChanged,
                    decimal: decimal,
                    nullable: nullable,
                    style: valueStyle,
                    semanticLabel: label,
                  ),
                ),
                if (unit != null) Text(' $unit', style: TextStyle(fontSize: 13, color: p.label2)),
              ],
            ),
          ),
          button('plus', 1, 'Más'),
        ],
      ),
    );
    if (label == null) return stepperBox;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.caption,
        ),
        const SizedBox(height: 6),
        stepperBox,
      ],
    );
  }
}

/// One cell of a [Segmented] control.
class Segment<T> {
  const Segment(this.value, this.label, {this.icon});

  final T value;
  final String label;

  /// Optional [AppIcons] name.
  final String? icon;
}

/// Segmented control (specs/ui.md §2.8): equal cells on a track with a sliding thumb under
/// the selected one. A [value] not among the segments puts the thumb on the first cell.
/// [inline] is the compact variant used inside rows.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.inline = false,
  });

  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final index = math.max(0, segments.indexWhere((s) => s.value == value));
    final fontSize = inline ? 13.0 : 14.0;
    final n = segments.length;
    final control = Container(
      height: inline ? 30 : 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: p.segmentTrack, borderRadius: BorderRadius.circular(9)),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            duration: AppMotion.med,
            curve: AppMotion.ease,
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: p.segmentThumb,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: segments[i].label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(segments[i].value),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (segments[i].icon != null) ...[
                              AppIcon(segments[i].icon!, size: 16, color: i == index ? p.label : p.label2),
                              if (segments[i].label.isNotEmpty) const SizedBox(width: 4),
                            ],
                            if (segments[i].label.isNotEmpty)
                              Flexible(
                                child: Text(
                                  segments[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: i == index ? FontWeight.w500 : FontWeight.w400,
                                    color: i == index ? p.label : p.label2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    if (!inline) return control;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 132, maxWidth: math.max(132, 64.0 * n)),
      child: control,
    );
  }
}

/// The iOS-style switch: 51×31, accent when on, white knob.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;

  /// Null disables the switch (opacity .4).
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      child: Opacity(
        opacity: onChanged == null ? .4 : 1,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: AppMotion.med,
            curve: AppMotion.ease,
            width: 51,
            height: 31,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: value ? p.acc : p.surface3, borderRadius: BorderRadius.circular(99)),
            child: AnimatedAlign(
              duration: AppMotion.med,
              curve: AppMotion.ease,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 27,
                height: 27,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 2))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [ListRow] with a trailing [AppSwitch]; tapping the row toggles it.
class SwitchRow extends StatelessWidget implements GroupedRow {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.iconTint,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? icon;
  final Color? iconTint;

  @override
  bool get hasIcon => icon != null;

  @override
  Widget build(BuildContext context) => ListRow(
    title: title,
    subtitle: subtitle,
    icon: icon,
    iconTint: iconTint,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: AppSwitch(value: value, onChanged: onChanged, semanticLabel: title),
  );
}

/// Round checkbox (`Check`): 30 px; off = ring, on = filled accent with a check.
class RoundCheck extends StatelessWidget {
  const RoundCheck({super.key, required this.value, required this.onChanged, this.size = 30, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      checked: value,
      label: semanticLabel,
      child: Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        pressedScale: .9,
        button: false,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? p.acc : Colors.transparent,
            border: value ? null : Border.all(color: p.label4, width: 1.8),
          ),
          child: value
              ? Center(
                  child: AppIcon('check', size: size * .55, color: p.onAcc),
                )
              : null,
        ),
      ),
    );
  }
}

/// The app slider: 6 px track, accent fill, white knob; values snap to [step], rounded to
/// 3 decimals and clamped.
class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final num min;
  final num max;
  final num step;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  bool _dragging = false;

  num _valueAt(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    final raw = widget.min + f * (widget.max - widget.min);
    final snapped = (raw / widget.step).round() * widget.step;
    return jsNum(((snapped * 1000).round() / 1000).clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final range = widget.max - widget.min;
        final f = range == 0 ? 0.0 : ((widget.value - widget.min) / range).clamp(0.0, 1.0).toDouble();
        void update(double dx) => widget.onChanged(_valueAt(dx, width));
        final up = jsNum(math.min(widget.max, widget.value + widget.step));
        final down = jsNum(math.max(widget.min, widget.value - widget.step));
        return Semantics(
          slider: true,
          value: formatInputNumber(widget.value),
          increasedValue: formatInputNumber(up),
          decreasedValue: formatInputNumber(down),
          onIncrease: () => widget.onChanged(up),
          onDecrease: () => widget.onChanged(down),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => update(d.localPosition.dx),
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              update(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: SizedBox(
              height: 32,
              width: width,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(99)),
                  ),
                  Container(
                    height: 6,
                    width: width * f,
                    decoration: BoxDecoration(color: p.acc, borderRadius: BorderRadius.circular(99)),
                  ),
                  Positioned(
                    left: (width * f - 13).clamp(-13, width - 13),
                    child: AnimatedScale(
                      scale: _dragging ? 1.14 : 1,
                      duration: AppMotion.fast,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2))],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The search field (`.search`): magnifier inside a filled pill, clear button when non-empty.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Buscar…',
    this.initialValue = '',
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final String initialValue;
  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 17, color: p.label),
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: p.searchFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        prefixIcon: AppIcon('magnifier', size: 18, color: p.label3),
        prefixIconConstraints: const BoxConstraints(minWidth: 35, minHeight: 36),
        suffixIcon: _controller.text.isEmpty
            ? null
            : GestureDetector(
                onTap: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
                child: Semantics(
                  label: 'Borrar búsqueda',
                  button: true,
                  child: AppIcon('xmark', size: 16, color: p.label3),
                ),
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }
}
