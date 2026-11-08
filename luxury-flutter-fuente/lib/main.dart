import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_screen.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'password_change_screen.dart';
import 'service_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  String? initializationError;
  SupabaseClient? client;
  if (url.isNotEmpty || publishableKey.isNotEmpty) {
    if (url.isEmpty || publishableKey.isEmpty) {
      initializationError =
          'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY juntos para habilitar la conexión.';
    } else {
      try {
        await Supabase.initialize(url: url, publishableKey: publishableKey);
        client = Supabase.instance.client;
      } catch (error) {
        initializationError = 'No se pudo inicializar Supabase: $error';
      }
    }
  }
  runApp(LuxuryApp(client: client, initializationError: initializationError));
}

class LuxuryApp extends StatefulWidget {
  const LuxuryApp({super.key, this.client, this.initializationError});
  final SupabaseClient? client;
  final String? initializationError;

  @override
  State<LuxuryApp> createState() => _LuxuryAppState();
}

class _LuxuryAppState extends State<LuxuryApp> {
  late final RestaurantStore store = RestaurantStore(client: widget.client);

  @override
  void initState() {
    super.initState();
    unawaited(store.initialize());
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Luxury · Restaurante Oriental',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: luxuryGold,
        primary: luxuryGold,
        secondary: luxuryBrown,
        error: luxuryRed,
        surface: const Color(0xFFFFFDFC),
      ),
      scaffoldBackgroundColor: luxuryBone,
      textTheme: ThemeData.light().textTheme
          .apply(bodyColor: luxuryInk, displayColor: luxuryInk)
          .copyWith(
            headlineSmall: const TextStyle(
              color: luxuryInk,
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
            titleLarge: const TextStyle(
              color: luxuryInk,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            titleMedium: const TextStyle(
              color: luxuryInk,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            bodyMedium: const TextStyle(color: luxuryMuted, height: 1.45),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: luxuryInk,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFDFC),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: luxuryBorder),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFDFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: luxuryBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: luxuryBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: luxuryGold, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: luxuryGold,
          foregroundColor: luxuryInk,
          minimumSize: const Size(44, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: luxuryBrown,
          side: const BorderSide(color: luxuryBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          minimumSize: const Size(44, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: luxuryBrown,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: luxuryBone,
        indicatorColor: luxuryGold.withValues(alpha: .18),
        selectedIconTheme: const IconThemeData(color: luxuryBrown),
        unselectedIconTheme: const IconThemeData(color: luxuryMuted),
        selectedLabelTextStyle: const TextStyle(
          color: luxuryBrown,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: luxuryMuted),
        groupAlignment: -.82,
        minWidth: 76,
        minExtendedWidth: 224,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFFFFDFC),
        indicatorColor: luxuryGold.withValues(alpha: .18),
        elevation: 8,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? luxuryBrown
                : luxuryMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFFFDFC),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: luxuryBorder),
        ),
        titleTextStyle: const TextStyle(
          color: luxuryInk,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: luxuryMuted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF0E8E1),
        selectedColor: luxuryGold.withValues(alpha: .2),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        labelStyle: const TextStyle(
          color: luxuryInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: luxuryBorder,
        thickness: 1,
        space: 1,
      ),
    ),
    home: _RootScreen(store: store, startupError: widget.initializationError),
  );
}

