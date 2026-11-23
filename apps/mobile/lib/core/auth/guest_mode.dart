import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Guest access is local to this app session; it is not a Breezze account.
final guestModeProvider = StateProvider<bool>((ref) => false);
