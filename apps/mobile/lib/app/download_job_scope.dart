/// Stable private-directory token for listener-specific download jobs.
/// Never use a plaintext user id or a global jobs.json across accounts.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

String downloadJobOwnerDirectory(String ownerId) {
  if (ownerId.trim().isEmpty) {
    throw ArgumentError.value(ownerId, 'ownerId', 'required for private jobs');
  }
  return 'account-${sha256.convert(utf8.encode(ownerId))}';
}
