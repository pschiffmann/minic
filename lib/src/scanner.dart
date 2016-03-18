/// Before parsing, source code is split into tokens that each represent an
/// atomic part of the code, like operators, keywords, or names. We do this
/// because it is easier to implement the parser if it doesn't need to handle
/// the text processing that recognizes these patterns.
library minic.src.scanner;

import 'package:source_span/source_span.dart';
import 'package:verbose_regexp/verbose_regexp.dart';
import 'memory.dart' show NumberType;
import 'util.dart' show PeekIterator;

/// Every [TokenType] has a `ValueExtractor`; It's a callback function that
/// converts the string representation of a value literal to a meaningful value.
/// The [Match] that is passed as argument is the one created with the
/// TokenTypes `pattern`.
typedef ValueExtractor(Match m);

/// The default [ValueExtractor].
String _wholeMatchExtractor(Match m) => m.group(0);

/// All backslash-escaped character sequences (see [reference][1]).
///
/// [1]: http://en.cppreference.com/w/c/language/escape
final Map<Pattern, ValueExtractor> _stringEscapes = {
  "'": (_) => "'",
  '"': (_) => '"',
  '?': (_) => '?',
  'a': (_) => '\a',
  'b': (_) => '\b',
  'f': (_) => '\f',
  'n': (_) => '\n',
  'r': (_) => '\r',
  't': (_) => '\t',
  'v': (_) => '\v',
  r'\': (_) => r'\',
  new RegExp(r'[0-7]{1,3}'): (m) =>
      new String.fromCharCode(int.parse(m.group(0), radix: 8)),
  new RegExp(r'[xu]([a-z0-9]+)', caseSensitive: false): (m) =>
      new String.fromCharCode(int.parse(m.group(1), radix: 16)),
};

