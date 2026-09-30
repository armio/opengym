import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/widgets.dart';

/// The word the owner types to confirm "Borrar todo".
const resetConfirmationWord = 'BORRAR';

/// "Borrar todo" asks for the word [resetConfirmationWord] before its button unlocks.
/// Resolves to true only when confirmed.
Future<bool> showResetConfirm(BuildContext context) async =>
    await showAppDialog<bool>(context, builder: (_) => const _ResetConfirm()) ?? false;

class _ResetConfirm extends StatefulWidget {
  const _ResetConfirm();

  @override
  State<_ResetConfirm> createState() => _ResetConfirmState();
}

class _ResetConfirmState extends State<_ResetConfirm> {
  final _typed = TextEditingController();

  bool get _matches => _typed.text.trim().toUpperCase() == resetConfirmationWord;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Borrar todo?', textAlign: TextAlign.center, style: t.sheetTitle),
        const SizedBox(height: 8),
        Text(
          'Se borran en el servidor tu plan, tus entrenos, tu peso corporal y tus pesos de trabajo, y se '
          'descartan las propuestas pendientes de Claude. Después se vacía este dispositivo. '
          'No se puede deshacer.',
          textAlign: TextAlign.center,
          style: t.body.copyWith(color: p.label2, height: 1.5, fontSize: 15),
        ),
        const SizedBox(height: 14),
        Text('Escribe $resetConfirmationWord para confirmar', style: t.caption),
        const SizedBox(height: 6),
        TextField(
          controller: _typed,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: resetConfirmationWord),
        ),
        const SizedBox(height: 18),
        AppButton(
          'Borrar todo',
          variant: ButtonVariant.danger,
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
        ),
        const SizedBox(height: 8),
        AppButton(
          'Cancelar',
          variant: ButtonVariant.ghost,
          dim: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
