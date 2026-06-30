import 'package:airclone/src/state/bw_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const windows = [
    BwWindow(hour: 8, minute: 0, rate: '512k'),
    BwWindow(hour: 18, minute: 0, rate: 'off'),
  ];

  test('activeRate picks the current window', () {
    expect(activeRate(windows, DateTime(2026, 6, 30, 9, 0)), '512k');
    expect(activeRate(windows, DateTime(2026, 6, 30, 20, 0)), 'off');
    expect(
      activeRate(windows, DateTime(2026, 6, 30, 18, 0)),
      'off',
    ); // boundary
  });

  test('before the first window wraps to the last (previous day)', () {
    // 06:00 is before 08:00 → the last window (18:00 → off) is still in effect.
    expect(activeRate(windows, DateTime(2026, 6, 30, 6, 0)), 'off');
  });

  test('empty timetable yields null', () {
    expect(activeRate(const [], DateTime(2026, 6, 30, 9, 0)), isNull);
  });

  test('unsorted windows are handled', () {
    const unsorted = [
      BwWindow(hour: 18, minute: 0, rate: 'off'),
      BwWindow(hour: 8, minute: 0, rate: '512k'),
    ];
    expect(activeRate(unsorted, DateTime(2026, 6, 30, 9, 0)), '512k');
  });

  test('BwSchedule JSON round-trips', () {
    const s = BwSchedule(enabled: true, windows: windows);
    final back = BwSchedule.fromJson(s.toJson());
    expect(back.enabled, isTrue);
    expect(back.windows.length, 2);
    expect(back.windows.first.rate, '512k');
    expect(back.windows[1].hour, 18);
  });
}
