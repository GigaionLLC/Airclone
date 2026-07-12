import 'package:airclone/src/state/browser_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// `activeIsConsole` is load-bearing for the phone shell: a console tab has an
/// empty browser state (`remote == null`), so the "is this pane showing content"
/// predicates gate on it too — otherwise opening a console bounces back to the
/// locations list.
void main() {
  group('BrowserState.activeIsConsole', () {
    test('true when the active tab is a console', () {
      const s = BrowserState(
        tabs: [
          TabInfo(label: 'Home'),
          TabInfo(label: 'Console', kind: PaneKind.console, consoleId: 'c0'),
        ],
        activeTab: 1,
      );
      expect(s.activeIsConsole, isTrue);
    });

    test('false when the active tab is a browser', () {
      const s = BrowserState(
        tabs: [
          TabInfo(label: 'Home'),
          TabInfo(label: 'Console', kind: PaneKind.console),
        ],
        activeTab: 0,
      );
      expect(s.activeIsConsole, isFalse);
    });

    test('false for the default (no-tabs) state and an out-of-range index', () {
      expect(const BrowserState().activeIsConsole, isFalse);
      const oob = BrowserState(tabs: [TabInfo(label: 'x')], activeTab: 5);
      expect(oob.activeIsConsole, isFalse);
    });
  });
}
