import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/widgets.dart';

/// The RIR ↔ RPE table (specs/ui.md §3.9 "Effort help sheet"): one judgement counted from
/// opposite ends, with the row most working sets land on highlighted.
Future<void> showEffortHelpSheet(BuildContext context) =>
    showAppSheet<void>(context, title: 'Esfuerzo por serie', builder: (_) => const _EffortHelp());

const _rows = [
  ('0', '10', 'Nada más — hasta el fallo'),
  ('1', '9', 'Una repetición más en reserva'),
  ('2', '8', 'Dos repeticiones más'),
  ('3', '7', 'Tres repeticiones más'),
  ('4+', '≤6', 'Fácil — zona de calentamiento'),
];

/// RIR 2 / RPE 8: where a working set usually lands.
const _typicalRow = 2;

class _EffortHelp extends StatelessWidget {
  const _EffortHelp();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    Widget row(String rir, String rpe, String feel, {bool header = false, bool highlighted = false}) {
      final numberStyle = header
          ? t.microCaps.copyWith(fontWeight: FontWeight.w600)
          : TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: highlighted ? p.acc : p.label);
      final feelStyle = header
          ? t.microCaps.copyWith(fontWeight: FontWeight.w600)
          : TextStyle(fontSize: 15, height: 1.3, color: highlighted ? p.label : p.label2);
      return Container(
        color: header ? p.surface2 : (highlighted ? p.accSoft : null),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: header ? 8 : 10),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(rir, textAlign: TextAlign.center, style: numberStyle),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: Text(rpe, textAlign: TextAlign.center, style: numberStyle),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(header ? feel.toUpperCase() : feel, style: feelStyle)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Lo dura que fue una serie, junto al peso y las repeticiones. Dos escalas para lo mismo, '
          'contadas desde extremos opuestos.',
          style: t.small,
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: ColoredBox(
            color: p.surface,
            child: Column(
              children: [
                row('RIR', 'RPE', 'Cómo se sintió', header: true),
                for (var i = 0; i < _rows.length; i++) ...[
                  Divider(height: .5, thickness: .5, indent: 14, color: p.sep),
                  row(_rows[i].$1, _rows[i].$2, _rows[i].$3, highlighted: i == _typicalRow),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'El RIR cuenta las repeticiones que dejas; el RPE lee ese mismo esfuerzo en una escala de 10 — '
          'así que RPE ≈ 10 − RIR. Elige la que ya usas para pensar.',
          style: t.small.copyWith(color: p.label3),
        ),
        const SizedBox(height: 8),
        Text(
          'La fila resaltada es donde cae la mayoría de las series efectivas. Las series ya registradas '
          'conservan su escala, y nada más lee el valor: la progresión y el 1RM estimado no cambian.',
          style: t.small.copyWith(color: p.label3),
        ),
      ],
    );
  }
}
