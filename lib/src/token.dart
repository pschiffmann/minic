library minic.token;

import 'dart:math' show Point;
import 'language.dart';
import 'util.dart';

class Token {
  final TokenType type;
  final String value;
  final Point position;

  Token(this.type, this.value, this.position);
}

class TokenIterator extends PeekIterator<Token> {
  static final _whitespacePattern = new RegExp('\s+');

  /// Create a [TokenIterator] for the source code in [source].
  TokenIterator.fromSource(String source)
      : super.fromIterable(() sync* {
          var lines = source.split(new RegExp('\r?\n'));
          int row = 0;
          int col = 0;
          while (row < lines.length && col < lines.last.length) {
            var line = lines[row].substring(col);
            if (line.length == 0) {
              row++;
              col = 0;
              continue;
            }
            var match;
            if ((match = _whitespacePattern.matchAsPrefix(line)) == null) {
              for (var type in tokenPattern.keys) {
                if ((match = tokenPattern[type].matchAsPrefix(source)) !=
                    null) {
                  yield new Token(type, match.group(0), new Point(row, col));
                  break;
                }
              }
            }
            if (match == null) throw new UnrecognizedSourceCodeException(
                "Couldn't match the source against any pattern",
                source,
                new Point(row, col));
            col += match.end;
          }
          yield new Token(TokenType.endOfFile, '', new Point(row, col));
        }());

  /// Forward the TokenIterator by one element and return the new [current] one.
  /// Match that token against [expected].
  Token consume(expected) {
    _assertTypeMatchesExpected(expected, next);
    moveNext();
    return current;
  }

  /// Match [current] against [expected].
  Token checkCurrent(expected) {
    _assertTypeMatchesExpected(expected, current);
    return current;
  }

  /// Match [next] against [expected].
  Token checkNext(expected) {
    _assertTypeMatchesExpected(expected, next);
    return next;
  }

  /// Throw a [UnexpectedTokenException] if the token is null its type doesn't
  /// match the [expected] ones.
  /// `expected` may be a list of [TokenType]s, or a single one.
  void _assertTypeMatchesExpected(Token token, expected) {
    if (expected is TokenType) expected = [expected];
    if (expected is! List) throw new ArgumentError.value(
        expected, 'expected', 'Must be [TokenType] or [List<TokenType>]');
    if (token ==
        null) throw new UnexpectedTokenException('Tokens exhausted', null);
    if (!expected.contains(token)) throw new UnexpectedTokenException(
        'Expected one of $expected, but got $token', token);
  }
}

/// Thrown during tokenization if the current input doesn't match any pattern.
class UnrecognizedSourceCodeException implements Exception {
  String message;
  String source;
  Point position;
  UnrecognizedSourceCodeException(this.message, this.source, this.position);
}

/// Thrown during parsing if [token] can't be processed at this point.
class UnexpectedTokenException implements Exception {
  final String message;
  final Token token;
  UnexpectedTokenException(this.message, this.token);
}
