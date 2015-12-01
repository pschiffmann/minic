library minic.src.util;

import 'dart:math';

/// A wrapper around another [Iterator] with an additional getter [next].
class PeekIterator<E> implements Iterator<E> {
  Iterator<E> original;

  E _current, _next = null;
  bool exhausted;

  PeekIterator.fromIterator(Iterator<E> original)
      : original = original,
        exhausted = !original.moveNext(),
        _next = original.current;

  PeekIterator.fromIterable(Iterable<E> it) : this.fromIterator(it.iterator);

  E get current => _current;

  /// Return the next element, or `null` if [current] points to the last element
  /// in the original iterator.
  E get next => _next;

  bool moveNext() {
    if (exhausted) {
      _current = null;
      return false;
    }
    exhausted = !original.moveNext();
    _current = _next;
    _next = original.current;
    return true;
  }
}

/// Return the number of bytes required to represent `n` values.
int calculateRequiredBytes(int n) => (log(n) / log(256)).ceil();
