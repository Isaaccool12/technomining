import 'package:engineer/core/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text form round-trips', () {
    const stamp = Hlc(wallMs: 1794147941000, counter: 7, node: 'device-a');
    final parsed = Hlc.tryParse(stamp.toString());
    expect(parsed?.toString(), stamp.toString());
  });

  test('invalid text is rejected', () {
    expect(Hlc.tryParse('2026'), isNull);
  });

  test('tick stays ordered when the phone clock goes back', () {
    const first = Hlc(wallMs: 5000, counter: 0, node: 'a');
    final second = first.tick(1000);
    expect(second.compareTo(first), greaterThan(0));
    expect(second.wallMs, 5000);
  });

  test('merge is later than both sides', () {
    const local = Hlc(wallMs: 5000, counter: 2, node: 'a');
    const remote = Hlc(wallMs: 5000, counter: 9, node: 'b');
    final merged = local.merge(remote, 1000);
    expect(merged.compareTo(local), greaterThan(0));
    expect(merged.counter, 10);
  });
}
