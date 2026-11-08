import 'package:flutter/material.dart';

import 'models.dart';

const luxuryBrown = Color(0xFF2A0F0D);
const luxuryGold = Color(0xFFE48424);
const luxuryRed = Color(0xFFC81D25);
const luxuryGreen = Color(0xFF7FB519);
const luxuryBone = Color(0xFFF5F0EB);
const luxuryInk = Color(0xFF1D1E23);
const luxuryMuted = Color(0xFF77716D);
const luxuryBorder = Color(0xFFE9E1DA);

String money(num value) => 'S/ ${value.toStringAsFixed(2)}';

Color statusColor(String status) => switch (status) {
  'DISPONIBLE' || 'LISTO' || 'PAGADO' || 'ATENDIDO' => luxuryGreen,
  'POR_COBRAR' || 'CANCELADO' => luxuryRed,
  _ => luxuryGold,
};

Color orderColor(OrderStatus status) => statusColor(status.databaseValue);

Future<void> showResultDialog(
  BuildContext context, {
  required String message,
  required bool success,
  String? title,
  String actionLabel = 'Continuar',
}) => showDialog<void>(
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
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (success ? luxuryGreen : luxuryRed).withValues(alpha: .14),
            ),
            child: Icon(
              success ? Icons.check_rounded : Icons.priority_high_rounded,
              color: success ? luxuryGreen : luxuryRed,
              size: 42,
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          color: color,
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
  Widget build(BuildContext context) => Padding(
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
                color: luxuryGold,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
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
        if (trailing == null) return heading;
        if (constraints.maxWidth < 760 && trailing is! IconButton) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 14), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .5),
              child: trailing!,
            ),
          ],
        );
      },
    ),
  );
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
          for (final child in children) SizedBox(width: width, child: child),
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
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (color == luxuryBrown ? luxuryGold : color).withValues(
                alpha: .14,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color == luxuryBrown ? luxuryGold : color),
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
      color: const Color(0xFFFFE8E6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFF8D171D))),
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
