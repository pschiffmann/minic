/// Before parsing, source code is split into tokens that each represent an
/// atomic part of the code, like operators, keywords, or names. We do this
/// because it is easier to implement the parser if it doesn't need to handle
/// the text processing that recognizes these patterns.
library minic.token;

import 'dart:collection' show LinkedHashMap;
import 'dart:math' show Point, max;
import 'util.dart' show PeekIterator;
import 'package:verbose_regexp/verbose_regexp.dart';

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

  /// The verbose name of this token type, mainly for debugging purposes.
  final String name;

  TokenType._(this.pattern, this.name);

  /// All token types that are required to parse C source code.
  ///
  /// This is a [LinkedHashMap], so you will iterate over the patterns in the
  /// order they were defined. The elements in `TokenType` are ordered putting
  /// more restrictive ones before others they collide with, e.g. the `++` token
  /// occurs before the `+` token.
  static final Map<String, TokenType> values = () {
    var values = new LinkedHashMap<String, TokenType>();

    for (var op in [
      '&&',
      '&=',
      '&',
      '!=',
      '!',
      '^=',
      '^',
      ':',
      ',',
      '/=',
      '/',
      '==',
      '=',
      '>=',
      '>>=',
      '>>',
      '>',
      '(',
      '{',
      '[',
      '<=',
      '<<=',
      '<<',
      '<',
      '-=',
      '->',
      '--',
      '-',
      '%=',
      '%',
      '|=',
      '||',
      '|',
      '+=',
      '++',
      '+',
      '?',
      ')',
      '}',
      ']',
      '*=',
      '*',
      '~',
      ';'
    ]) values[op] = new TokenType._(op, op);

    // Don't match float constants like `.5f`
    values['.'] = new TokenType._(new RegExp(r'\.(?!\d)'), '.');

    for (var kw in [
      'auto',
      'break',
      'case',
      'const',
      'continue',
      'default',
      'do',
      'else',
      'enum',
      'extern',
      'for',
      'goto',
      'if',
      'long',
      'register',
      'return',
      'short',
      'signed',
      'sizeof',
      'static',
      'struct',
      'switch',
      'typedef',
      'union',
      'unsigned',
      'void',
      'volatile',
      'while',
    ]) values[kw] = new TokenType._(new RegExp(kw + r'\b'), kw);

    values['numberLiteral'] = new TokenType._(new RegExp(verbose(r'''
                              # group numbers and meaning:
      (                       #  1: digits (whole number and fraction)
        (-)?                  #  2: prefix negation
        (?:
          0[xX]([0-9a-fA-F]+) #  3: hex value
          |
          0([0-7]+)           #  4: octal value
          |
          (\d+)               #  5: decimal value
        )
        (                     #  6: dot separator
          \.(\d*)             #  7: fraction after whole number
        )?
        |
        \.(\d+)               #  8: fraction, whole number omitted
      )
      (?:[eE](-?\d+))?        #  9: exponent (float literal only)
      ([dDfFlLuU]*)           # 10: double, float, long, unsigned type hints
      (?!\w)
    ''')), 'numberLiteral');

    values['stringLiteral'] = new TokenType._(new RegExp(verbose(r'''
        "
        (?:
          \\.
          |
          [^"]
        )*
        "
      ''')), 'stringLiteral');

    values['charLiteral'] =
        new TokenType._(new RegExp("'[^']'"), 'charLiteral');

    values['name'] = new TokenType._(new RegExp(r'([A-Za-z_]\w*)'), 'name');

    return values;
  }();

  /// A token with this type is emitted by [Scanner] to indicate that it has
  /// reached the end of the source code. This way you can always compare
  /// `token.type` to the expected type and don't have to care about derefencing
  /// that property on `null`.
  static final TokenType endOfFile = new TokenType._(null, 'endOfFile');

  String toString() => "TokenType('$name')";
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

  String toString() => "Token(type='${type.name}', `$value` at $position)";
}

/// This class processes raw C source code and turns it into a [Token] stream.
/// It can't handle malformed code and will abort by throwing
/// [UnrecognizedSourceCodeException] if it doesn't match any token pattern.
/// However, tokenization is performed lazy, so the exception won't be thrown
/// until you reach the broken position.
class Scanner extends PeekIterator<Token> {
  static final _whitespacePattern = new RegExp(r'\s+');

  /// Create a [Scanner] for the source code in `lines`.
  Scanner(String lines)
      : super.fromIterable(() sync* {
          // Helper function that returns a [Point], where `y` is the number of
          // `\n` in `str`, and `x` the number of characters in the last line.
          var countLines = (String str) => new Point(
              str.endsWith('\n') ? 0 : str.length - max(0, str.lastIndexOf('\n')),
              '\n'.allMatches(str).length);

          var logicalPosition = new Point(0, 0);

          while (lines.length > 0) {
            Match match = _whitespacePattern.matchAsPrefix(lines);
            if (match == null) {
              for (var type in TokenType.values.values) {
                if ((match = type.pattern.matchAsPrefix(lines)) != null) {
                  yield new Token(type, match.group(0), logicalPosition);
                  break;
                }
              }
            }

            if (match == null) throw new UnrecognizedSourceCodeException(
                "Couldn't match the source against any pattern",
                (lines + '\n').substring(0, lines.indexOf('\n')),
                logicalPosition);

            lines = lines.substring(match.group(0).length);
            var offset = countLines(match.group(0));
            if (offset.y == 0) logicalPosition += offset;
            else logicalPosition =
                new Point(offset.x, logicalPosition.y + offset.y);
          }

          yield new Token(TokenType.endOfFile, null, logicalPosition);
        }());

  /// Check whether `current.type.name` is one of `expected`. If successful,
  /// return that token and forward the TokenIterator by one element. Throw an
  /// [UnexpectedTokenException] on error.
  Token consume(List<String> expected) {
    _assertTypeMatchesExpected(current, expected);
    var curr = current;
    moveNext();
    return curr;
  }

  /// Match [current] against [expected].
  Token checkCurrent(List<String> expected) {
    _assertTypeMatchesExpected(current, expected);
    return current;
  }

  /// Match [next] against [expected].
  Token checkNext(List<String> expected) {
    _assertTypeMatchesExpected(next, expected);
    return next;
  }

  /// Throw a [UnexpectedTokenException] if the token is null or its type
  /// doesn't match the [expected] ones.
  /// `expected` may be a list of [TokenType]s, or a single one.
  void _assertTypeMatchesExpected(Token token, List<String> expected) {
    if (token ==
        null) throw new UnexpectedTokenException('Tokens exhausted', null);
    if (!expected.contains(token.type.name)) throw new UnexpectedTokenException(
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
  String message;
  Token token;
  UnexpectedTokenException(this.message, this.token);
}
