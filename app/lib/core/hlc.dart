import 'dart:math' as math;

/// Hybrid logical clock stamp; its text form sorts in causal order.
///
/// It keeps the order of edits correct even when a phone has the wrong time.
final class Hlc implements Comparable<Hlc> {
  /// Creates a stamp from its parts.
  const Hlc({required this.wallMs, required this.counter, required this.node});

  /// The zero stamp of [node].
  const Hlc.zero(String node) : this(wallMs: 0, counter: 0, node: node);

  /// Physical component, UTC milliseconds.
  final int wallMs;

  /// Logical counter for events within one millisecond.
  final int counter;

  /// Identifier of the device that produced the stamp.
  final String node;

  /// Parses [text], returning null when it is not a valid stamp.
  static Hlc? tryParse(String text) {
    final match = RegExp(r'^(\d{15})-([0-9a-f]{6})-(.+)$').firstMatch(text);
    if (match == null) return null;
    return Hlc(
      wallMs: int.parse(match.group(1) ?? '0'),
      counter: int.parse(match.group(2) ?? '0', radix: 16),
      node: match.group(3) ?? '',
    );
  }

  /// Next stamp for a local event at [nowMs].
  Hlc tick(int nowMs) {
    final wall = math.max(wallMs, nowMs);
    return Hlc(
      wallMs: wall,
      counter: wall == wallMs ? counter + 1 : 0,
      node: node,
    );
  }

  /// Next stamp after receiving [remote] at [nowMs].
  Hlc merge(Hlc remote, int nowMs) {
    final wall = math.max(math.max(wallMs, remote.wallMs), nowMs);
    final int next;
    if (wall == wallMs && wall == remote.wallMs) {
      next = math.max(counter, remote.counter) + 1;
    } else if (wall == wallMs) {
      next = counter + 1;
    } else if (wall == remote.wallMs) {
      next = remote.counter + 1;
    } else {
      next = 0;
    }
    return Hlc(wallMs: wall, counter: next, node: node);
  }

  @override
  int compareTo(Hlc other) => toString().compareTo(other.toString());

  @override
  String toString() {
    final wall = wallMs.toString().padLeft(15, '0');
    final count = counter.toRadixString(16).padLeft(6, '0');
    return '$wall-$count-$node';
  }
}
