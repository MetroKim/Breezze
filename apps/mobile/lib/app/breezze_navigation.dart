import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:material_ui/material_ui.dart';

/// Breezze navigation policy.
///
/// Product tabs remain the same four destinations on every device. Details
/// preserve iOS edge-swipe navigation and native modal presentation on Apple
/// devices without forcing a Cupertino visual theme on other platforms.
/// When the OS asks for reduced animation, the same routes stay accessible
/// with a zero-duration transition instead of a decorative page slide.
Route<T> breezzePageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
  RouteSettings? settings,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (routeContext, animation, secondary) =>
          builder(routeContext),
    );
  }

  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return CupertinoPageRoute<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      builder: builder,
    );
  }

  return MaterialPageRoute<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    builder: builder,
  );
}
