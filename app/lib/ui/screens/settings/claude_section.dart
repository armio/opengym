import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'clipboard.dart';

/// "Conectar Claude": the MCP connector URL (`<server>/mcp`) with a copy button and the
/// steps to add it in Claude.
class ConnectClaudeSection extends StatelessWidget {
  const ConnectClaudeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final url = context.select<AppState, String?>((s) => s.connectorUrl);
    final p = context.palette;
    return Section(
      title: 'Claude',
      footer:
          '1. En Claude, abre Ajustes → Conectores → Añadir conector personalizado.\n'
          '2. Pega esta URL y guarda.\n'
          '3. Se abrirá tu servidor: escribe su contraseña y pulsa «Permitir».\n'
          'Claude podrá leer tus entrenos y proponerte planes; nada cambia hasta que lo aceptes en Coach.',
      children: [
        ListRow(
          icon: 'sparkles',
          iconTint: p.orange,
          title: 'Conectar Claude',
          subtitle: url ?? 'Inicia sesión en tu servidor para obtener la URL.',
          trailing: url == null ? null : CopyButton(text: url, message: 'URL del conector copiada'),
        ),
      ],
    );
  }
}
