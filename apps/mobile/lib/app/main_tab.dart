/// Stable internal tab identities; the old `browse` identifier is retained
/// for state/persistence compatibility while the visible product label is New.
enum MainTab { home, browse, library, search }

/// V8 primary navigation: exactly four destinations, same order everywhere.
const List<String> breezzeMainTabLabels = <String>[
  'Home',
  'New',
  'Library',
  'Search',
];
