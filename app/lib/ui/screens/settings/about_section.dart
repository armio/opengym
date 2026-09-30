import 'package:flutter/material.dart';

import '../../../data/library.dart' show mediaAttribution;
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'clipboard.dart';

/// The app version shown in "Acerca de"; release builds pass `--dart-define=APP_VERSION=…`.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Where the original openGym lives.
const originalProjectUrl = 'https://github.com/DuarteSantos8/openGym';

/// "Acerca de": version, licence, the exercise dataset and media credits, and the original
/// project.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Section(
      title: 'Acerca de',
      children: [
        ListRow(icon: 'info', iconTint: p.grey, title: 'Versión', value: appVersion),
        ListRow(
          icon: 'lock',
          iconTint: p.green,
          title: 'Licencia AGPL-3.0',
          subtitle: 'openGym es software libre y de código abierto: puedes usarlo, estudiarlo y modificarlo.',
        ),
        ListRow(
          icon: 'dumbbell',
          iconTint: p.orange,
          title: 'Ejercicios',
          subtitle:
              'Datos e instrucciones: hasaneyldrm/exercises-dataset (MIT). Imágenes y animaciones $mediaAttribution',
        ),
        ListRow(
          icon: 'figureStrength',
          iconTint: p.teal,
          title: 'Diagrama corporal',
          subtitle: 'Basado en MuscleMap de Melih Colpan (MIT).',
        ),
        ListRow(
          icon: 'link',
          iconTint: p.indigo,
          title: 'Proyecto original',
          subtitle: 'openGym de Duarte Santos · ${originalProjectUrl.replaceFirst('https://', '')}',
          trailing: const CopyButton(text: originalProjectUrl, message: 'Enlace copiado'),
        ),
      ],
    );
  }
}
