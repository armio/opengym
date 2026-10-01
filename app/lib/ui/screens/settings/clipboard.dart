import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/widgets.dart';

/// Copies [text] to the clipboard and confirms it with a toast.
Future<void> copyToClipboard(BuildContext context, String text, {String message = 'Copiado'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, message);
}

/// A small round "copy" button for a row's trailing slot.
class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.text, this.message = 'Copiado', this.tooltip = 'Copiar'});

  final String text;
  final String message;
  final String tooltip;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: 'clipboard',
    tooltip: tooltip,
    size: 32,
    iconSize: 16,
    onPressed: () => copyToClipboard(context, text, message: message),
  );
}
