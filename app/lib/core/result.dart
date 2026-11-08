/// Outcome of a recoverable operation.
sealed class Result<T, F> {
  /// Base constructor for the two outcomes.
  const Result();
}

/// Successful outcome carrying [value].
final class Ok<T, F> extends Result<T, F> {
  /// Wraps a successful [value].
  const Ok(this.value);

  /// The produced value.
  final T value;
}

/// Failed outcome carrying a typed [failure].
final class Err<T, F> extends Result<T, F> {
  /// Wraps a typed [failure].
  const Err(this.failure);

  /// The stable failure code.
  final F failure;
}
