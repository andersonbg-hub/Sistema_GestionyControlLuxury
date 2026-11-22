import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_widgets.dart';
import 'data/restaurant_store.dart';
import 'data/supabase_http_client.dart';
import 'models/models.dart';
import 'views/admin/dashboard_screen.dart';
import 'views/password_change_screen.dart';
import 'views/cashier/cashier_screen.dart';
import 'views/kitchen/kitchen_screen.dart';
import 'views/waiter/waiter_screen.dart';
import 'views/staff_profile_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  String? initializationError;
  SupabaseClient? client;
  final openedFromFile = kIsWeb && Uri.base.scheme == 'file';
  if (!openedFromFile && (url.isNotEmpty || publishableKey.isNotEmpty)) {
    if (url.isEmpty || publishableKey.isEmpty) {
      initializationError =
          'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY juntos para habilitar la conexión.';
    } else {
      try {
        await Supabase.initialize(
          url: url,
          publishableKey: publishableKey,
          httpClient: SupabaseHttpClient(),
          postgrestOptions: const PostgrestClientOptions(
            requestTimeout: Duration(seconds: 10),
            retryCount: 1,
          ),
        );
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
    title: widget.client == null && widget.initializationError == null
        ? 'Luxury · Demostración local'
        : 'Luxury · Restaurante Oriental',
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
        backgroundColor: luxuryBrown,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFDFC),
        elevation: 1,
        shadowColor: Color(0x102A0F0D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
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
        backgroundColor: const Color(0xFFFFFDFC),
        indicatorColor: luxuryGold.withValues(alpha: .18),
        selectedIconTheme: const IconThemeData(color: luxuryBrown),
        unselectedIconTheme: const IconThemeData(color: luxuryMuted),
        selectedLabelTextStyle: const TextStyle(
          color: luxuryBrown,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: luxuryMuted),
        groupAlignment: -.82,
        minWidth: 80,
        minExtendedWidth: 224,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFFFFDFC),
        indicatorColor: luxuryGold.withValues(alpha: .18),
        elevation: 0,
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

class _RootScreen extends StatefulWidget {
  const _RootScreen({required this.store, this.startupError});
  final RestaurantStore store;
  final String? startupError;

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> with WidgetsBindingObserver {
  Timer? _midnight;
  late DateTime _businessDay;
  RestaurantStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _businessDay = limaBusinessDay(DateTime.now());
    _updateBusinessDay();
  }

  void _updateBusinessDay() {
    _midnight?.cancel();
    final now = DateTime.now();
    final day = limaBusinessDay(now);
    if (day != _businessDay) setState(() => _businessDay = day);
    _midnight = Timer(
      nextLimaMidnight(now).difference(now),
      _updateBusinessDay,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _updateBusinessDay();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      if (store.loading) {
        return const Scaffold(
          body: Center(
            child: OperationLabel(label: 'Cargando Luxury…', loading: true),
          ),
        );
      }
      if (widget.startupError != null) {
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorBanner(message: widget.startupError!),
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
    if (busy) return;
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
    if (busy) return;
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
          if (error != null || store.errorMessage != null) ...[
            LoginFieldError(
              message:
                  error ?? 'No se pudo acceder al sistema. Inténtalo de nuevo.',
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : _signIn,
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

typedef _ReadyLineNotice = ({String key, OrderLine line});
typedef _ReadyOrderNotice = ({
  RestaurantOrder order,
  List<_ReadyLineNotice> lines,
});

class _WorkScreen extends StatefulWidget {
  const _WorkScreen({required this.store});
  final RestaurantStore store;

  @override
  State<_WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<_WorkScreen>
    with OperationProgress<_WorkScreen> {
  RestaurantStore get store => widget.store;
  final _readReadyLines = ValueNotifier<Set<String>>(<String>{});
  SharedPreferences? _noticePreferences;
  String? _noticePreferencesKey;
  bool _readyNoticesLoaded = false;
  Future<void> _noticeWrite = Future<void>.value();

  @override
  void initState() {
    super.initState();
    if (store.role == StaffRole.waiter) unawaited(_restoreReadyNotices());
  }

  @override
  void dispose() {
    _readReadyLines.dispose();
    super.dispose();
  }

  Future<void> _restoreReadyNotices() async {
    final userId = store.userId;
    if (userId != null) {
      _noticePreferencesKey = 'luxury.waiter.ready-notices.v1.$userId';
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        _noticePreferences = prefs;
        _readReadyLines.value =
            (prefs.getStringList(_noticePreferencesKey!) ?? const []).toSet();
      } on Exception {
        // If browser storage is unavailable, keep receipts in this session.
      }
    }
    if (mounted) setState(() => _readyNoticesLoaded = true);
  }

  void _saveReadReadyLines(Set<String> lines) {
    final prefs = _noticePreferences;
    final key = _noticePreferencesKey;
    if (prefs == null || key == null) return;
    _noticeWrite = _noticeWrite.then((_) async {
      try {
        await prefs.setStringList(key, lines.toList());
      } on Exception {
        // The new value is already reflected in the active session.
      }
    });
  }

  void _acknowledgeReadyOrder(_ReadyOrderNotice notice) {
    final visibleKeys = {
      for (final current in _readyOrders(includeRead: true))
        for (final line in current.lines) line.key,
    };
    final updated = {
      ..._readReadyLines.value.where(visibleKeys.contains),
      for (final line in notice.lines) line.key,
    };
    setState(() => _readReadyLines.value = updated);
    _saveReadReadyLines(updated);
  }

  Future<void> _resetDemo(BuildContext context) async {
    final confirmed = await showLuxuryDialog<bool>(
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
    if (confirmed == true && context.mounted) {
      try {
        await showBlockingProgress(
          context,
          label: 'Reiniciando demostración…',
          action: () async {
            await store.resetDemo();
            if (mounted) {
              setState(() => _readReadyLines.value = <String>{});
              _saveReadReadyLines(<String>{});
            }
          },
        );
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

  Future<void> _refreshInformation() => runOperation(() async {
    await store.refresh();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Información actualizada.')));
    }
  }, label: 'Actualizando información…');

  Future<void> _syncPendingOrders() => runOperation(() async {
    await store.syncPendingOrders();
    if (mounted && store.pendingOrderCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedidos pendientes sincronizados.')),
      );
    }
  }, label: 'Sincronizando pedidos…');

  List<_ReadyOrderNotice> _readyOrders({bool includeRead = false}) {
    if (!_readyNoticesLoaded) return const [];
    final result = <_ReadyOrderNotice>[];
    for (final order in store.orders) {
      if ((!store.isDemo && order.waiterId != store.userId) ||
          order.pendingSync ||
          order.retirementConfirmed ||
          order.status == OrderStatus.cancelled) {
        continue;
      }
      final lines = <_ReadyLineNotice>[];
      for (final (index, line) in order.lines.indexed) {
        if (line.status != OrderStatus.ready || store.isWaiterService(line)) {
          continue;
        }
        final identity = line.id == null
            ? 'local-$index-${line.menuItemId}'
            : 'item-${line.id}';
        final key = '${order.id}/$identity/${line.quantity}';
        if (includeRead || !_readReadyLines.value.contains(key)) {
          lines.add((key: key, line: line));
        }
      }
      if (lines.isNotEmpty) result.add((order: order, lines: lines));
    }
    return result;
  }

  Future<void> _showReadyOrders() => showLuxuryDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([store, _readReadyLines]),
      builder: (context, _) {
        final orders = _readyOrders();
        return AlertDialog(
          scrollable: true,
          title: const Text('Platos listos para servir'),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (orders.isEmpty)
                  const Text('No hay avisos nuevos.')
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Pulsa un aviso para marcarlo como recibido.'),
                  ),
                for (final (index, notice) in orders.indexed)
                  LuxuryReveal(
                    key: ValueKey(notice.order.id),
                    index: index,
                    child: ListTile(
                      leading: const Icon(
                        Icons.room_service_outlined,
                        color: luxuryGold,
                      ),
                      onTap: () => _acknowledgeReadyOrder(notice),
                      title: Text(
                        '${notice.order.locationLabel} · #${notice.order.id}',
                      ),
                      subtitle: Text(
                        notice.lines
                            .map(
                              (entry) =>
                                  '${entry.line.quantity}× ${entry.line.name}',
                            )
                            .join(', '),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    ),
  );

  Widget _headerControls(StaffRole role) {
    final photoPath = store.currentStaffMember?.photoPath ?? '';
    final photoUrl = store.profilePhotoUrl(photoPath);
    final readyCount = role == StaffRole.waiter ? _readyOrders().length : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (role == StaffRole.waiter)
          IconButton(
            tooltip: 'Platos listos para servir ($readyCount)',
            onPressed: _showReadyOrders,
            icon: AnimatedSwitcher(
              duration: luxuryDuration(context, 240),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Badge(
                key: ValueKey(readyCount),
                isLabelVisible: readyCount > 0,
                backgroundColor: luxuryPaletteRed,
                label: Text('$readyCount'),
                child: Icon(
                  readyCount > 0
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_rounded,
                ),
              ),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Cuenta de ${store.displayName}',
          position: PopupMenuPosition.under,
          popUpAnimationStyle: luxuryOverlayMotion(context),
          offset: const Offset(0, 8),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 272, maxWidth: 320),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFEFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE7DED0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: luxuryPaletteOrange.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: photoUrl.isEmpty
                        ? const Icon(
                            Icons.person_outline_rounded,
                            color: luxuryPaletteDark,
                            size: 18,
                          )
                        : Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.person_outline_rounded,
                              color: luxuryPaletteDark,
                              size: 18,
                            ),
                          ),
                  ),
                ),
                if (MediaQuery.sizeOf(context).width > 900) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: luxuryPaletteDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          role.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: luxuryMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: luxuryPaletteDark,
                  size: 19,
                ),
              ],
            ),
          ),
          onSelected: (value) {
            if (value == 'logout') {
              unawaited(runOperation(store.signOut, showProgress: false));
            }
            if (value == 'reset') unawaited(_resetDemo(context));
            if (value == 'profile') {
              unawaited(showOwnStaffProfile(context, store));
            }
            if (value == 'refresh') unawaited(_refreshInformation());
            if (value == 'sync') unawaited(_syncPendingOrders());
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              height: 82,
              padding: EdgeInsets.zero,
              enabled: false,
              value: 'account',
              child: _AccountMenuHeader(
                name: store.displayName,
                role: role.label,
                connected: store.isConnected,
              ),
            ),
            const PopupMenuDivider(height: 10),
            const PopupMenuItem(
              value: 'profile',
              height: 46,
              child: _AccountMenuEntry(
                icon: Icons.badge_outlined,
                label: 'Mi perfil',
              ),
            ),
            if (store.isDemo)
              const PopupMenuItem<String>(
                value: 'reset',
                height: 46,
                child: _AccountMenuEntry(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reiniciar demostración',
                ),
              ),
            if (store.isConnected)
              const PopupMenuItem<String>(
                value: 'refresh',
                height: 46,
                child: _AccountMenuEntry(
                  icon: Icons.sync_rounded,
                  label: 'Actualizar información',
                ),
              ),
            if (store.pendingOrderCount > 0)
              PopupMenuItem(
                value: 'sync',
                height: 46,
                child: _AccountMenuEntry(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Sincronizar pedidos (${store.pendingOrderCount})',
                ),
              ),
            const PopupMenuDivider(height: 10),
            const PopupMenuItem<String>(
              value: 'logout',
              height: 46,
              child: _AccountMenuEntry(
                icon: Icons.logout_rounded,
                label: 'Cerrar sesión',
                destructive: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = store.role!;
    final status = store.errorMessage;
    final theme = Theme.of(context);
    final workTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: luxuryPaletteOrange,
        onPrimary: luxuryPaletteDark,
        secondary: luxuryPaletteGold,
        onSecondary: luxuryPaletteDark,
        tertiary: luxuryPaletteGreen,
        error: luxuryPaletteRed,
        onError: Colors.white,
        surface: const Color(0xFFFFFEFB),
        onSurface: luxuryPaletteDark,
        outline: const Color(0xFFE7DED0),
        surfaceTint: Colors.transparent,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F4EE),
      textTheme: theme.textTheme.copyWith(
        headlineSmall: theme.textTheme.headlineSmall?.copyWith(
          color: luxuryPaletteDark,
          fontFamily: 'Georgia',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -.45,
        ),
        titleLarge: theme.textTheme.titleLarge?.copyWith(
          color: luxuryPaletteDark,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: luxuryPaletteDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 76,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: const Color(0xFFFFFEFB),
        elevation: 1,
        shadowColor: luxuryPaletteDark.withValues(alpha: .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFECE5DA)),
        ),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0xFFFFFEFB),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: luxuryPaletteOrange, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: luxuryPaletteOrange,
          foregroundColor: luxuryPaletteDark,
          minimumSize: const Size(44, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: luxuryPaletteDark,
          side: const BorderSide(color: Color(0xFFDDD2C1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(44, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: luxuryPaletteDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: luxuryPaletteDark,
        indicatorColor: luxuryPaletteOrange,
        selectedIconTheme: const IconThemeData(color: luxuryPaletteDark),
        unselectedIconTheme: IconThemeData(
          color: const Color(0xFFFFFCF7).withValues(alpha: .65),
        ),
        selectedLabelTextStyle: const TextStyle(
          color: Color(0xFFFFFCF7),
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: const Color(0xFFFFFCF7).withValues(alpha: .68),
        ),
        groupAlignment: -.78,
        minWidth: 82,
        minExtendedWidth: 232,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: luxuryPaletteDark,
        indicatorColor: luxuryPaletteOrange,
        elevation: 0,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? luxuryPaletteDark
                : const Color(0xFFFFFCF7).withValues(alpha: .72),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: const Color(0xFFFFFCF7).withValues(
              alpha: states.contains(WidgetState.selected) ? 1 : .72,
            ),
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        backgroundColor: const Color(0xFFF1EADF),
        selectedColor: luxuryPaletteGold.withValues(alpha: .22),
        labelStyle: const TextStyle(color: luxuryPaletteDark),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFFFFFEFB),
        elevation: 14,
        shadowColor: luxuryPaletteDark.withValues(alpha: .2),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE7DED0)),
        ),
        menuPadding: const EdgeInsets.all(8),
        textStyle: const TextStyle(
          color: luxuryPaletteDark,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE7DED0),
        thickness: 1,
        space: 1,
      ),
    );
    return Theme(
      data: workTheme,
      child: PinnedHeaderActions(
        controls: (_) => _headerControls(role),
        fallbackTitle: role.label,
        child: Scaffold(
          body: Column(
            children: [
              if (status != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: ErrorBanner(message: status),
                ),
              Expanded(
                child: switch (role) {
                  StaffRole.administrator => AdminScreen(store: store),
                  StaffRole.manager => AdminScreen(
                    store: store,
                    managerOnly: true,
                  ),
                  StaffRole.kitchen ||
                  StaffRole.headChef => KitchenScreen(store: store),
                  StaffRole.waiter => WaiterScreen(store: store),
                  StaffRole.cashier => CashierScreen(store: store),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountMenuHeader extends StatelessWidget {
  const _AccountMenuHeader({
    required this.name,
    required this.role,
    required this.connected,
  });

  final String name;
  final String role;
  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: luxuryPaletteDark,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: luxuryPaletteOrange.withValues(alpha: .18),
            shape: BoxShape.circle,
            border: Border.all(color: luxuryPaletteGold.withValues(alpha: .3)),
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            color: luxuryPaletteGold,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFFCF7),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFD4C8B6), fontSize: 11),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: connected ? luxuryPaletteGreen : luxuryPaletteGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    connected ? 'Conectado' : 'Modo demostración',
                    style: const TextStyle(
                      color: Color(0xFFD4C8B6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AccountMenuEntry extends StatelessWidget {
  const _AccountMenuEntry({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? luxuryPaletteRed : luxuryPaletteDark;
    final iconColor = destructive ? luxuryPaletteRed : luxuryPaletteOrange;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: destructive ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
