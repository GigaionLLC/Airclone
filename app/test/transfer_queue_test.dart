import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A concurrency limit that skips SharedPreferences so the queue logic can be
/// tested deterministically.
class _FixedConcurrency extends TransferConcurrency {
  _FixedConcurrency(this.value);
  final int value;
  @override
  int build() => value;
}

ProviderContainer _containerWithLimit(int limit) => ProviderContainer(
  overrides: [
    transferConcurrencyProvider.overrideWith(() => _FixedConcurrency(limit)),
  ],
);

int _count(ProviderContainer c, JobStatus status) =>
    c.read(jobsControllerProvider).where((j) => j.status == status).length;

/// Enqueues [n] no-op transfers and returns their job ids in order.
List<int> _enqueueAll(JobsController jobs, int n) => [
  for (var i = 0; i < n; i++)
    () {
      final job = jobs.add(
        type: JobType.copy,
        source: 's$i',
        dest: 'd$i',
        status: JobStatus.queued,
      );
      jobs.enqueue(job.id, () async {});
      return job.id;
    }(),
];

void main() {
  test('unlimited (0) dispatches every transfer immediately', () {
    final c = _containerWithLimit(0);
    addTearDown(c.dispose);
    final jobs = c.read(jobsControllerProvider.notifier);

    _enqueueAll(jobs, 5);

    expect(_count(c, JobStatus.running), 5);
    expect(_count(c, JobStatus.queued), 0);
  });

  test('a limit caps concurrent transfers; the rest wait queued', () {
    final c = _containerWithLimit(2);
    addTearDown(c.dispose);
    final jobs = c.read(jobsControllerProvider.notifier);

    final ids = _enqueueAll(jobs, 4);

    expect(_count(c, JobStatus.running), 2);
    expect(_count(c, JobStatus.queued), 2);

    // Completing a running job frees a slot for the next queued one.
    jobs.markDone(ids[0], JobStatus.success);
    expect(_count(c, JobStatus.running), 2);
    expect(_count(c, JobStatus.queued), 1);
    expect(_count(c, JobStatus.success), 1);
  });

  test('canceling a queued job removes it without dispatching', () {
    final c = _containerWithLimit(1);
    addTearDown(c.dispose);
    final jobs = c.read(jobsControllerProvider.notifier);

    final ids = _enqueueAll(jobs, 3);
    expect(_count(c, JobStatus.running), 1);
    expect(_count(c, JobStatus.queued), 2);

    // Cancel the last queued job: it never dispatches and a slot is not used.
    jobs.stop(ids[2]);
    expect(_count(c, JobStatus.running), 1);
    expect(_count(c, JobStatus.queued), 1);
    expect(_count(c, JobStatus.canceled), 1);
  });
}
