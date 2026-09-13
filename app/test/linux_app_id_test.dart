import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Linux app ID is written in files that cannot import each other, and
/// they must agree exactly:
///
///  - `APPLICATION_ID` in `linux/CMakeLists.txt` is what the running window
///    reports: the GApplication ID, which GTK sends as the Wayland app_id, and
///    through `g_set_prgname` the X11 WM_CLASS;
///  - the desktop file must be NAMED after that ID, or the dock cannot match
///    the window to its launcher and shows a generic icon;
///  - the Flatpak manifest, the MetaInfo `<id>` and the icon file names must
///    use it too, or Flathub's linter rejects the build.
///
/// The ID is `com.gigaionllc.airclone`, the same as on Android, iOS and macOS.
/// Flathub cannot rename an ID after acceptance without a resubmission (see
/// dev/plans/flathub-plan.md), so a drift is worth catching here rather than
/// in review.
void main() {
  const id = 'com.gigaionllc.airclone';
  const pkg = 'linux/packaging';

  // Run from app/. A context without the Linux tree has nothing to check.
  final checkedOut = Directory(pkg).existsSync();

  String read(String path) => File(path).readAsStringSync();
  List<String> lines(String path) =>
      LineSplitter.split(read(path)).map((l) => l.trim()).toList();

  test('the runner reports the ID', () {
    if (!checkedOut) return;
    expect(read('linux/CMakeLists.txt'), contains('set(APPLICATION_ID "$id")'));

    final runner = read('linux/runner/my_application.cc');
    expect(
      runner,
      contains('"application-id", APPLICATION_ID'),
      reason: 'the Wayland app_id would stop matching the desktop file',
    );
    expect(
      runner,
      contains('g_set_prgname(APPLICATION_ID)'),
      reason: 'the X11 WM_CLASS would fall back to the binary name',
    );
  });

  test('the desktop file is named after the ID and points back at it', () {
    if (!checkedOut) return;
    final desktop = lines('$pkg/$id.desktop');
    expect(desktop, contains('Icon=$id'));
    expect(desktop, contains('StartupWMClass=$id'));
  });

  test('the MetaInfo file is named after the ID and launches it', () {
    if (!checkedOut) return;
    final metainfo = read('$pkg/$id.metainfo.xml');
    expect(metainfo, contains('<id>$id</id>'));
    expect(
      metainfo,
      contains('<launchable type="desktop-id">$id.desktop</launchable>'),
    );
  });

  test('the Flatpak manifest is named after the ID and installs by it', () {
    if (!checkedOut) return;
    final manifest = lines('$pkg/$id.yml');
    expect(manifest, contains('app-id: $id'));
    // `/app/share/...` rather than `/share/...`: a dependency's `cleanup` list
    // names `/share/applications` too, and that is not an install.
    final apps = manifest.where((l) => l.contains('/app/share/applications'));
    expect(apps, isNotEmpty);
    expect(apps, everyElement(contains('$id.desktop')));
    final meta = manifest.where((l) => l.contains('/app/share/metainfo'));
    expect(meta, isNotEmpty);
    expect(meta, everyElement(contains('$id.metainfo.xml')));

    final icons = manifest
        .where((l) => l.contains('/app/share/icons/'))
        .toList();
    expect(icons, isNotEmpty);
    expect(icons, everyElement(endsWith('/apps/$id.png')));
    // Flathub requires an icon of at least 256x256.
    expect(icons.any((l) => l.contains('/256x256/')), isTrue);
  });

  test('the Flatpak build script stages files by the same ID', () {
    final script = File('../dev/linux/build-flatpak.sh');
    if (!script.existsSync()) return;
    expect(
      LineSplitter.split(script.readAsStringSync()),
      contains('APP_ID="$id"'),
    );
  });
}
