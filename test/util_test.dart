import 'package:test/test.dart';
import 'package:minic/src/util.dart';

void main() {
  group('PeekIterator', () {
    test('exposes correct [Iterator] behaviour', () {
      var it = new PeekIterator.fromIterable(['a', 'b', 'c']);

      expect(it.moveNext(), equals(true));
      expect(it.current, equals('a'));
      expect(it.moveNext(), equals(true));
      expect(it.current, equals('b'));
      expect(it.moveNext(), equals(true));
      expect(it.current, equals('c'));
      expect(it.moveNext(), equals(false));
      expect(it.current, equals(null));
    });

    test('exposes correct `next` value', () {
      var it = new PeekIterator.fromIterable(['a', 'b', 'c']);

      it.moveNext();
      expect(it.next, equals('b'));
      it.moveNext();
      expect(it.next, equals('c'));
      it.moveNext();
      expect(it.next, equals(null));
    });

    test('works with empty iterables', () {
      var it = new PeekIterator.fromIterable([]);

      expect(it.moveNext(), equals(false));
      expect(it.current, equals(null));
      expect(it.next, equals(null));
    });
  });
}