class _RootScreen extends StatelessWidget {
  const _RootScreen({required this.store, this.startupError});
  final RestaurantStore store;
  final String? startupError;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      if (store.loading) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: luxuryGold)),
        );
      }
      if (startupError != null) {
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorBanner(message: startupError!),
              ),
            ),
          ),
        );
      }
      if (store.role == null) return _LoginScreen(store: store);
      if (store.mustChangePassword) {
        return PasswordChangeScreen(store: store, requiredChange: true);
      }
      return _WorkScreen(store: store);
    },
  );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.store});
  final RestaurantStore store;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  String? emailError;
  String? passwordError;
  RestaurantStore get store => widget.store;

  Future<void> _login(StaffRole role) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await store.loginDemo(role);
    } catch (exception) {
      setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signIn() async {
    final normalizedEmail = email.text.trim();
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
    try {
      await store.signIn(normalizedEmail, password.text);
    } catch (exception) {
      setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendPasswordRecovery() async {
    try {
      await store.sendPasswordRecovery(email.text.trim());
      if (!mounted) return;
      await showResultDialog(
        context,
        success: true,
        title: 'Revisa tu correo',
        message:
            'Si el correo está registrado, recibirás instrucciones para recuperar el acceso.',
      );
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF17181D),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        if (!wide) {
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
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _LoginBrand(),
                          const SizedBox(height: 12),
                          Center(
                            child: _LoginCoverImage(
                              size: (constraints.maxWidth * .66)
                                  .clamp(210.0, 300.0)
                                  .toDouble(),
                            ),
                          ),
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
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
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

        return Container(
          color: const Color(0xFF17181D),
          padding: const EdgeInsets.all(26),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500, maxHeight: 900),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LayoutBuilder(
                  builder: (context, cardConstraints) => Stack(
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 42,
                                  vertical: 32,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 460,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      _loginContent(context, dark: true),
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
                        child: Icon(
                          Icons.menu,
                          color: Colors.white54,
                          size: 25,
                        ),
                      ),
                      const Positioned(left: 38, top: 38, child: _LoginBrand()),
                      Positioned(
                        left: 40,
                        bottom: 34,
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
                          size: (cardConstraints.maxWidth * .38)
                              .clamp(260.0, cardConstraints.maxHeight * .62)
                              .toDouble(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _loginContent(BuildContext context, {required bool dark}) {
    final titleColor = dark ? Colors.white : luxuryBrown;
    final detailColor = dark ? Colors.white70 : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          store.isConnected ? 'Iniciar sesión' : 'Bienvenido a Luxury',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: titleColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          store.isConnected
              ? 'Usa tu cuenta autorizada para ingresar al sistema.'
              : 'Elige el espacio de trabajo para recorrer la demostración.',
          style: TextStyle(color: detailColor, height: 1.5),
        ),
        const SizedBox(height: 28),
        if (store.isConnected) ...[
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (emailError != null) setState(() => emailError = null);
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
          if (error != null || store.errorMessage != null) ...[
            LoginFieldError(message: error ?? store.errorMessage!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : _signIn,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(busy ? 'Conectando…' : 'Iniciar sesión'),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: busy ? null : _sendPasswordRecovery,
              style: TextButton.styleFrom(foregroundColor: luxuryGold),
              child: const Text('¿Olvidaste tu contraseña?'),
            ),
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
      Column(
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
        'assets/images/portada_restaurante.png',
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

class _WorkScreen extends StatelessWidget {
  const _WorkScreen({required this.store});
  final RestaurantStore store;

  Future<void> _resetDemo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar demostración'),
        content: const Text(
          'Se eliminarán los cambios locales y volverán los datos de ejemplo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await store.resetDemo();
        if (context.mounted) {
          await showResultDialog(
            context,
            success: true,
            message: 'Demostración reiniciada.',
          );
        }
      } catch (error) {
        if (context.mounted) {
          await showResultDialog(context, success: false, message: '$error');
        }
      }
    }
  }

  Future<void> _syncPendingOrders(BuildContext context) async {
    try {
      await store.syncPendingOrders();
      if (context.mounted) {
        await showResultDialog(
          context,
          success: true,
          message: 'Pedidos pendientes sincronizados.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        await showResultDialog(context, success: false, message: '$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = store.role!;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: luxuryGold.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.restaurant, color: luxuryGold, size: 21),
            ),
            const SizedBox(width: 10),
            const Text(
              'LUXURY',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(width: 12),
            if (MediaQuery.sizeOf(context).width > 650)
              Text(
                '· ${role.label}',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width > 600)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Chip(
                avatar: Icon(
                  store.isConnected ? Icons.cloud_done : Icons.wifi_off,
                  size: 17,
                ),
                label: Text(store.isConnected ? 'Supabase' : 'Demo local'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: store.displayName,
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) {
              if (value == 'logout') unawaited(store.signOut());
              if (value == 'reset') unawaited(_resetDemo(context));
              if (value == 'password') {
                unawaited(showPasswordChangeDialog(context, store));
              }
              if (value == 'sync') {
                unawaited(_syncPendingOrders(context));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                value: 'account',
                child: Text('${store.displayName}\n${role.label}'),
              ),
              if (store.isConnected)
                const PopupMenuItem(
                  value: 'password',
                  child: Text('Cambiar contraseña'),
                ),
              if (store.isDemo)
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Reiniciar demostración'),
                ),
              if (store.pendingOrderCount > 0)
                PopupMenuItem(
                  value: 'sync',
                  child: Text(
                    'Sincronizar pedidos (${store.pendingOrderCount})',
                  ),
                ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Cerrar sesión'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (role) {
        StaffRole.administrator => AdminScreen(store: store),
        StaffRole.manager => AdminScreen(store: store, managerOnly: true),
        StaffRole.kitchen => KitchenScreen(store: store),
        StaffRole.headChef => KitchenScreen(store: store),
        StaffRole.waiter => WaiterScreen(store: store),
        StaffRole.cashier => CashierScreen(store: store),
      },
    );
  }
}
