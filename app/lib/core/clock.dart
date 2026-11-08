/// Source of the current time, injected so that logic stays testable.
abstract interface class Clock {
  /// Current UTC time in milliseconds since the epoch.
  int nowUtcMs();
}

/// [Clock] backed by the device time.
final class SystemClock implements Clock {
  /// Creates the device clock.
  const SystemClock();

  @override
  int nowUtcMs() => DateTime.now().toUtc().millisecondsSinceEpoch;
}
