import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_widgets.dart';
import '../data/restaurant_store.dart';
import '../models/models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.store});
  final RestaurantStore store;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  String? emailError;
  String? passwordError;
  String? _lockedEmail;
  String? _lockMessage;
  DateTime? _lockedUntil;
  Timer? _lockTimer;

  RestaurantStore get store => widget.store;
  String get _emailKey => email.text.trim().toLowerCase();
  bool get _locked =>
      _emailKey == _lockedEmail &&
      (_lockedUntil?.isAfter(DateTime.now()) ?? false);

  Future<void> _login(StaffRole role) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await store.loginDemo(role);
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signIn() async {
    if (busy || _locked) return;
    final normalizedEmail = email.text.trim();
    final emailKey = _emailKey;
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!validEmail.hasMatch(normalizedEmail) || password.text.isEmpty) {
      setState(() {
        emailError = validEmail.hasMatch(normalizedEmail)
            ? null
            : 'Usa un correo válido, como nombre@empresa.com';
        passwordError = password.text.isEmpty ? 'Ingresa tu contraseña.' : null;
        error = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      emailError = null;
      passwordError = null;
    });
    var showWarning = false;
    try {
      await store.signIn(normalizedEmail, password.text);
    } on LoginAttemptException catch (exception) {
      if (!mounted) return;
      showWarning = exception.isLastAttempt;
      final lockedUntil = exception.lockedUntil;
      setState(() {
        if (lockedUntil == null) {
          error = exception.message;
        } else {
          _lockedEmail = emailKey;
          _lockedUntil = lockedUntil;
          _lockMessage = exception.message;
        }
      });
      if (lockedUntil != null) {
        password.clear();
        _lockTimer?.cancel();
        _lockTimer = Timer(lockedUntil.difference(DateTime.now()), () {
          if (!mounted) return;
          setState(() {
            _lockedEmail = null;
            _lockedUntil = null;
            _lockMessage = null;
          });
        });
      }
    } on AuthRetryableFetchException {
      if (mounted) {
        setState(
          () => error =
              'La conexión tardó demasiado. Intenta iniciar sesión de nuevo.',
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => error =
              'No se pudieron cargar tus datos a tiempo. Vuelve a intentarlo.',
        );
      }
    } on StateError catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } on AuthException catch (exception) {
      if (!mounted) return;
      setState(
        () => error = switch (exception.code) {
          'invalid_credentials' => 'El correo o la contraseña son incorrectos.',
          'email_not_confirmed' =>
            'Tu correo aún no está confirmado. Contacta a Administración.',
          'over_request_rate_limit' =>
            'Hubo varios intentos. Espera un momento y vuelve a intentarlo.',
          _ => 'No se pudo iniciar sesión. Inténtalo de nuevo.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo iniciar sesión. Si el problema continúa, contacta a Administración.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (showWarning && mounted) await _showLastAttemptWarning();
  }

  Future<void> _showLastAttemptWarning() async {
    await showLuxuryDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: luxuryGold),
        title: const Text('Te queda un último intento'),
        content: const Text(
          'Revisa tu correo y tu contraseña. Si el próximo intento falla, se bloqueará temporalmente el acceso para este correo.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF17181D),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final landscape = width >= 820 && height < 540;
        final wide = height >= 340 && (width >= 1000 || landscape);
        if (!wide) {
          final compact = height < 610;
          final coverSize = math.min(
            (width * .58).clamp(140.0, 300.0).toDouble(),
            (height * .31).clamp(100.0, 300.0).toDouble(),
          );
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF25262D), Color(0xFF17181D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: luxuryBone,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        compact ? 14 : 24,
                        24,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _LoginBrand(),
                          const SizedBox(height: 12),
                          Center(child: _LoginCoverImage(size: coverSize)),
                          const Text(
                            'SABOR QUE REÚNE',
                            style: TextStyle(
                              color: luxuryBrown,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CustomPaint(
                      painter: const _IngredientBackdropPainter(mobile: true),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compact ? 18 : 28,
                          24,
                          32,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _loginContent(context, dark: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(height < 490 ? 18 : 26),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LayoutBuilder(
              builder: (context, cardConstraints) {
                final cardWidth = cardConstraints.maxWidth;
                final cardHeight = cardConstraints.maxHeight;
                final formScale = (cardWidth / 1400)
                    .clamp(1.0, 1.42)
                    .toDouble();
                final short = cardHeight < 490;
                final artworkHeight = short
                    ? cardHeight - 168
                    : cardHeight * .65;
                return Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.white),
                    ),
                    Positioned(
                      left: cardConstraints.maxWidth * .4,
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF202127), Color(0xFF17181D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: SafeArea(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.symmetric(
                                horizontal: short ? 26 : 42,
                                vertical: short ? 20 : 32,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 460 * formScale,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ASIAN FOOD  ·  CHINCHA',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 3,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    _loginContent(
                                      context,
                                      dark: true,
                                      scale: formScale,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: const _IngredientBackdropPainter(),
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 24,
                      right: 24,
                      child: Icon(Icons.menu, color: Colors.white54, size: 25),
                    ),
                    Positioned(
                      left: 38,
                      top: short ? 18 : 38,
                      width: cardWidth * .4 - 62,
                      child: const _LoginBrand(),
                    ),
                    Positioned(
                      left: 40,
                      bottom: short ? 14 : 34,
                      width: cardConstraints.maxWidth * .28,
                      child: Text(
                        store.isConnected
                            ? 'PEDIDOS, SERVICIO Y GESTIÓN EN UN SOLO LUGAR.'
                            : 'SABOR ORIENTAL, SERVICIO QUE REÚNE.',
                        style: const TextStyle(
                          color: Color(0xFF76685F),
                          fontSize: 11,
                          height: 1.6,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.15,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      width: cardConstraints.maxWidth * .4,
                      top: 0,
                      bottom: 0,
                      child: _LoginArtwork(
                        size: math.min(cardWidth * .38, artworkHeight),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
  );

  Widget _loginContent(
    BuildContext context, {
    required bool dark,
    double scale = 1,
  }) {
    final titleColor = dark ? Colors.white : luxuryBrown;
    final detailColor = dark ? Colors.white70 : Colors.black54;
    final formError = _locked ? _lockMessage : error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          store.isConnected ? 'Iniciar sesión' : 'Bienvenido a Luxury',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: titleColor,
            fontSize: 28 * scale,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          store.isConnected
              ? 'Usa tu cuenta autorizada para ingresar al sistema.'
              : 'Elige el espacio de trabajo para recorrer la demostración.',
          style: TextStyle(
            color: detailColor,
            fontSize: 14 * scale,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        if (store.isConnected) ...[
          TextField(
            controller: email,
            style: TextStyle(fontSize: 16 * scale),
            readOnly: busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (emailError != null || _lockedEmail != null) {
                setState(() => emailError = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'Correo',
              prefixIcon: const Icon(Icons.alternate_email),
              suffixIcon: emailError == null
                  ? null
                  : const Icon(Icons.error, color: Color(0xFFF05B6C)),
              errorText: emailError == null ? null : ' ',
              errorStyle: const TextStyle(height: 0, fontSize: 0),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFF05B6C),
                  width: 1.3,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFF05B6C),
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (emailError != null) LoginFieldError(message: emailError!),
          const SizedBox(height: 14),
          TextField(
            controller: password,
            style: TextStyle(fontSize: 16 * scale),
            readOnly: busy,
            obscureText: true,
            onSubmitted: (_) => _signIn(),
            onChanged: (_) {
              if (passwordError != null) setState(() => passwordError = null);
            },
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: passwordError == null
                  ? null
                  : const Icon(Icons.error, color: Color(0xFFF05B6C)),
              errorText: passwordError == null ? null : ' ',
              errorStyle: const TextStyle(height: 0, fontSize: 0),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFF05B6C),
                  width: 1.3,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFF05B6C),
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (passwordError != null) LoginFieldError(message: passwordError!),
          if (formError != null || store.errorMessage != null) ...[
            LoginFieldError(
              message:
                  formError ??
                  'No se pudo acceder al sistema. Inténtalo de nuevo.',
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy || _locked ? null : _signIn,
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(52 * scale),
                disabledBackgroundColor: const Color(0xFF3B2926),
                disabledForegroundColor: const Color(0xFFFFD7AA),
                textStyle: TextStyle(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Iniciar sesión'),
            ),
          ),
          SizedBox(
            height: 16,
            child: busy
                ? const Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      color: luxuryGold,
                      backgroundColor: Color(0xFF4D332B),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      minHeight: 5,
                      semanticsLabel: 'Progreso de inicio de sesión',
                    ),
                  )
                : null,
          ),
        ] else ...[
          if (error != null) ...[
            LoginFieldError(message: error!),
            const SizedBox(height: 12),
          ],
          ...StaffRole.values.map(
            (role) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                color: const Color(0xFF3B211E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF5B3A32)),
                ),
                child: ListTile(
                  onTap: busy ? null : () => _login(role),
                  leading: CircleAvatar(
                    backgroundColor: luxuryGold.withValues(alpha: .18),
                    child: Icon(_roleIcon(role), color: luxuryGold),
                  ),
                  title: Text(
                    role.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    _roleDescription(role),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.arrow_forward_ios,
                          size: 15,
                          color: luxuryGold,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Modo local de demostración: los cambios se conservan en este dispositivo y no se envían a Supabase.',
            style: TextStyle(color: detailColor, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }

  static IconData _roleIcon(StaffRole role) => switch (role) {
    StaffRole.administrator => Icons.space_dashboard_outlined,
    StaffRole.manager => Icons.manage_accounts_outlined,
    StaffRole.kitchen => Icons.soup_kitchen_outlined,
    StaffRole.headChef => Icons.restaurant_menu,
    StaffRole.waiter => Icons.table_restaurant,
    StaffRole.cashier => Icons.point_of_sale,
  };

  static String _roleDescription(StaffRole role) => switch (role) {
    StaffRole.administrator =>
      'Dashboard, menú, inventario, usuarios y reportes',
    StaffRole.manager => 'Reportes, incidencias, usuarios y auditoría',
    StaffRole.kitchen => 'Comandas en vivo, disponibilidad y faltantes',
    StaffRole.headChef => 'Comandas, alertas, disponibilidad y solicitudes',
    StaffRole.waiter => 'Mesas, pedidos, observaciones y seguimiento',
    StaffRole.cashier => 'Pagos mixtos, notas de venta y arqueo',
  };
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: luxuryGold, width: 2),
        ),
        child: const Icon(Icons.restaurant, color: luxuryBrown, size: 30),
      ),
      const SizedBox(width: 14),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LUXURY',
              style: TextStyle(
                color: luxuryBrown,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            Text(
              'RESTAURANTE ORIENTAL',
              style: TextStyle(
                color: luxuryBrown.withValues(alpha: .6),
                fontSize: 9,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _LoginArtwork extends StatelessWidget {
  const _LoginArtwork({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Center(child: _LoginCoverImage(size: size));
}

class _LoginCoverImage extends StatelessWidget {
  const _LoginCoverImage({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF1B1005),
      shape: BoxShape.circle,
      border: Border.all(color: luxuryGold, width: 5),
      boxShadow: [
        BoxShadow(
          color: luxuryBrown.withValues(alpha: .28),
          blurRadius: 32,
          offset: const Offset(12, 20),
        ),
      ],
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/images/portada_restaurante.webp',
        fit: BoxFit.cover,
        semanticLabel: 'Portada ilustrada del restaurante Luxury',
      ),
    ),
  );
}

class _IngredientBackdropPainter extends CustomPainter {
  const _IngredientBackdropPainter({this.mobile = false});

  final bool mobile;

  @override
  void paint(Canvas canvas, Size size) {
    final darkPanelLeft = mobile ? 0.0 : size.width * .4;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(darkPanelLeft, 0, size.width, size.height));

    final greens = [
      const Color(0xFF648D37),
      const Color(0xFF7FA649),
      const Color(0xFF3E6A32),
    ];
    final topStems = mobile
        ? [
            (size.width * .22, -.01, .08, .13),
            (size.width * .51, -.02, .10, .17),
            (size.width * .78, -.01, -.04, .15),
          ]
        : [
            (size.width * .415, -.02, .02, .13),
            (size.width * .45, -.02, .04, .16),
            (size.width * .485, -.02, .055, .12),
          ];

    for (var index = 0; index < topStems.length; index++) {
      final (x, y, dx, dy) = topStems[index];
      final base = Offset(x, y * size.height);
      final tip = Offset(x + dx * size.width, dy * size.height);
      final stem = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx + dx * size.width * .12,
          size.height * dy * .58,
          tip.dx,
          tip.dy,
        );
      canvas.drawPath(
        stem,
        Paint()
          ..color = greens[index % greens.length].withValues(alpha: .8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = mobile ? 2 : 3
          ..strokeCap = StrokeCap.round,
      );

      for (final step in [.34, .68]) {
        final origin = Offset(
          base.dx + (tip.dx - base.dx) * step,
          base.dy + (tip.dy - base.dy) * step,
        );
        final side = step == .47 ? -1.0 : 1.0;
        _drawLeaf(
          canvas,
          origin,
          angle: math.pi / 2 + side * (.28 + index * .035),
          length: size.width * (mobile ? .045 : .025),
          width: size.width * (mobile ? .012 : .009),
          color: greens[(index + 1) % greens.length],
        );
      }
    }

    final garnish = mobile
        ? [
            (.18, .86, const Color(0xFF789548)),
            (.82, .91, const Color(0xFF668438)),
            (.63, .76, const Color(0xFF779243)),
          ]
        : [
            (.44, .86, const Color(0xFF789548)),
            (.91, .86, const Color(0xFF668438)),
          ];

    for (final (x, y, color) in garnish) {
      final origin = Offset(size.width * x, size.height * y);
      _drawLeaf(
        canvas,
        origin,
        angle: -.65,
        length: size.width * (mobile ? .065 : .032),
        width: size.width * (mobile ? .018 : .009),
        color: color,
      );
      _drawLeaf(
        canvas,
        origin.translate(size.width * .012, 0),
        angle: 2.45,
        length: size.width * (mobile ? .055 : .027),
        width: size.width * (mobile ? .016 : .008),
        color: color.withValues(alpha: .8),
      );
    }

    final specks = mobile
        ? [
            (.1, .77, 3.0, const Color(0xFFE78C38)),
            (.9, .8, 2.4, const Color(0xFF9C4938)),
            (.72, .96, 2.2, const Color(0xFFA5A080)),
            (.27, .94, 2.0, const Color(0xFF668438)),
          ]
        : [
            (.47, .84, 3.0, const Color(0xFFE78C38)),
            (.52, .92, 2.4, const Color(0xFF9C4938)),
            (.71, .87, 2.2, const Color(0xFFA5A080)),
            (.83, .95, 2.0, const Color(0xFF668438)),
            (.93, .73, 2.2, const Color(0xFFE78C38)),
            (.55, .08, 2.0, const Color(0xFF6D8B42)),
          ];

    for (final (x, y, radius, color) in specks) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        radius,
        Paint()..color = color.withValues(alpha: .75),
      );
    }

    canvas.restore();
  }

  void _drawLeaf(
    Canvas canvas,
    Offset start, {
    required double angle,
    required double length,
    required double width,
    required Color color,
  }) {
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-direction.dy, direction.dx);
    final tip = start + direction * length;
    final middle = Offset.lerp(start, tip, .52)!;
    final leaf = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        middle.dx + normal.dx * width,
        middle.dy + normal.dy * width,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        middle.dx - normal.dx * width,
        middle.dy - normal.dy * width,
        start.dx,
        start.dy,
      );
    canvas.drawPath(leaf, Paint()..color = color.withValues(alpha: .9));
    canvas.drawLine(
      start,
      tip,
      Paint()
        ..color = const Color(0xFFB4C47A).withValues(alpha: .45)
        ..strokeWidth = .7,
    );
  }

  @override
  bool shouldRepaint(_IngredientBackdropPainter oldDelegate) =>
      mobile != oldDelegate.mobile;
}
