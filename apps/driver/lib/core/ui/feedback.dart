import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_exception.dart';

final _currency = NumberFormat.simpleCurrency(locale: 'en_US');

String formatMoney(double value) => _currency.format(value);

/// Lee montos que el backend envía como texto ("14.5") o número.
double parseMoney(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
      ApiException.from(error).message,
      style: TextStyle(color: Theme.of(context).colorScheme.onError, fontWeight: FontWeight.w600),
    ),
    backgroundColor: Theme.of(context).colorScheme.error,
  ));
}

void showSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Eliminar',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
