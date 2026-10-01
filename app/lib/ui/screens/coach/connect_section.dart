import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../settings/clipboard.dart';

/// Prompts that get Claude working with openGym, ready to copy.
const suggestedPrompts = [
  'Diseña mi plan de entrenamiento con openGym',
  'Revisa mis últimas semanas de entrenamiento y propón cambios',
  '¿Cómo va mi progreso en press de banca?',
  'Mis sesiones se alargan demasiado: propón cómo acortarlas sin perder lo importante',
  'Actualiza mi perfil de atleta: ahora puedo entrenar 4 días a la semana',
];

/// The Claude Code command that adds the connector.
String claudeCodeCommand(String url) => 'claude mcp add --transport http opengym $url';

/// "Conectar Claude" (contract §6.5): the connector URL (`<server>/mcp`) with a copy button,
/// how to add it in claude.ai, Claude Desktop and Claude Code, and prompts to start with.
class CoachConnectSection extends StatelessWidget {
  const CoachConnectSection({super.key});

  @override
  Widget build(BuildContext context) {
    final url = context.select<AppState, String?>((s) => s.connectorUrl);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: 'Conectar Claude',
          footer: 'Claude puede leer tus entrenos y proponerte planes; nada cambia hasta que lo aceptes aquí.',
          children: [
            ListRow(
              icon: 'link',
              iconTint: p.orange,
              title: 'URL del conector',
              subtitle: url ?? 'Inicia sesión en tu servidor para obtener la URL.',
              trailing: url == null ? null : CopyButton(text: url, message: 'URL del conector copiada'),
            ),
          ],
        ),
        Section(
          title: 'Cómo añadirlo',
          children: [
            ListRow(
              icon: 'globe',
              iconTint: p.blue,
              title: 'claude.ai',
              subtitle:
                  'Ajustes → Conectores → Añadir conector personalizado → pega la URL → inicia sesión '
                  'con la contraseña de tu servidor y pulsa «Permitir».',
            ),
            ListRow(
              icon: 'personCircle',
              iconTint: p.indigo,
              title: 'Claude Desktop',
              subtitle:
                  'El mismo conector: añádelo igual en Ajustes → Conectores (si ya lo añadiste en '
                  'claude.ai, aparece también aquí).',
            ),
            ListRow(
              icon: 'wrench',
              iconTint: p.grey,
              title: 'Claude Code',
              subtitle: url == null
                  ? 'claude mcp add --transport http opengym <URL>'
                  : '${claudeCodeCommand(url)}\nLuego escribe /mcp en Claude Code para iniciar sesión.',
              trailing: url == null
                  ? null
                  : CopyButton(text: claudeCodeCommand(url), message: 'Comando copiado', tooltip: 'Copiar comando'),
            ),
          ],
        ),
        Section(
          title: 'Pídeselo a Claude',
          footer: 'Sus propuestas llegan a esta pestaña para que decidas qué aplicar.',
          children: [
            for (final prompt in suggestedPrompts)
              ListRow(
                title: prompt,
                trailing: CopyButton(text: prompt, message: 'Petición copiada', tooltip: 'Copiar petición'),
              ),
          ],
        ),
      ],
    );
  }
}
