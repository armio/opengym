import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../theme.dart';
import 'timer_bar.dart' show clockText;

/// Time since [start] as `m:ss` with unbounded minutes ("75:03"). It rebuilds on its own every
/// second, so the screen around it does not.
class ElapsedText extends StatefulWidget {
  const ElapsedText({super.key, required this.start, this.style});

  /// Epoch ms.
  final int start;

  /// Defaults to the header subtitle style.
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _timer;
  late String _text = _now();

  String _now() {
    final seconds = (context.read<AppState>().clock.nowMs() - widget.start) ~/ 1000;
    return clockText(seconds < 0 ? 0 : seconds);
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _now();
      if (next != _text) setState(() => _text = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_text, style: widget.style ?? context.textStyles.subtitle);
}
