import 'package:airclone/src/state/cloud_placeholder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// An online-only file gets no thumbnail, because drawing one downloads the
/// whole file. That is the right DEFAULT and a poor absolute — sometimes the
/// file is 3MB and you want to see what it is. Right-click → Show thumbnail is
/// how a user says so for one file.
void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('nothing is allowed until it is asked for', () {
    expect(c.read(thumbnailOptInProvider), isEmpty);
    expect(
      c.read(thumbnailOptInProvider.notifier).has('gdrive:', 'a/b.jpg'),
      isFalse,
    );
  });

  test('an opt-in covers exactly the file it was made for', () {
    c.read(thumbnailOptInProvider.notifier).allow('gdrive:', 'a/b.jpg');
    final n = c.read(thumbnailOptInProvider.notifier);
    expect(n.has('gdrive:', 'a/b.jpg'), isTrue);
    // Not its neighbour...
    expect(n.has('gdrive:', 'a/c.jpg'), isFalse);
    // ...and not the same path on a different remote, which is a different file.
    expect(n.has('s3:bucket', 'a/b.jpg'), isFalse);
  });

  test('opting in twice is not an error and does not duplicate', () {
    final n = c.read(thumbnailOptInProvider.notifier);
    n.allow('gdrive:', 'a/b.jpg');
    n.allow('gdrive:', 'a/b.jpg');
    expect(c.read(thumbnailOptInProvider).length, 1);
  });

  test('several files can be allowed independently', () {
    final n = c.read(thumbnailOptInProvider.notifier);
    n.allow('gdrive:', 'one.jpg');
    n.allow('gdrive:', 'two.jpg');
    expect(n.has('gdrive:', 'one.jpg'), isTrue);
    expect(n.has('gdrive:', 'two.jpg'), isTrue);
    expect(n.has('gdrive:', 'three.jpg'), isFalse);
  });

  test('the key keeps remote and path distinguishable', () {
    // A naive concatenation would make ('a:', 'b/c') and ('a:b', '/c') collide.
    expect(
      ThumbnailOptIn.keyFor('a:', 'b/c'),
      isNot(ThumbnailOptIn.keyFor('a:b', '/c')),
    );
  });

  test('a new container starts empty — the choice is per session', () {
    // Deliberately not persisted: an opt-in made on home wifi should not still
    // apply when the same folder is opened on a hotel connection next week.
    c.read(thumbnailOptInProvider.notifier).allow('gdrive:', 'a/b.jpg');
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(fresh.read(thumbnailOptInProvider), isEmpty);
  });
}