/// Used to extract the char value from char literals. Searches for a single
/// character or a backslash-escaped sequence.
String _charExtractor(Match m) {
  var literal = m.group(1);
  if (literal.length == 1) return literal;
  if (literal.startsWith(r'\')) {
    for (var pattern in _stringEscapes.keys) {
      var escapeSequence = pattern.matchAsPrefix(literal, 1);
      if (escapeSequence == null) continue;
      if (escapeSequence.end < literal.length) break;
      return _stringEscapes[pattern](escapeSequence);
    }
    throw new UnrecognizedSourceCodeException('Invalid escape sequence', null);
  }
  throw new UnrecognizedSourceCodeException('Invalid char literal', null);
}

/// Used to extract [integer literals][1].
///
/// The result is a map with the structure:
///
///     {
///       "value": <int>
///       "type":  <NumberType>
///     }
///
/// [1]: http://en.cppreference.com/w/c/language/integer_constant
Map _intExtractor(Match m) {
  var value;
  var type = NumberType.sint32;
  if (m.group(1) != null) {
    value = int.parse(m.group(1), radix: 16);
  } else if (m.group(2) != null) {
    value = int.parse(m.group(2), radix: 8);
  } else {
    value = int.parse(m.group(3));
  }

  if (m.group(4) != null) {
    var isLong = m.group(4).toLowerCase().contains('l');
    var isUnsigned = m.group(4).toLowerCase().contains('u');
    if (isLong && isUnsigned)
      type = NumberType.uint64;
    else if (isLong)
      type = NumberType.sint64;
    else if (isUnsigned) type = NumberType.uint32;
  }
  return {'value': value, 'type': type};
}

/// Used to extract [floating point literals][1].
///
/// The result is a map with the structure:
///
///     {
///       "value": <double>
///       "type":  <NumberType>
///     }
///
/// [1]: http://en.cppreference.com/w/c/language/floating_constant
Map _floatingExtractor(Match m) => {
      'value': double.parse(m.group(1)),
      'type': (m.group(2)?.toLowerCase() ?? 'd') == 'd'
          ? NumberType.fp64
          : NumberType.fp32
    };

/// Used to extract the string value from string literals. Replaces all
/// backslash-escaped sequences with the corresponding unicode entities.
String _stringExtractor(Match m) {
  var literal = m.group(1);
  var progress = 0;
  findEscapeSequences: while (
      (progress = literal.indexOf(r'\', progress)) != -1) {
    for (var pattern in _stringEscapes.keys) {
      var escapeSequence = pattern.matchAsPrefix(literal, progress + 1);
      if (escapeSequence == null) continue;
      var replacement = _stringEscapes[pattern](escapeSequence);
      literal = literal.replaceRange(progress, escapeSequence.end, replacement);
      progress += replacement.length;
      continue findEscapeSequences;
    }
  }
  return literal;
}

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
  /// Stores [pattern]s for all token types. Some token types use [RegExp]s as
  /// patterns, which are not const-constructible.
  static Map<TokenType, Pattern> _patternCache = <TokenType, Pattern>{};

  /// Used to compute the [pattern].
  final Pattern _pattern;

  /// Used to compute the [pattern].
  final bool _patternIsRegexp;

  /// Used to recognize this type during tokenization.
  Pattern get pattern => _patternCache.putIfAbsent(
      this,
      () => _patternIsRegexp
          ? new RegExp(verbose(_pattern), caseSensitive: false)
          : _pattern);

  /// The verbose name of this token type, mainly for debugging purposes.
  final String name;

  /// Optional function callback used to further validate a match before it is
  /// accepted as a token value.
  final ValueExtractor valueExtractor;

  const TokenType(this.name, this._pattern,
      [this._patternIsRegexp = false,
      this.valueExtractor = _wholeMatchExtractor]);

  /// TokenType `&&`
  static const TokenType ampamp = const TokenType('&&', '&&');

  /// TokenType `&=`
  static const TokenType ampeq = const TokenType('&=', '&=');

  /// TokenType `&`
  static const TokenType amp = const TokenType('&', '&');

  /// TokenType `!=`
  static const TokenType bangeq = const TokenType('!=', '!=');

  /// TokenType `!`
  static const TokenType bang = const TokenType('!', '!');

  /// TokenType `|=`
  static const TokenType bareq = const TokenType('|=', '|=');

  /// TokenType `||`
  static const TokenType barbar = const TokenType('||', '||');

  /// TokenType `|`
  static const TokenType bar = const TokenType('|', '|');

  /// TokenType `^=`
  static const TokenType careteq = const TokenType('^=', '^=');

  /// TokenType `^`
  static const TokenType caret = const TokenType('^', '^');

  /// TokenType `:`
  static const TokenType colon = const TokenType(':', ':');

  /// TokenType `,`
  static const TokenType comma = const TokenType(',', ',');

  /// TokenType `/=`
  static const TokenType diveq = const TokenType('/=', '/=');

  /// TokenType `/`
  static const TokenType div = const TokenType('/', '/');

  /// TokenType `==`
  static const TokenType eqeq = const TokenType('==', '==');

  /// TokenType `=`
  static const TokenType eq = const TokenType('=', '=');

  /// TokenType `>=`
  static const TokenType gteq = const TokenType('>=', '>=');

  /// TokenType `>>=`
  static const TokenType gtgteq = const TokenType('>>=', '>>=');

  /// TokenType `>>`
  static const TokenType gtgt = const TokenType('>>', '>>');

  /// TokenType `>`
  static const TokenType gt = const TokenType('>', '>');

  /// TokenType `(`
  static const TokenType lbracket = const TokenType('(', '(');

  /// TokenType `{`
  static const TokenType lcbracket = const TokenType('{', '{');

  /// TokenType `[`
  static const TokenType lsbracket = const TokenType('[', '[');

  /// TokenType `<=`
  static const TokenType lteq = const TokenType('<=', '<=');

  /// TokenType `<<=`
  static const TokenType ltlteq = const TokenType('<<=', '<<=');

  /// TokenType `<<`
  static const TokenType ltlt = const TokenType('<<', '<<');

  /// TokenType `<`
  static const TokenType lt = const TokenType('<', '<');

  /// TokenType `-=`
  static const TokenType minuseq = const TokenType('-=', '-=');

  /// TokenType `->`
  static const TokenType minusgt = const TokenType('->', '->');

  /// TokenType `--`
  static const TokenType minusminus = const TokenType('--', '--');

  /// TokenType `-`
  static const TokenType minus = const TokenType('-', '-');

  /// TokenType `%=`
  static const TokenType percenteq = const TokenType('%=', '%=');

  /// TokenType `%`
  static const TokenType percent = const TokenType('%', '%');

  /// TokenType `+=`
  static const TokenType pluseq = const TokenType('+=', '+=');

  /// TokenType `++`
  static const TokenType plusplus = const TokenType('++', '++');

  /// TokenType `+`
  static const TokenType plus = const TokenType('+', '+');

  /// TokenType `?`
  static const TokenType questionmark = const TokenType('?', '?');

  /// TokenType `)`
  static const TokenType rbracket = const TokenType(')', ')');

  /// TokenType `}`
  static const TokenType rcbracket = const TokenType('}', '}');

  /// TokenType `]`
  static const TokenType rsbracket = const TokenType(']', ']');

  /// TokenType `*=`
  static const TokenType stareq = const TokenType('*=', '*=');

  /// TokenType `*`
  static const TokenType star = const TokenType('*', '*');

  /// TokenType `~`
  static const TokenType tilde = const TokenType('~', '~');

  /// TokenType `;`
  static const TokenType semicolon = const TokenType(';', ';');

  /// TokenType `.`
  static const TokenType dot = const TokenType('.', r'\.(?!\d)', true);

  /// TokenType `auto`
  static const TokenType kw_auto = const TokenType('auto', r'auto\b', true);

  /// TokenType `break`
  static const TokenType kw_break = const TokenType('break', r'break\b', true);

  /// TokenType `case`
  static const TokenType kw_case = const TokenType('case', r'case\b', true);

  /// TokenType `const`
  static const TokenType kw_const = const TokenType('const', r'const\b', true);

  /// TokenType `continue`
  static const TokenType kw_continue =
      const TokenType('continue', r'continue\b', true);

  /// TokenType `default`
  static const TokenType kw_default =
      const TokenType('default', r'default\b', true);

  /// TokenType `do`
  static const TokenType kw_do = const TokenType('do', r'do\b', true);

  /// TokenType `else`
  static const TokenType kw_else = const TokenType('else', r'else\b', true);

  /// TokenType `enum`
  static const TokenType kw_enum = const TokenType('enum', r'enum\b', true);

  /// TokenType `extern`
  static const TokenType kw_extern =
      const TokenType('extern', r'extern\b', true);

  /// TokenType `for`
  static const TokenType kw_for = const TokenType('for', r'for\b', true);

  /// TokenType `goto`
  static const TokenType kw_goto = const TokenType('goto', r'goto\b', true);

  /// TokenType `if`
  static const TokenType kw_if = const TokenType('if', r'if\b', true);

  /// TokenType `inline`
  static const TokenType kw_inline =
      const TokenType('inline', r'inline\b', true);

  /// TokenType `long`
  static const TokenType kw_long = const TokenType('long', r'long\b', true);

  /// TokenType `register`
  static const TokenType kw_register =
      const TokenType('register', r'register\b', true);

  /// TokenType `restrict`
  static const TokenType kw_restrict =
      const TokenType('restrict', r'restrict\b', true);

  /// TokenType `return`
  static const TokenType kw_return =
      const TokenType('return', r'return\b', true);

  /// TokenType `short`
  static const TokenType kw_short = const TokenType('short', r'short\b', true);

  /// TokenType `signed`
  static const TokenType kw_signed =
      const TokenType('signed', r'signed\b', true);

  /// TokenType `sizeof`
  static const TokenType kw_sizeof =
      const TokenType('sizeof', r'sizeof\b', true);

  /// TokenType `static`
  static const TokenType kw_static =
      const TokenType('static', r'static\b', true);

  /// TokenType `struct`
  static const TokenType kw_struct =
      const TokenType('struct', r'struct\b', true);

  /// TokenType `switch`
  static const TokenType kw_switch =
      const TokenType('switch', r'switch\b', true);

  /// TokenType `typedef`
  static const TokenType kw_typedef =
      const TokenType('typedef', r'typedef\b', true);

  /// TokenType `union`
  static const TokenType kw_union = const TokenType('union', r'union\b', true);

  /// TokenType `unsigned`
  static const TokenType kw_unsigned =
      const TokenType('unsigned', r'unsigned\b', true);

  /// TokenType `volatile`
  static const TokenType kw_volatile =
      const TokenType('volatile', r'volatile\b', true);

  /// TokenType `while`
  static const TokenType kw_while = const TokenType('while', r'while\b', true);

  /// TokenType `intLiteral`
  static const TokenType intLiteral = const TokenType(
      'int literal',
      r'''
        (?:
          0x([0-9a-f]+) #  1: hex
          |
          0([0-7]+)     #  2: octal
          |
          ([1-9]\d*)    #  3: decimal
        )
        (ul|lu|l|u)?    #  4: type hints
        (?!\.)          # NOT followed by a dot ( collision with float constants)
        \b
      ''',
      true,
      _intExtractor);

  /// TokenType `floatingLiteral`
  static const TokenType floatingLiteral = const TokenType(
      'floating literal',
      r'''
        (               #  1: significand and exponent
          (?:
            \d+\.?\d*   # -- whole-number with optional fractional part
            |
            \.\d+       # -- only fractional part
          )
          (?:
            e-?\d+
          )?            # -- exponent
        )
        (f|d)?          #  2: type hint
        (?!\w)
      ''',
      true,
      _floatingExtractor);

  /// TokenType `stringLiteral`
  static const TokenType stringLiteral = const TokenType(
      'string literal', r'"((?:\\.|[^"])*)"', true, _stringExtractor);

  /// TokenType `charLiteral`
  static const TokenType charLiteral = const TokenType(
      'charLiteral', r"'([^'\\]|\\[a-z0-9\\]+)'", true, _charExtractor);

  /// TokenType `name`
  static const TokenType identifier =
      const TokenType('identifier', r'[a-z_]\w*', true);

  /// A token with this type is emitted by [Scanner] to indicate that it has
  /// reached the end of the source code. This way you can always compare
  /// `token.type` to the expected type and don't have to care about derefencing
  /// that property on `null`.
  static const TokenType endOfFile = const TokenType('end of file', null);

  /// All static `TokenType`s. The elements are ordered putting more restrictive
  /// ones before others they collide with, e.g. the `++` token occurs before
  /// the `+` token.
  static const List<TokenType> values = const <TokenType>[
    ampamp,
    ampeq,
    amp,
    bangeq,
    bang,
    bareq,
    barbar,
    bar,
    careteq,
    caret,
    colon,
    comma,
    diveq,
    div,
    eqeq,
    eq,
    gteq,
    gtgteq,
    gtgt,
    gt,
    lbracket,
    lcbracket,
    lsbracket,
    lteq,
    ltlteq,
    ltlt,
    lt,
    minuseq,
    minusgt,
    minusminus,
    minus,
    percenteq,
    percent,
    pluseq,
    plusplus,
    plus,
    questionmark,
    rbracket,
    rcbracket,
    rsbracket,
    stareq,
    star,
    tilde,
    semicolon,
    dot,
    kw_auto,
    kw_break,
    kw_case,
    kw_const,
    kw_continue,
    kw_default,
    kw_do,
    kw_else,
    kw_enum,
    kw_extern,
    kw_for,
    kw_goto,
    kw_if,
    kw_inline,
    kw_long,
    kw_register,
    kw_restrict,
    kw_return,
    kw_short,
    kw_signed,
    kw_sizeof,
    kw_static,
    kw_struct,
    kw_switch,
    kw_typedef,
    kw_union,
    kw_unsigned,
    kw_volatile,
    kw_while,
    intLiteral,
    floatingLiteral,
    stringLiteral,
    charLiteral,
    identifier,
  ];

  String toString() => "TokenType('$name')";
}

/// A token encapsulates the occurence of a [TokenType] in a parsed source code.
class Token {
  final TokenType type;

  /// The value that was extracted from the matched code using the TokenTypes
  /// valueExtractor. In most cases, this will be a plain string.
  final value;

  /// The original string.
  final FileSpan source;

  Token(this.type, this.value, this.source);

  String toString() => 'Token(type=`${type.name}`, value=`$value`, '
      'at ${source.start.line}:${source.start.column})';
}

/// This class processes raw C source code and turns it into a [Token] stream.
/// It can't handle malformed code and will abort by throwing
/// [UnrecognizedSourceCodeException] if it doesn't match any token pattern.
/// However, tokenization is performed lazy, so the exception won't be thrown
/// until you reach the broken position.
class Scanner extends PeekIterator<Token> {
  static final _whitespacePattern = new RegExp(r'\s+');

  /// Create a new [Scanner] for `source`.
  Scanner(SourceFile source)
      : super.fromIterable(() sync* {
          var offset = 0;
          var text = source.getText(0);

          while (offset < source.length) {
            var match = _whitespacePattern.matchAsPrefix(text, offset);
            if (match != null) {
              offset = match.end;
              continue;
            }

            var tokenType = TokenType.values.firstWhere(
                (TokenType t) =>
                    (match = t.pattern.matchAsPrefix(text, offset)) != null,
                orElse: () => throw new UnrecognizedSourceCodeException(
                    "Couldn't match the source against any pattern",
                    source.location(offset)));
            var value;
            try {
              value = tokenType.valueExtractor(match);
            } catch (e) {
              if (e is UnrecognizedSourceCodeException)
                e.location = source.location(offset);
              throw e;
            }

            yield new Token(tokenType, value, source.span(offset, match.end));
            offset = match.end;
          }
          yield new Token(TokenType.endOfFile, null, null);
        }());

  /// Return `current` and forward the Scanner by one token.
  ///
  /// If `expected` is not null and doesn't contain `current.type`, throw
  /// [UnexpectedTokenException].
  Token consume([List<TokenType> expected]) {
    if (expected != null) _assertTypeMatchesExpected(current, expected);
    var curr = current;
    moveNext();
    return curr;
  }

  /// If `current.type` is one of `expected`, return `current` and forward the
  /// Scanner by one token. Else return `null`.
  Token consumeIfMatches(List<TokenType> expected) {
    if (!expected.contains(current)) return null;
    var curr = current;
    moveNext();
    return curr;
  }

  /// Return [current] if its type is one of `expected`, or throw
  /// [UnexpectedTokenException].
  Token requireCurrent(List<TokenType> expected) {
    _assertTypeMatchesExpected(current, expected);
    return current;
  }

  /// Return [next] if its type is one of `expected`, or throw
  /// [UnexpectedTokenException].
  Token requireNext(List<TokenType> expected) {
    _assertTypeMatchesExpected(next, expected);
    return next;
  }

  /// Return `true` if the type of [current] is one of `expected`.
  bool checkCurrent(List<TokenType> expected) =>
      expected.contains(current.type);

  /// Return `true` if the type of [next] is one of `expected`.
  bool checkNext(List<TokenType> expected) => expected.contains(next.type);

  /// Throw an [UnexpectedTokenException] if `token` is null or its type
  /// doesn't match the `expected` ones.
  void _assertTypeMatchesExpected(Token token, List<TokenType> expected) {
    if (token == null)
      throw new UnexpectedTokenException('Tokens exhausted', null);
    if (!expected.contains(token.type))
      throw new UnexpectedTokenException(
          'Expected one of $expected, but found ${token.type}', token);
  }
}

/// Thrown during tokenization if the current input doesn't match any pattern.
class UnrecognizedSourceCodeException implements Exception {
  String message;
  FileLocation location;
  UnrecognizedSourceCodeException(this.message, this.location);
}

/// Thrown during parsing if [token] can't be processed at this point.
class UnexpectedTokenException implements Exception {
  String message;
  Token token;
  UnexpectedTokenException(this.message, this.token);
}
