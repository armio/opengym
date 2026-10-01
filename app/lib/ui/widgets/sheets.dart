import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'buttons.dart';

/// Opens a bottom sheet in the app style (specs/ui.md §1.3): grab handle, optional title,
/// `--bg-el` background, top radius 22, at most 90 % of the screen, scrollable.
///
/// * [locked] sheets cannot be dismissed by backdrop tap, swipe or the back button — only by
///   their own buttons (`Navigator.pop(context, result)`).
/// * [expand] gives the sheet a fixed 90 % height; the builder then gets a bounded height and
///   must lay out its own scrolling (e.g. `Column` + `Expanded(ListView)`). Otherwise the
///   content is wrapped in a scroll view and the sheet hugs it.
///
/// Sheets stack: opening one from another puts it on top.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool locked = false,
  bool expand = false,
}) {
  final p = context.palette;
  return showModalBottomSheet<T>(
    context: context,
    // Above the tab bar and the tabs' nested navigators.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: !locked,
    enableDrag: !locked,
    backgroundColor: p.sheet,
    barrierColor: Colors.black.withValues(alpha: .4),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9, maxWidth: 640),
    builder: (ctx) => PopScope(
      canPop: !locked,
      child: _SheetFrame(title: title, expand: expand, builder: builder),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.expand, required this.builder});

  final String? title;
  final bool expand;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final p = context.palette;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 5,
            margin: const EdgeInsets.only(top: 6, bottom: 14),
            decoration: BoxDecoration(color: p.label4, borderRadius: BorderRadius.circular(99)),
          ),
        ),
        if (title != null) SheetTitle(title!),
      ],
    );
    final padding = EdgeInsets.fromLTRB(18, 8, 18, 20 + media.viewInsets.bottom + media.padding.bottom);
    if (expand) {
      return SizedBox(
        height: media.size.height * .9,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: Builder(builder: builder)),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          Builder(builder: builder),
        ],
      ),
    );
  }
}

/// A sheet's `h3` title: 20/600, margin-bottom 14.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key, this.leading});

  final String text;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(child: Text(text, style: context.textStyles.sheetTitle)),
      ],
    ),
  );
}

/// A centred dialog in the app style (`kind: 'center'`): max 300 px wide, radius 16,
/// padding 20. Returns what the content pops.
Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder, bool locked = false}) {
  final p = context.palette;
  return showDialog<T>(
    context: context,
    barrierDismissible: !locked,
    barrierColor: Colors.black.withValues(alpha: .4),
    builder: (ctx) => PopScope(
      canPop: !locked,
      child: Dialog(
        backgroundColor: p.dialog,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(ctx).width * .84).clamp(0, 300)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
}

/// The themed confirm dialog (`confirmSheet`): optional title, message, a confirm button
/// (red when [danger]) and a dim cancel button. Resolves to true only on confirm; tapping the
/// backdrop or going back cancels, unless [locked] (then only the two buttons answer).
Future<bool> showConfirm(
  BuildContext context, {
  String? title,
  required String message,
  String confirmText = 'Confirmar',
  String cancelText = 'Cancelar',
  bool danger = false,
  bool locked = false,
}) async {
  final result = await showAppDialog<bool>(
    context,
    locked: locked,
    builder: (ctx) {
      final t = ctx.textStyles;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title, textAlign: TextAlign.center, style: t.sheetTitle),
            const SizedBox(height: 8),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: t.body.copyWith(color: ctx.palette.label2, height: 1.5),
          ),
          const SizedBox(height: 18),
          AppButton(
            confirmText,
            variant: danger ? ButtonVariant.danger : ButtonVariant.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 8),
          AppButton(cancelText, variant: ButtonVariant.ghost, dim: true, onPressed: () => Navigator.of(ctx).pop(false)),
        ],
      );
    },
  );
  return result ?? false;
}

/// Shows a toast (specs/ui.md §1.5): one message at a time — a new one replaces the current —
/// visible 2.2 s, a pill above the tab bar. Works from any context under the app's overlay.
void showToast(BuildContext context, String message) => _Toast.show(context, message);

abstract final class _Toast {
  static OverlayEntry? _entry;
  static final _key = GlobalKey<_ToastViewState>();

  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final state = _key.currentState;
    if (_entry != null && state != null && state.mounted) {
      state.update(message);
      return;
    }
    _entry?.remove();
    final entry = OverlayEntry(
      builder: (_) => _ToastView(
        key: _key,
        message: message,
        onDone: () {
          _entry?.remove();
          _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key, required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  static const _visible = Duration(milliseconds: 2200);

  late String _message = widget.message;
  bool _shown = false;
  Timer? _hide;
  Timer? _remove;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
    _schedule();
  }

  void update(String message) {
    setState(() {
      _message = message;
      _shown = true;
    });
    _schedule();
  }

  void _schedule() {
    _hide?.cancel();
    _remove?.cancel();
    _hide = Timer(_visible, () {
      if (!mounted) return;
      setState(() => _shown = false);
      _remove = Timer(AppMotion.med, widget.onDone);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _remove?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final p = context.palette;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 96 + media.padding.bottom,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: AppMotion.med,
          curve: AppMotion.ease,
          child: AnimatedSlide(
            offset: _shown ? Offset.zero : const Offset(0, .15),
            duration: AppMotion.med,
            curve: AppMotion.ease,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: media.size.width * .88),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    decoration: BoxDecoration(
                      color: p.surface2.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: const [
                        BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10), spreadRadius: -6),
                      ],
                    ),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.label),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
