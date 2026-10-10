/// Interface size (issue #32): the arithmetic the binding and MediaQuery must
/// agree on, and where the starting size comes from.
library;

import 'package:airclone/src/state/interface_scale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AIRCLONE_SCALE', () {
    test('accepts a number or a percentage', () {
      expect(parseInterfaceScale('2'), 2.0);
      expect(parseInterfaceScale(' 1.5 '), 1.5);
      expect(parseInterfaceScale('150%'), 1.5);
      expect(parseInterfaceScale('125 %'), 1.25);
    });

    // A typo must not become a usable-looking wrong size.
    test('ignores junk and out-of-range values instead of clamping', () {
      for (final bad in [
        null,
        '',
        'big',
        '2x',
        '0',
        '-1',
        '0.4',
        '3.5',
        '400%',
        'NaN',
        'Infinity',
      ]) {
        expect(parseInterfaceScale(bad), isNull, reason: '"$bad"');
      }
    });
  });

  group('the window at a scale', () {
    // A 4K window that GTK reports at ratio 1: the case from the report.
    const physical = BoxConstraints.tightFor(width: 3840, height: 2160);

    test(
      '200% lays out a 1920x1080 window drawn across all 3840x2160 pixels',
      () {
        final c = scaledViewConfiguration(
          physicalConstraints: physical,
          devicePixelRatio: 1.0,
          scale: 2.0,
        );
        expect(c.devicePixelRatio, 2.0);
        expect(c.logicalConstraints.maxWidth, 1920);
        expect(c.logicalConstraints.maxHeight, 1080);
        // The physical surface is untouched: the picture still fills the window.
        expect(c.physicalConstraints, physical);
      },
    );

    test('multiplies the OS ratio rather than replacing it', () {
      final c = scaledViewConfiguration(
        physicalConstraints: physical,
        devicePixelRatio: 2.0,
        scale: 1.25,
      );
      expect(c.devicePixelRatio, 2.5);
      expect(c.logicalConstraints.maxWidth, 3840 / 2.5);
    });

    test('100% is exactly what Flutter would have done', () {
      final c = scaledViewConfiguration(
        physicalConstraints: physical,
        devicePixelRatio: 1.5,
        scale: 1.0,
      );
      expect(c.devicePixelRatio, 1.5);
      expect(c.logicalConstraints, physical / 1.5);
    });
  });

  group('MediaQuery agrees with the binding', () {
    const raw = MediaQueryData(
      size: Size(3840, 2160),
      devicePixelRatio: 1.0,
      padding: EdgeInsets.only(top: 40),
      viewInsets: EdgeInsets.only(bottom: 100),
    );

    test('size, ratio and insets are rescaled together', () {
      final m = scaleMediaQuery(raw, 2.0);
      expect(m.size, const Size(1920, 1080));
      expect(m.devicePixelRatio, 2.0);
      expect(m.padding.top, 20);
      expect(m.viewInsets.bottom, 50);
    });

    test('at 100% it is the same object', () {
      expect(identical(scaleMediaQuery(raw, 1.0), raw), isTrue);
    });
  });

  group('the starting size', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to 100%', () async {
      expect(await loadInitialInterfaceScale(environment: const {}), 1.0);
    });

    test('the saved setting is used', () async {
      SharedPreferences.setMockInitialValues({'interface_scale': 1.75});
      expect(await loadInitialInterfaceScale(environment: const {}), 1.75);
    });

    test('AIRCLONE_SCALE wins over the saved setting', () async {
      SharedPreferences.setMockInitialValues({'interface_scale': 1.75});
      expect(
        await loadInitialInterfaceScale(
          environment: const {'AIRCLONE_SCALE': '2'},
        ),
        2.0,
      );
      expect(
        interfaceScaleFromEnvironment(
          environment: const {'AIRCLONE_SCALE': '2'},
        ),
        isTrue,
      );
    });

    test('a bad AIRCLONE_SCALE falls back to the saved setting', () async {
      SharedPreferences.setMockInitialValues({'interface_scale': 1.5});
      expect(
        await loadInitialInterfaceScale(
          environment: const {'AIRCLONE_SCALE': 'huge'},
        ),
        1.5,
      );
    });

    test('a corrupt saved value is ignored', () async {
      SharedPreferences.setMockInitialValues({'interface_scale': 40.0});
      expect(await loadInitialInterfaceScale(environment: const {}), 1.0);
    });
  });

  test('every offered size is in range and 100% is one of them', () {
    expect(kInterfaceScales, contains(1.0));
    for (final s in kInterfaceScales) {
      expect(parseInterfaceScale('$s'), s);
    }
  });
}
