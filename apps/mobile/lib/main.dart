import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'widgets/bz_shell.dart';

void main() {
  runApp(const BreezzeShell());
}

/// Kept for API parity; the shell owns the MaterialApp.
class BreezzeApp extends StatelessWidget {
  const BreezzeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const BreezzeShell();
  }
}
