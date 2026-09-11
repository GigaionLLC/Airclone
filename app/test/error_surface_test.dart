import 'package:airclone/src/ui/error_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user reported Airclone as "completely blank". It was not blank — three
/// widgets had thrown, and Flutter's RELEASE error box is a flat grey rectangle
/// with NO TEXT, because its message is assembled inside an `assert`. Nothing on
/// screen said an error had happened, so the only report we could get was
/// "nothing shows up" and the cause had to be inferred from a screenshot.
///
/// The throw behind that is fixed. This covers the failure MODE, which is what
/// would have made the next one equally invisible.
///
/// [AircloneErrorSurface] is rendered directly rather than through
/// [installVisibleErrorWidget], which is a deliberate no-op in debug — testing
/// through the installer would exercise nothing that ships.
void main() {
  FlutterErrorDetails details(Object e) =>
      FlutterErrorDetails(exception: e, library: 'test');

  Widget host(Widget child) =>
      Directionality(textDirection: TextDirection.ltr, child: child);

  testWidgets('it says an error happened, rather than showing a blank box', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AircloneErrorSurface(details: details(StateError('boom')))),
    );
    expect(find.textContaining("couldn't be drawn"), findsOneWidget);
  });

  testWidgets('it shows the exception, so a screenshot is worth something', (
    tester,
  ) async {
    // The real one: an unstattable Windows drive letter.
    await tester.pumpWidget(
      host(
        AircloneErrorSurface(
          details: details('FileSystemException: Exists failed, path = Z:/'),
        ),
      ),
    );
    expect(find.textContaining('Exists failed'), findsOneWidget);
    expect(find.textContaining('Z:/'), findsOneWidget);
  });

  testWidgets('it points at the problem report', (tester) async {
    // The diagnostics log already holds the exception — the user just has to be
    // told it exists, at the moment they are looking at the failure.
    await tester.pumpWidget(
      host(AircloneErrorSurface(details: details(StateError('boom')))),
    );
    expect(find.textContaining('Problem report'), findsOneWidget);
  });

  testWidgets('it needs no Theme, Material, MediaQuery or provider', (
    tester,
  ) async {
    // It draws DURING a failure, so anything it depended on could be the thing
    // that just failed. Only a Directionality is supplied here.
    await tester.pumpWidget(
      host(AircloneErrorSurface(details: details(StateError('boom')))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a huge exception cannot push the guidance off screen', (
    tester,
  ) async {
    // A stack-like blob in a 240px sidebar must not crowd out the one line that
    // tells the user what to do next.
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 240,
          height: 300,
          child: AircloneErrorSurface(
            details: details(
              List.filled(400, 'very long failure text').join(' '),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Problem report'), findsOneWidget);
  });

  testWidgets('it survives being given an exception with an awkward toString', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AircloneErrorSurface(details: details(_Awkward()))),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining("couldn't be drawn"), findsOneWidget);
  });
}

class _Awkward {
  @override
  String toString() => '';
}
