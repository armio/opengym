import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/api_client.dart';
import '../../../data/app_state.dart';
import '../../../data/sync.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// Server address + owner password + device name → device login → first (pull-only) sync with
/// progress → the app switches to the shell (contract §3.3.3, §4.1).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _server;
  final _password = TextEditingController();
  late final TextEditingController _deviceName;

  bool _busy = false;
  bool _obscure = true;
  String? _error;
  SyncProgress? _progress;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _server = TextEditingController(text: app.serverUrl ?? '');
    _deviceName = TextEditingController(text: app.deviceName ?? defaultDeviceName());
  }

  @override
  void dispose() {
    _server.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final app = context.read<AppState>();
    if (_password.text.isEmpty) {
      setState(() => _error = 'Escribe la contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await app.login(
        serverUrl: _server.text,
        password: _password.text,
        deviceName: _deviceName.text,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        confirmUpload: (summary) => confirmUploadLocalOnly(context, summary),
      );
      if (!mounted) return;
      if (!app.isSignedIn) {
        setState(() => _error = 'El servidor rechazó la sesión. Vuelve a intentarlo.');
      } else if (app.lastSyncError != null) {
        showToast(context, 'Sesión iniciada. Tus datos se descargarán cuando haya conexión.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = loginErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final media = MediaQuery.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, media.padding.top + 24, 24, media.padding.bottom + 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, minHeight: media.size.height * .78),
            child: AutofillGroup(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: AppIcon('dumbbell', size: 54, color: p.acc)),
                  const SizedBox(height: 10),
                  Text('openGym', textAlign: TextAlign.center, style: t.largeTitle),
                  const SizedBox(height: 4),
                  Text('Tus entrenos. Tus pesos. Tu servidor.', textAlign: TextAlign.center, style: t.subtitle),
                  const SizedBox(height: 30),
                  _Label('Servidor'),
                  TextField(
                    controller: _server,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.url],
                    decoration: const InputDecoration(hintText: 'https://opengym.tu-cuenta.workers.dev'),
                  ),
                  const SizedBox(height: 14),
                  _Label('Contraseña'),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      hintText: 'OWNER_PASSWORD del servidor',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: p.label3,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Label('Nombre de este dispositivo'),
                  TextField(
                    controller: _deviceName,
                    enabled: !_busy,
                    maxLength: 60,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(hintText: 'Dispositivo', counterText: ''),
                  ),
                  const SizedBox(height: 22),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: t.small.copyWith(color: p.red),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppButton(
                    _busy ? (_progress == null ? 'Conectando…' : 'Descargando tus datos…') : 'Entrar',
                    variant: ButtonVariant.primary,
                    busy: _busy,
                    onPressed: _submit,
                  ),
                  if (_busy && _progress != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${_progress!.items} ${_progress!.items == 1 ? 'elemento recibido' : 'elementos recibidos'}',
                      textAlign: TextAlign.center,
                      style: t.small,
                    ),
                  ],
                  const SizedBox(height: 26),
                  Text(
                    'Usa la dirección de tu Worker de Cloudflare y la contraseña OWNER_PASSWORD que configuraste. '
                    'Tus datos se guardan también en este dispositivo y funcionan sin conexión.',
                    textAlign: TextAlign.center,
                    style: t.small.copyWith(color: p.label3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(text, style: context.textStyles.caption),
  );
}

/// Spanish message for a failed login.
String loginErrorMessage(Object error) => switch (error) {
  FormatException(:final message) => message,
  UnauthorizedException() => 'Contraseña incorrecta',
  RateLimitedException() => 'Demasiados intentos fallidos. Espera unos minutos y vuelve a probar.',
  OfflineException() => 'No se pudo conectar con el servidor. Revisa la dirección y tu conexión.',
  RequestException(status: 404) => 'No hay un servidor de openGym en esa dirección.',
  ApiException(:final message) => message,
  _ => 'No se pudo iniciar sesión.',
};

/// A sensible default device name for the platform.
String defaultDeviceName() {
  if (kIsWeb) return 'Navegador';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'PC',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Dispositivo',
  };
}
