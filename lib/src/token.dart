/// Before parsing, source code is split into tokens that each represent an
/// atomic part of the code, like operators, keywords, or names. We do this
/// because it is easier to implement the parser if it doesn't need to handle
/// the text processing that recognizes these patterns.
library minic.token;

import 'dart:collection' show LinkedHashMap;
import 'dart:math' show Point;
import 'util.dart' show PeekIterator;

/// Every token has a type that is used to identify the tokens purpose in the
/// program. Compare a token type to the ones stored in `values`.
///
/// Note that some tokens are used in multiple contexts. For example, the `&`
/// operator can be parsed both as the prefix operator [address of][1], or as
/// the infix operator [binary and][2].
///
/// [1]: http://en.cppreference.com/w/c/language/operator_member_access#Address_of
/// [2]: http://en.cppreference.com/w/c/language/operator_arithmetic#Bitwise_logic
class TokenType {
  /// Used to recognize this type during tokenization.
  final Pattern pattern;

  const TokenType._internal(this.pattern);

  /// All token types that are required to parse C source code.
  ///
  /// This is a [LinkedHashMap], so you will iterate over the patterns in the
  /// order they were defined. The elements in `TokenType` are ordered putting
  /// more restrictive ones before others they collide with, e.g. the `++` token
  /// occurs before the `+` token.
  static final Map<String, TokenType> values =
      new LinkedHashMap.from(<String, TokenType>{
    '&&': const TokenType._internal('&&'),
    '&=': const TokenType._internal('&='),
    '&': const TokenType._internal('&'),
    '!=': const TokenType._internal('!='),
    '!': const TokenType._internal('!'),
    '^=': const TokenType._internal('^='),
    '^': const TokenType._internal('^'),
    ':': const TokenType._internal(':'),
    ',': const TokenType._internal(','),
    '/=': const TokenType._internal('/='),
    '/': const TokenType._internal('/'),
    '.*': const TokenType._internal('.*'),
    '.': const TokenType._internal('.'),
    '==': const TokenType._internal('=='),
    '=': const TokenType._internal('='),
    '>=': const TokenType._internal('>='),
    '>>=': const TokenType._internal('>>='),
    '>>': const TokenType._internal('>>'),
    '>': const TokenType._internal('>'),
    '(': const TokenType._internal('('),
    '{': const TokenType._internal('{'),
    '[': const TokenType._internal('['),
    '<=': const TokenType._internal('<='),
    '<<=': const TokenType._internal('<<='),
    '<<': const TokenType._internal('<<'),
    '<': const TokenType._internal('<'),
    '-=': const TokenType._internal('-='),
    '->*': const TokenType._internal('->*'),
    '->': const TokenType._internal('->'),
    '--': const TokenType._internal('--'),
    '-': const TokenType._internal('-'),
    '%=': const TokenType._internal('%='),
    '%': const TokenType._internal('%'),
    '|=': const TokenType._internal('|='),
    '||': const TokenType._internal('||'),
    '|': const TokenType._internal('|'),
    '+=': const TokenType._internal('+='),
    '++': const TokenType._internal('++'),
    '+': const TokenType._internal('+'),
    '?': const TokenType._internal('?'),
    ')': const TokenType._internal(')'),
    '}': const TokenType._internal('}'),
    ']': const TokenType._internal(']'),
    '*=': const TokenType._internal('*='),
    '*': const TokenType._internal('*'),
    '~': const TokenType._internal('~'),
    'sizeof': const TokenType._internal('sizeof'),
    'if': const TokenType._internal('if'),
    'else': const TokenType._internal('else'),
    ';': const TokenType._internal(';'),
    'const': const TokenType._internal('const'),
    'static': const TokenType._internal('static'),
    'floatLiteral':
        new TokenType._internal(new RegExp(r'-?((?:\d+\.\d*)|(?:\d*\.\d+))f?')),
    'intLiteral': new TokenType._internal(new RegExp(r'-?(0x)?\d+')),
    'stringLiteral': new TokenType._internal(new RegExp('"[^"]"')),
    'charLiteral': new TokenType._internal(new RegExp("'.'")),
    'name': new TokenType._internal(new RegExp(r'[A-Za-z_]\w*'))
  });

  static final TokenType endOfFile = new TokenType._internal(new RegExp(r'^$'));
}

/// A token encapsulates the occurence of a [TokenType] in a parsed source code.
class Token {
  final TokenType type;

  /// The string that was matched by the pattern of this tokens type.
  final String value;

  /// 0-based index into the source code this token was created from. `x` is the
  /// column and `y` is the line.
  final Point position;

  Token(this.type, this.value, this.position);
}

/// This class processes raw C source code and turns it into a [Token] stream.
/// It can't handle malformed code and will abort by throwing
/// [UnrecognizedSourceCodeException] if it doesn't match any token pattern.
/// However, tokenization is performed lazy, so the exception won't be thrown
/// until you reach the broken position.
class TokenIterator extends PeekIterator<Token> {
  static final _whitespacePattern = new RegExp(r'\s+');

  /// Create a [TokenIterator] for the source code in [lines].
  ///
  /// Lines are expected to contain no linebreaks.
  TokenIterator.fromSource(List<String> lines)
      : super.fromIterable(() sync* {
          int row = 0;
          int col = 0;
          while (row < lines.length && col < lines.last.length) {
            var line = lines[row].substring(col);
            if (line.length == 0) {
              row++;
              col = 0;
              continue;
            }
            print(line);
            var match;
            if ((match = _whitespacePattern.matchAsPrefix(line)) == null) {
              for (var type in TokenType.values.values) {
                if ((match = type.pattern.matchAsPrefix(line)) != null) {
                  yield new Token(type, match.group(0), new Point(col, row));
                  break;
                }
              }
            }
            if (match == null) throw new UnrecognizedSourceCodeException(
                "Couldn't match the source against any pattern",
                line,
                new Point(col, row));
            col += match.end;
          }
          print(lines);

          yield new Token(TokenType.endOfFile, '', new Point(col, row));
        }());

  /// Match the current token against `expected`, which may be a single
  /// [TokenType] or a list of them. If successful, return that token and
  /// forward the TokenIterator by one element.
  Token consume(expected) {
    _assertTypeMatchesExpected(expected, current);
    var curr = current;
    moveNext();
    return curr;
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

  /// Throw a [UnexpectedTokenException] if the token is null or its type
  /// doesn't match the [expected] ones.
  /// `expected` may be a list of [TokenType]s, or a single one.
  void _assertTypeMatchesExpected(Token token, expected) {
    if (expected is TokenType) expected = [expected];
    if (expected is! List) throw new ArgumentError.value(
        expected, 'expected', 'Must be `TokenType` or `List<TokenType>`');
    if (token ==
        null) throw new UnexpectedTokenException('Tokens exhausted', null);
    if (!expected.contains(token)) throw new UnexpectedTokenException(
        'Expected one of $expected, but found ${token.type}', token);
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
