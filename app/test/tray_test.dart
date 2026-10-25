/// The desktop tray (#54): the tooltip text, its throttle, the close decision,
/// the persisted close-to-tray choice, and the tray menu.
library;

import 'package:airclone/src/state/close_to_tray.dart';
import 'package:airclone/src/state/tray_controller.dart';
import 'package:airclone/src/state/tray_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  group('trayStatusLine', () {
    test('idle', () {
      expect(trayStatusLine(const TrayActivity()), 'Idle');
    });

    test('engine starting wins over everything else', () {
      expect(
        trayStatusLine(const TrayActivity(engineReady: false, transferring: 3)),
        'Engine starting',
      );
    });

    test('one file, speed and ETA', () {
      expect(
        trayStatusLine(
          const TrayActivity(transferring: 1, speed: 1677722, eta: 125),
        ),
        'Transferring 1 file, 1.6 MB/s, 3 min left',
      );
    });

    test('several files with no speed or estimate yet', () {
      expect(
        trayStatusLine(const TrayActivity(transferring: 4)),
        'Transferring 4 files',
      );
    });

    test('queue and limit follow after a dot', () {
      expect(
        trayStatusLine(
          const TrayActivity(queued: 2, queuePaused: true, bwLimit: '5M'),
        ),
        'Idle · 2 queued (paused) · Limit 5M/s',
      );
    });

    test('a paused empty queue still says so', () {
      expect(
        trayStatusLine(const TrayActivity(queuePaused: true)),
        'Idle · Queue paused',
      );
    });

    test('limit off is not mentioned', () {
      expect(trayStatusLine(const TrayActivity(bwLimit: 'off')), 'Idle');
    });

    test('isBusy counts running and queued work', () {
      expect(const TrayActivity().isBusy, isFalse);
      expect(const TrayActivity(transferring: 1).isBusy, isTrue);
      expect(const TrayActivity(queued: 1).isBusy, isTrue);
    });
  });

  group('trayTooltip and clipping', () {
    test('prefixes the app name', () {
      expect(trayTooltip(const TrayActivity()), 'Airclone – Idle');
    });

    test('never exceeds the Windows limit', () {
      const a = TrayActivity(
        transferring: 123456789,
        speed: 1e15,
        eta: 1e9,
        queued: 987654321,
        queuePaused: true,
        bwLimit: '123456789012345678901234567890M',
      );
      final t = trayTooltip(a);
      expect(t.length, lessThanOrEqualTo(kTrayTooltipMaxLength));
      expect(t, endsWith('…'));
    });

    test('clipTrayText leaves short text alone', () {
      expect(clipTrayText('abc', max: 3), 'abc');
      expect(clipTrayText('abcd', max: 3), 'ab…');
    });
  });

  group('formatEta', () {
    test('no estimate', () {
      expect(formatEta(null), isNull);
      expect(formatEta(0), isNull);
      expect(formatEta(-5), isNull);
      expect(formatEta(double.nan), isNull);
      expect(formatEta(double.infinity), isNull);
    });

    test('rounds up and picks a coarse unit', () {
      expect(formatEta(0.2), '1 s');
      expect(formatEta(45), '45 s');
      expect(formatEta(60), '1 min');
      expect(formatEta(61), '2 min');
      expect(formatEta(3600), '1 h');
      expect(formatEta(3 * 3600 + 100), '3 h');
      expect(formatEta(2 * 86400), '2 d');
    });
  });

  group('TrayTextThrottle', () {
    final t0 = DateTime(2026, 10, 25, 12);

    test('first text goes out, a repeat does not', () {
      final th = TrayTextThrottle();
      expect(th.offer('a', t0), isTrue);
      expect(th.offer('a', t0.add(const Duration(seconds: 10))), isFalse);
      expect(th.last, 'a');
    });

    test('a change inside the interval waits, then goes out', () {
      final th = TrayTextThrottle();
      expect(th.offer('a', t0), isTrue);
      expect(th.offer('b', t0.add(const Duration(seconds: 1))), isFalse);
      expect(th.last, 'a');
      expect(th.offer('b', t0.add(const Duration(seconds: 2))), isTrue);
      expect(th.last, 'b');
    });

    test('reset lets the same text out again', () {
      final th = TrayTextThrottle();
      th.offer('a', t0);
      th.reset();
      expect(th.offer('a', t0), isTrue);
    });
  });

  group('decideClose', () {
    test('no tray always quits', () {
      for (final choice in [null, true, false]) {
        for (final busy in [true, false]) {
          expect(
            decideClose(closeToTray: choice, trayAvailable: false, busy: busy),
            CloseAction.quit,
          );
        }
      }
    });

    test('a saved choice is followed, busy or not', () {
      for (final busy in [true, false]) {
        expect(
          decideClose(closeToTray: true, trayAvailable: true, busy: busy),
          CloseAction.hideToTray,
        );
        expect(
          decideClose(closeToTray: false, trayAvailable: true, busy: busy),
          CloseAction.quit,
        );
      }
    });

    test('never chosen: quit when idle, ask when busy', () {
      expect(
        decideClose(closeToTray: null, trayAvailable: true, busy: false),
        CloseAction.quit,
      );
      expect(
        decideClose(closeToTray: null, trayAvailable: true, busy: true),
        CloseAction.ask,
      );
    });
  });

  group('CloseToTray persistence', () {
    test('defaults to never chosen', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(closeToTrayProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(closeToTrayProvider), isNull);
    });

    test('loads a saved choice', () async {
      SharedPreferences.setMockInitialValues({CloseToTray.prefsKey: true});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(closeToTrayProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(closeToTrayProvider), isTrue);
    });

    test('set saves it', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(closeToTrayProvider.notifier).set(false);
      expect(c.read(closeToTrayProvider), isFalse);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool(CloseToTray.prefsKey), isFalse);
    });

    test('tray availability starts false', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(trayAvailableProvider), isFalse);
      c.read(trayAvailableProvider.notifier).set(true);
      expect(c.read(trayAvailableProvider), isTrue);
    });
  });

  group('bandwidth helpers', () {
    test('labels', () {
      expect(trayBandwidthLabel('off'), 'Unlimited');
      expect(trayBandwidthLabel(''), 'Unlimited');
      expect(trayBandwidthLabel('5M'), '5M/s');
    });

    test('sameBandwidth ignores the binary suffix and case', () {
      expect(sameBandwidth('5M', '5Mi'), isTrue);
      expect(sameBandwidth('5m', '5M'), isTrue);
      expect(sameBandwidth('off', ''), isTrue);
      expect(sameBandwidth('5M', '10M'), isFalse);
    });
  });

  group('buildTrayMenu', () {
    Menu build(TrayMenuInput input, {List<String>? log}) => buildTrayMenu(
      input,
      onOpen: () => log?.add('open'),
      onTogglePause: () => log?.add('pause'),
      onSetBandwidth: (r) => log?.add('bw:$r'),
      onQuit: () => log?.add('quit'),
    );

    MenuItem item(Menu m, String key) =>
        m.items!.firstWhere((i) => i.key == key);

    const running = TrayMenuInput(
      status: 'Idle',
      queuePaused: false,
      bwLimit: 'off',
      engineReady: true,
    );

    test('has the four actions and a disabled status row', () {
      final m = build(running);
      final keys = m.items!.where((i) => i.key != null).map((i) => i.key);
      expect(keys, ['status', 'open', 'pause', 'bwlimit', 'quit']);
      expect(item(m, 'status').disabled, isTrue);
      expect(item(m, 'status').label, 'Idle');
    });

    test('pause label follows the queue', () {
      expect(item(build(running), 'pause').label, 'Pause all');
      const paused = TrayMenuInput(
        status: 'Idle',
        queuePaused: true,
        bwLimit: 'off',
        engineReady: true,
      );
      expect(item(build(paused), 'pause').label, 'Resume all');
    });

    test('clicks reach the callbacks', () {
      final log = <String>[];
      final m = build(running, log: log);
      for (final k in ['open', 'pause', 'quit']) {
        final i = item(m, k);
        i.onClick!(i);
      }
      final bw = item(
        m,
        'bwlimit',
      ).submenu!.items!.firstWhere((i) => i.key == 'bw:5M');
      bw.onClick!(bw);
      expect(log, ['open', 'pause', 'quit', 'bw:5M']);
    });

    test('the current preset is checked, a custom limit is shown', () {
      const custom = TrayMenuInput(
        status: 'Idle',
        queuePaused: false,
        bwLimit: '7Mi',
        engineReady: true,
      );
      final sub = item(build(custom), 'bwlimit').submenu!.items!;
      expect(sub.first.key, 'bw:current');
      expect(sub.first.checked, isTrue);
      expect(sub.where((i) => i.checked == true).length, 1);

      final std = item(build(running), 'bwlimit').submenu!.items!;
      expect(std.any((i) => i.key == 'bw:current'), isFalse);
      expect(std.firstWhere((i) => i.key == 'bw:off').checked, isTrue);
    });

    test('bandwidth is disabled until the engine is up', () {
      const starting = TrayMenuInput(
        status: 'Engine starting',
        queuePaused: false,
        bwLimit: 'off',
        engineReady: false,
      );
      expect(item(build(starting), 'bwlimit').disabled, isTrue);
      expect(item(build(running), 'bwlimit').disabled, isFalse);
    });

    test('structureKey ignores the status text', () {
      const a = TrayMenuInput(
        status: 'Idle',
        queuePaused: false,
        bwLimit: 'off',
        engineReady: true,
      );
      const b = TrayMenuInput(
        status: 'Transferring 1 file',
        queuePaused: false,
        bwLimit: 'off',
        engineReady: true,
      );
      expect(a.structureKey, b.structureKey);
    });
  });
}
