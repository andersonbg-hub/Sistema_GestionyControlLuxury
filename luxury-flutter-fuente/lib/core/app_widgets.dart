import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'app_colors.dart';
import 'luxury_motion.dart';

export 'app_colors.dart';
export 'luxury_motion.dart';

class LuxuryMenuEntry {
  const LuxuryMenuEntry({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class LuxurySideMenu extends StatelessWidget {
  const LuxurySideMenu({
    super.key,
    required this.entries,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.sectionBreakIndices = const {},
    this.showBrand = true,
  });

  final List<LuxuryMenuEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Set<int> sectionBreakIndices;
  final bool showBrand;

  static const _background = Color(0xFF382217);
  static const _headerBackground = Color(0xFF2D1A11);
  static const _mutedText = Color(0xFFE4C9B0);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Material(
      color: _background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBrand)
            Container(
              height: 84,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: _headerBackground,
                border: Border(bottom: BorderSide(color: Color(0xFF65402B))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF130D09),
                      shape: BoxShape.circle,
                      border: Border.all(color: luxuryGold, width: 2),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/portada_restaurante.webp',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.restaurant_menu,
                              color: luxuryGold,
                              size: 26,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LUXURY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'RESTAURANTE ORIENTAL',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFFF2A447),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (showBrand)
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 16, 16, 8),
              child: Text(
                'MENÚ PRINCIPAL',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          if (!showBrand) const SizedBox.shrink(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = selectedIndex == index;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sectionBreakIndices.contains(index))
                      const Padding(
                        padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: Divider(color: Color(0xFF65402B), height: 1),
                      ),
                    Semantics(
                      button: true,
                      selected: selected,
                      child: InkWell(
                        key: ValueKey('luxury-side-menu-$index'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onDestinationSelected(index),
                        child: AnimatedContainer(
                          duration: luxuryDuration(context, 200),
                          curve: Curves.easeOutCubic,
                          height: 48,
                          decoration: BoxDecoration(
                            color: selected
                                ? luxuryPaletteOrange.withValues(alpha: .16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? luxuryPaletteGold.withValues(alpha: .35)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: selected ? 17 : 11,
                              right: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  entry.icon,
                                  size: 18,
                                  color: selected
                                      ? const Color(0xFFFFC46B)
                                      : _mutedText,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    entry.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: selected ? 1 : .9,
                                      ),
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

String money(num value) => 'S/ ${value.toStringAsFixed(2)}';

String searchText(String value) {
  final lower = value.toLowerCase().trim();
  const accents = 'áéíóúü';
  const base = 'aeiouu';
  return lower.replaceAllMapped(
    RegExp('[$accents]'),
    (match) => base[accents.indexOf(match[0]!)],
  );
}

String shortDate(DateTime day) =>
    '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';

String limaDateTime(DateTime instant) {
  final time = limaWallTime(instant);
  final hours = time.hour.toString().padLeft(2, '0');
  final minutes = time.minute.toString().padLeft(2, '0');
  return '${shortDate(time)}/${time.year} · $hours:$minutes';
}

bool inBusinessRange(DateTime instant, DateTimeRange? range) {
  if (range == null) return true;
  final day = limaBusinessDay(instant);
  final start = DateTime.utc(
    range.start.year,
    range.start.month,
    range.start.day,
  );
  final end = DateTime.utc(range.end.year, range.end.month, range.end.day);
  return !day.isBefore(start) && !day.isAfter(end);
}

class HistoryDateFilter extends StatelessWidget {
  const HistoryDateFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.presets = false,
  });

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final bool presets;

  @override
  Widget build(BuildContext context) {
    final day = limaBusinessDay(DateTime.now());
    final today = DateTime(day.year, day.month, day.day);
    final current = value;
    final days = current == null || current.end != today
        ? 0
        : DateTime.utc(day.year, day.month, day.day)
                  .difference(
                    DateTime.utc(
                      current.start.year,
                      current.start.month,
                      current.start.day,
                    ),
                  )
                  .inDays +
              1;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (presets)
          for (final (count, label) in [
            (1, 'Hoy'),
            (3, 'Últimos 3 días'),
            (7, 'Últimos 7 días'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: days == count,
              onSelected: (selected) => onChanged(
                selected
                    ? DateTimeRange(
                        start: DateTime(
                          today.year,
                          today.month,
                          today.day - count + 1,
                        ),
                        end: today,
                      )
                    : null,
              ),
            ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined),
          label: AnimatedSwitcher(
            duration: luxuryDuration(context, 220),
            child: Text(
              current == null
                  ? 'Rango de fechas'
                  : '${shortDate(current.start)} – ${shortDate(current.end)}',
              key: ValueKey((current?.start, current?.end)),
            ),
          ),
          onPressed: () async {
            final result = await showLuxuryDialog<DateTimeRange>(
              context: context,
              builder: (context) =>
                  _HistoryRangeDialog(today: today, initial: current),
            );
            if (context.mounted && result != null) onChanged(result);
          },
        ),
        if (current != null)
          IconButton(
            tooltip: 'Restablecer fechas',
            icon: const Icon(Icons.clear),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}

class _HistoryRangeDialog extends StatefulWidget {
  const _HistoryRangeDialog({required this.today, required this.initial});

  final DateTime today;
  final DateTimeRange? initial;

  @override
  State<_HistoryRangeDialog> createState() => _HistoryRangeDialogState();
}

class _HistoryRangeDialogState extends State<_HistoryRangeDialog> {
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  late DateTime month;
  DateTime? start;
  DateTime? end;

  @override
  void initState() {
    super.initState();
    start = widget.initial?.start;
    end = widget.initial?.end;
    final first = start ?? widget.today;
    month = DateTime(first.year, first.month);
  }

  void _select(DateTime date) => setState(() {
    final first = start;
    if (first == null || end != null) {
      start = date;
      end = null;
    } else if (date.isBefore(first)) {
      start = date;
      end = first;
    } else {
      end = date;
    }
  });

  @override
  Widget build(BuildContext context) {
    final monthTitle = '${months[month.month - 1]} ${month.year}';
    final canGoBack = month.isAfter(DateTime(2000));
    final canGoNext = month.isBefore(
      DateTime(widget.today.year, widget.today.month),
    );
    return AlertDialog(
      scrollable: true,
      title: const Text('Rango de fechas'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _endpoint('Desde', start)),
                const SizedBox(width: 8),
                Expanded(child: _endpoint('Hasta', end)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              start == null
                  ? 'Selecciona el inicio del rango.'
                  : end == null
                  ? 'Selecciona el final o aplica un solo día.'
                  : 'El rango incluye ambas fechas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: canGoBack
                      ? () => setState(
                          () => month = DateTime(month.year, month.month - 1),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    monthTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: canGoNext
                      ? () => setState(
                          () => month = DateTime(month.year, month.month + 1),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'])
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: luxuryDuration(context, 200),
              child: Column(
                key: ValueKey(month),
                children: [
                  for (var week = 0; week < 6; week++)
                    Row(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Expanded(
                            child: _day(week * 7 + weekday - month.weekday + 2),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: start == null
              ? null
              : () => Navigator.pop(
                  context,
                  DateTimeRange(start: start!, end: end ?? start!),
                ),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }

  Widget _endpoint(String label, DateTime? date) => AnimatedContainer(
    duration: luxuryDuration(context, 200),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: date == null ? luxuryBone : luxuryGold.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: date == null ? luxuryBorder : luxuryGold.withValues(alpha: .45),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(
          date == null ? 'Sin elegir' : '${shortDate(date)}/${date.year}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    ),
  );

  Widget _day(int number) {
    final date = DateTime(month.year, month.month, number);
    if (date.month != month.month) return const SizedBox(height: 40);
    final selected = date == start || date == end;
    final inRange =
        start != null &&
        end != null &&
        date.isAfter(start!) &&
        date.isBefore(end!);
    final enabled = !date.isAfter(widget.today);
    return Semantics(
      selected: selected || inRange,
      label: '$number de ${months[month.month - 1]} de ${month.year}',
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: TextButton(
            onPressed: enabled ? () => _select(date) : null,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: selected
                  ? luxuryPaletteGold
                  : inRange
                  ? luxuryGold.withValues(alpha: .15)
                  : null,
              foregroundColor: luxuryPaletteDark,
              side: date == widget.today && !selected
                  ? BorderSide(color: luxuryPaletteGold.withValues(alpha: .7))
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Text('$number'),
          ),
        ),
      ),
    );
  }
}

String formatErrorMessage(Object? error) {
  if (error == null) return '';
  if (error is TimeoutException ||
      error is ClientException ||
      error is AuthRetryableFetchException) {
    return 'La conexión no respondió a tiempo. Revisa la red y vuelve a intentarlo.';
  }
  if (error is FunctionException) {
    final details = error.details;
    final detail = details is Map ? details['error'] : null;
    if (detail is String && detail.trim().isNotEmpty) return detail;
    if (error.status == 404) {
      return 'Falta publicar la función de cuentas en Supabase.';
    }
    if (error.status == 401) {
      return 'Vuelve a iniciar sesión para continuar.';
    }
    if (error.status == 0) {
      return 'No se pudo conectar con el servicio de cuentas.';
    }
  }
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    final code = error.code?.toLowerCase() ?? '';
    if (code == 'invalid_credentials' ||
        msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (code == 'email_not_confirmed' || msg.contains('email not confirmed')) {
      return 'El correo no ha sido confirmado. Revisa tu bandeja de entrada.';
    }
    if (code == 'user_not_found' || msg.contains('user not found')) {
      return 'No existe una cuenta registrada con este correo.';
    }
    if (code == 'over_request_rate_limit' ||
        error.statusCode == '429' ||
        msg.contains('rate limit')) {
      return 'Demasiados intentos fallidos. Inténtalo de nuevo en unos minutos.';
    }
    if (code == 'same_password' || msg.contains('same password')) {
      return 'La nueva contraseña no puede ser igual a la anterior.';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message;
    }
  }
  if (error is PostgrestException) {
    if ((error.code == 'PGRST204' || error.code == '42703') &&
        error.message.contains('imagen_url')) {
      return 'Supabase todavía requiere la migración para guardar imágenes por URL.';
    }
    if (error.code == 'PGRST116') {
      return 'No se encontró el registro solicitado o no tienes permiso.';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message;
    }
  }
  if (error is StateError) {
    return error.message;
  }
  final str = error.toString();
  if (str.contains('invalid_credentials') ||
      str.contains('Invalid login credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (str.contains('Email not confirmed') ||
      str.contains('email_not_confirmed')) {
    return 'El correo no ha sido confirmado. Revisa tu bandeja de entrada.';
  }
  if (str.startsWith('Exception: ')) {
    return str.substring(11);
  }
  if (str.startsWith('StateError: ')) {
    return str.substring(12);
  }
  final match = RegExp(r'message:\s*([^,]+)').firstMatch(str);
  if (match != null) {
    final extracted = match.group(1)?.trim();
    if (extracted != null && extracted.isNotEmpty) {
      if (extracted.toLowerCase().contains('invalid login credentials')) {
        return 'Correo o contraseña incorrectos.';
      }
      return extracted;
    }
  }
  return str;
}

Color statusColor(String status) => switch (status) {
  'DISPONIBLE' || 'LISTO' || 'PAGADO' || 'ATENDIDO' => luxuryPaletteGreen,
  'POR_COBRAR' || 'CANCELADO' => luxuryPaletteRed,
  _ => luxuryPaletteOrange,
};

Color orderColor(OrderStatus status) => statusColor(status.databaseValue);

Future<void> showResultDialog(
  BuildContext context, {
  required String message,
  required bool success,
  String? title,
  String actionLabel = 'Continuar',
}) => showLuxuryDialog<void>(
  context: context,
  barrierColor: const Color(0xB317181D),
  builder: (context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33404B48),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            duration: luxuryDuration(context, 400),
            tween: Tween(begin: .72, end: 1),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (success ? luxuryGreen : luxuryRed).withValues(
                  alpha: .14,
                ),
              ),
              child: Icon(
                success ? Icons.check_rounded : Icons.priority_high_rounded,
                color: success ? luxuryGreen : luxuryRed,
                size: 42,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title ?? (success ? '¡Listo!' : 'No se pudo completar'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              height: 1.45,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: success ? luxuryGreen : luxuryRed,
              side: BorderSide(
                color: (success ? luxuryGreen : luxuryRed).withValues(
                  alpha: .55,
                ),
              ),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  ),
);

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) async {
  return await showLuxuryDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;
}

class OperationLabel extends StatelessWidget {
  const OperationLabel({super.key, required this.label, this.loading = false});

  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) return Text(label);
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              color: DefaultTextStyle.of(context).style.color,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

Future<T> showBlockingProgress<T>(
  BuildContext context, {
  required String label,
  required Future<T> Function() action,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    requestFocus: true,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    builder: (context) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 368),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('Espera un momento.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(
                    color: luxuryGold,
                    backgroundColor: Color(0xFFF0E2D3),
                    minHeight: 5,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await action();
  } finally {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }
}

mixin OperationProgress<T extends StatefulWidget> on State<T> {
  bool _operationPending = false;
  bool get operationPending => _operationPending;

  Future<bool> runOperation(
    Future<void> Function() action, {
    String label = 'Procesando…',
    bool showProgress = true,
  }) async {
    if (operationPending || !mounted) return false;
    _operationPending = true;
    try {
      await (showProgress
          ? showBlockingProgress(context, label: label, action: action)
          : action());
      return true;
    } catch (error) {
      if (mounted) {
        await showResultDialog(
          context,
          success: false,
          message: formatErrorMessage(error),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }
}

class SectionTransition extends StatelessWidget {
  const SectionTransition({
    super.key,
    required this.section,
    required this.child,
  });

  final Object section;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LuxuryReveal(key: ValueKey(section), section: true, child: child);
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  factory StatusBadge.order(OrderStatus status) =>
      StatusBadge(label: status.label, color: orderColor(status));

  factory StatusBadge.table(TableStatus status) => StatusBadge(
    label: status.label,
    color: statusColor(status.databaseValue),
  );

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: luxuryDuration(context, 200),
    curve: Curves.easeOutCubic,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          color: color == luxuryPaletteGreen ? luxuryPaletteGreenText : color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pinned = PinnedHeaderScope.maybeOf(context);
    if (pinned == null) return _inline(context);
    // Con encabezado fijo, el título se muestra allí y no dentro del scroll.
    return _PinnedTitle(
      notifier: pinned,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    );
  }

  Widget _inline(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 34,
              margin: const EdgeInsets.only(top: 3, right: 12),
              decoration: BoxDecoration(
                color: luxuryPaletteGold,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'Georgia',
                      fontSize: 26,
                      letterSpacing: -.45,
                    ),
                  ),
                  if (subtitle case final value?) ...[
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: luxuryMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        final actions = trailing;
        if (actions == null) return heading;
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    ),
  );
}

/// Datos del título de sección que se muestran en el encabezado fijo.
class PinnedHeaderData {
  const PinnedHeaderData({
    required this.owner,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final Object owner;
  final String title;
  final String? subtitle;
  final Widget? trailing;
}

class PinnedHeaderScope extends InheritedWidget {
  const PinnedHeaderScope({
    super.key,
    required this.notifier,
    required super.child,
  });

  final ValueNotifier<PinnedHeaderData?> notifier;

  static ValueNotifier<PinnedHeaderData?>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PinnedHeaderScope>()?.notifier;

  @override
  bool updateShouldNotify(PinnedHeaderScope oldWidget) =>
      notifier != oldWidget.notifier;
}

/// Controles de cuenta (campana, menú de cuenta…) que el encabezado fijo
/// muestra a la derecha. Los provee la pantalla de trabajo de cada rol.
class PinnedHeaderActions extends InheritedWidget {
  const PinnedHeaderActions({
    super.key,
    required this.controls,
    required this.fallbackTitle,
    required super.child,
  });

  final Widget Function(BuildContext context) controls;
  final String fallbackTitle;

  static PinnedHeaderActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PinnedHeaderActions>();

  @override
  bool updateShouldNotify(PinnedHeaderActions oldWidget) => true;
}

/// Encabezado estático: queda fuera del scroll, en el lugar del título de cada
/// sección, y reúne el título, las acciones de la sección y las de la cuenta.
/// Sin [PinnedHeaderActions] arriba (por ejemplo en pruebas) no hace nada y los
/// títulos se muestran en línea como antes.
class PinnedHeaderHost extends StatefulWidget {
  const PinnedHeaderHost({
    super.key,
    required this.child,
    this.section,
    this.horizontalPadding = 20,
    this.maxWidth,
  });

  final Widget child;

  /// Cambia al navegar a otra sección para limpiar el título anterior.
  final Object? section;
  final double horizontalPadding;
  final double? maxWidth;

  @override
  State<PinnedHeaderHost> createState() => _PinnedHeaderHostState();
}

class _PinnedHeaderHostState extends State<PinnedHeaderHost> {
  // Se publica en el siguiente cuadro; no se desecha para que esas
  // publicaciones tardías nunca lleguen a un notificador ya liberado.
  final _notifier = ValueNotifier<PinnedHeaderData?>(null);

  @override
  void didUpdateWidget(PinnedHeaderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section) {
      // Se registra antes que el título de la nueva sección, que publica después.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifier.value = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PinnedHeaderActions.maybeOf(context) == null) return widget.child;
    return PinnedHeaderScope(
      notifier: _notifier,
      child: Column(
        children: [
          _PinnedHeaderBar(
            notifier: _notifier,
            horizontalPadding: widget.horizontalPadding,
            maxWidth: widget.maxWidth,
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _PinnedTitle extends StatefulWidget {
  const _PinnedTitle({
    required this.notifier,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final ValueNotifier<PinnedHeaderData?> notifier;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  State<_PinnedTitle> createState() => _PinnedTitleState();
}

class _PinnedTitleState extends State<_PinnedTitle> {
  final _owner = Object();

  void _publish() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.notifier.value = PinnedHeaderData(
        owner: _owner,
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: widget.trailing,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _publish();
  }

  @override
  void didUpdateWidget(_PinnedTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publish();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PinnedHeaderBar extends StatelessWidget {
  const _PinnedHeaderBar({
    required this.notifier,
    required this.horizontalPadding,
    this.maxWidth,
  });

  final ValueNotifier<PinnedHeaderData?> notifier;
  final double horizontalPadding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final actions = PinnedHeaderActions.maybeOf(context);
    if (actions == null) return const SizedBox.shrink();
    return ValueListenableBuilder<PinnedHeaderData?>(
      valueListenable: notifier,
      builder: (context, data, _) {
        final narrow = MediaQuery.sizeOf(context).width < 760;
        final title = data?.title ?? actions.fallbackTitle;
        final subtitle = data?.subtitle;
        final trailing = data?.trailing;
        final heading = Row(
          children: [
            Container(
              width: 4,
              height: subtitle == null ? 28 : 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: luxuryPaletteGold,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'Georgia',
                      fontSize: narrow ? 21 : 26,
                      letterSpacing: -.45,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: luxuryMuted),
                    ),
                ],
              ),
            ),
          ],
        );
        final controls = actions.controls(context);
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFFFFEFB),
            border: Border(bottom: BorderSide(color: Color(0xFFE7DED0))),
          ),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            10,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? double.infinity,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 3, child: heading),
                      if (!narrow && trailing != null) ...[
                        const SizedBox(width: 16),
                        Flexible(
                          flex: 4,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: trailing,
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                      controls,
                    ],
                  ),
                  if (narrow && trailing != null) ...[
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Gives record details their own row before the actions on smaller screens.
class ResponsiveListTile extends StatelessWidget {
  const ResponsiveListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.dense = false,
    this.isThreeLine = false,
    this.contentPadding,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool dense;
  final bool isThreeLine;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 760 || trailing == null) {
        return ListTile(
          title: title,
          subtitle: subtitle,
          leading: leading,
          trailing: trailing == null
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .5,
                  ),
                  child: trailing,
                ),
          dense: dense,
          isThreeLine: isThreeLine,
          contentPadding: contentPadding,
          onTap: onTap,
        );
      }
      final theme = Theme.of(context).textTheme;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: contentPadding ?? EdgeInsets.all(dense ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: theme.titleMedium!,
                          child: title,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          DefaultTextStyle(
                            style: theme.bodyMedium!.copyWith(
                              color: Colors.black54,
                            ),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DefaultTextStyle(style: theme.bodyMedium!, child: trailing!),
            ],
          ),
        ),
      );
    },
  );
}

/// Natural card heights keep statistics readable with enlarged text as well.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.maxColumns = 4});
  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.maxWidth + 12) / 272).floor().clamp(
        1,
        maxColumns,
      );
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (index, child) in children.indexed)
            SizedBox(
              width: width,
              child: LuxuryReveal(index: index, hover: true, child: child),
            ),
        ],
      );
    },
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = luxuryBrown,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (color == luxuryBrown ? luxuryPaletteOrange : color)
                  .withValues(alpha: .14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: color == luxuryBrown ? luxuryPaletteOrange : color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (caption != null)
                  Text(caption!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class CatalogThumbnail extends StatelessWidget {
  const CatalogThumbnail({
    super.key,
    required this.url,
    required this.icon,
    this.color = luxuryBrown,
  });

  final String url;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(icon, color: color);
    return SizedBox.square(
      dimension: 42,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: ColoredBox(
          color: color.withValues(alpha: .10),
          child: url.isEmpty
              ? fallback
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Colors.black38),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: luxuryPaletteRed.withValues(alpha: .08),
      border: Border.all(color: luxuryPaletteRed.withValues(alpha: .18)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(color: luxuryPaletteRed)),
  );
}

class LoginFieldError extends StatelessWidget {
  const LoginFieldError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 7),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      border: Border.all(color: const Color(0xFFFFD6DC)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: Color(0xFFCF334B),
        fontSize: 12,
        height: 1.35,
      ),
    ),
  );
}
