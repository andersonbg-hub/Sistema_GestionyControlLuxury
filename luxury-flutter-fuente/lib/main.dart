import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_widgets.dart';
import 'data/restaurant_store.dart';
import 'data/supabase_http_client.dart';
import 'models/models.dart';
import 'views/admin/dashboard_screen.dart';
import 'views/password_change_screen.dart';
import 'views/cashier/cashier_screen.dart';
import 'views/kitchen/kitchen_screen.dart';
import 'views/login_screen.dart';
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 460,
        insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        backgroundColor: const Color(0xFF382F29),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
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
      if (store.role == null) return LoginScreen(store: store);
      if (store.mustChangePassword) {
        return PasswordChangeScreen(store: store, requiredChange: true);
      }
      return _WorkScreen(store: store);
    },
  );
}

typedef _ReadyOrderNotice = ({RestaurantOrder order, List<OrderLine> lines});

class _WorkScreen extends StatefulWidget {
  const _WorkScreen({required this.store});
  final RestaurantStore store;

  @override
  State<_WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<_WorkScreen>
    with OperationProgress<_WorkScreen> {
  RestaurantStore get store => widget.store;
  Future<void> _acknowledgeReadyOrder(_ReadyOrderNotice notice) async {
    await runOperation(
      () => store.advanceOrder(
        notice.order.copyWith(lines: notice.lines),
        forStage: OrderStatus.ready,
      ),
      label: 'Confirmando recepción…',
    );
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
          action: store.resetDemo,
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

  List<_ReadyOrderNotice> _readyOrders() {
    final result = <_ReadyOrderNotice>[];
    for (final order in store.orders) {
      if ((!store.isDemo && order.waiterId != store.userId) ||
          order.pendingSync ||
          order.retirementConfirmed ||
          order.status == OrderStatus.cancelled) {
        continue;
      }
      final lines = [
        for (final line in order.lines)
          if (line.status == OrderStatus.ready && !store.isWaiterService(line))
            line,
      ];
      if (lines.isNotEmpty) result.add((order: order, lines: lines));
    }
    return result;
  }

  Future<void> _showReadyOrders() => showLuxuryDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: store,
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
                    child: Text(
                      'Pulsa un aviso para confirmar que recibiste esos platos.',
                    ),
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
                            .map((line) => '${line.quantity}× ${line.name}')
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
