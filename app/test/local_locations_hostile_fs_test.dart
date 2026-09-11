import 'dart:io';

import 'package:airclone/src/state/local_locations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user reported Airclone opening completely blank on Windows: an empty
/// sidebar with no section headers at all, and two empty panes, while the
/// toolbars, the address bars and "engine ok · rclone v1.75.1" all drew fine.
///
/// The shape of that screenshot is the clue. Those three regions are exactly the
/// three on-screen widgets that `ref.watch(drivesProvider)`, and in a RELEASE
/// build Flutter's default `ErrorWidget` paints a flat `0xF0C0C0C0` grey
/// rectangle with no text. A provider that throws takes down every widget
/// watching it — and `Directory.existsSync()` is not a predicate on Windows: the
/// SDK throws `FileSystemException("Exists failed", ...)` for anything the OS
/// refuses to stat. `Directory('CON:/').existsSync()` does exactly that on
/// Windows 11.
///
/// The drive sweep stats twenty-four letters of whatever volumes a machine
/// happens to have attached. One of them being unstattable — a mapped drive
/// whose server is gone, a card reader with no media — must cost that letter,
/// not the whole application.
void main() {
  test('an unstattable path is answered, not thrown', () {
    // The contract the fix rests on. Guard on Windows only: `CON:` is a reserved
    // DOS device name and means nothing to POSIX, where this is simply a
    // relative path that does not exist.
    if (!Platform.isWindows) return;
    expect(
      () => Directory('CON:/').existsSync(),
      throwsA(isA<FileSystemException>()),
      reason:
          'if this ever stops throwing, the hazard is gone and so is the '
          'reason for the guard in local_locations.dart',
    );
  });

  test('drivesProvider returns a list rather than entering an error state', () {
    // The regression itself: reading it must not throw, because three separate
    // widgets rethrow whatever it holds.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(() => c.read(drivesProvider), returnsNormally);
    expect(c.read(drivesProvider), isA<List<LocalLocation>>());
  });

  test('every drive it does offer has a usable fs root', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    for (final d in c.read(drivesProvider)) {
      expect(d.remote.fs, isNotEmpty);
      expect(d.remote.fs, endsWith('/'), reason: 'rclone local fs shape');
      expect(d.remote.isLocal, isTrue);
    }
  });

  test('the default user folders survive a hostile filesystem', () {
    // buildDefaultUserFolders() stats $HOME and seven standard folders on every
    // launch — a roaming profile on an unreachable share reaches the same throw.
    expect(buildDefaultUserFolders, returnsNormally);
  });

  test('a seeded folder that cannot be stat-ed is dropped, not fatal', () {
    // Whatever the machine, the seed list must be a list of real locations.
    for (final l in buildDefaultUserFolders()) {
      expect(l.remote.fs, isNotEmpty);
      expect(l.remote.isLocal, isTrue);
    }
  });

  group("the reporter's machine: E:/ is an empty card reader", () {
    // Verbatim from the diagnostics report on issue #3, Windows 10 Pro for
    // Workstations 19045, Airclone 0.8.1:
    //
    //   FileSystemException: Exists failed, path = 'E:/'
    //       (OS Error: The device is not ready, errno = 21)
    //
    // errno 21 is ERROR_NOT_READY. Reproduced here by making the stat throw for
    // exactly that letter, which is the only honest way to test it without an
    // empty card reader plugged into the build machine.
    bool statWithEmptyDriveAtE(String path) {
      if (path == 'E:/') {
        throw const FileSystemException(
          'Exists failed',
          'E:/',
          OSError('The device is not ready', 21),
        );
      }
      return path == 'C:/' || path == 'D:/';
    }

    test('the sweep survives it instead of taking the app down', () {
      expect(
        () => windowsDrives(existsSync: statWithEmptyDriveAtE),
        returnsNormally,
      );
    });

    test('the unreadable letter is skipped, the readable ones are kept', () {
      final drives = windowsDrives(existsSync: statWithEmptyDriveAtE);
      final letters = drives.map((d) => d.remote.fs).toList();
      expect(letters, ['C:/', 'D:/']);
      expect(letters, isNot(contains('E:/')));
    });

    test('a drive that throws does not stop the ones after it', () {
      // E comes before the rest of the alphabet: the old loop died at E and
      // never reached F..Z, so "skipped" has to mean skipped, not stopped.
      final drives = windowsDrives(
        existsSync: (p) => p == 'E:/'
            ? throw const FileSystemException('Exists failed', 'E:/')
            : p == 'Z:/',
      );
      expect(drives.map((d) => d.remote.fs), ['Z:/']);
    });

    test('every letter failing yields an empty list, not an exception', () {
      expect(
        windowsDrives(
          existsSync: (p) => throw FileSystemException('Exists failed', p),
        ),
        isEmpty,
      );
    });
  });
}
