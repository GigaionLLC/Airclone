import 'dart:io';

/// Whether the primary pointer is a finger (phone/tablet) rather than a mouse.
/// Touch-first surfaces open files with a single tap and use long-press where
/// desktop uses right-click; selection happens through the long-press menu.
final bool isTouchPrimary = Platform.isAndroid || Platform.isIOS;
