import 'dart:convert' show UTF8;
import 'package:test/test.dart';
import 'package:minic/scanner.dart';
import 'package:minic/memory.dart';
import 'package:source_span/source_span.dart';

void main() {
  group('Scanner', () {
    test("matches only language terminals", () {
      // http://en.cppreference.com/w/c/language/operator_precedence
      var operators = '''
        ++ -- ( ) [ ] . ->
        ++ -- + - ! ~ * & sizeof
        * / %
        + -
        << >>
        < <= > >=
        == !=
        &
        ^
        |
        &&
        ||
        ? :
        = += -= *= /= %= <<= >>= &= ^= |=
        ,
        { } ;
      '''
          .trim()
          .split(new RegExp(r'\s+'));

      // http://en.cppreference.com/w/c/keyword
      var keywordsExceptTypenames = '''
        auto
        break
        case const continue
        default do
        else enum extern
        for
        goto
        if inline
        long
        register restrict return
        short signed sizeof static struct switch
        typedef
        union unsigned
        volatile
        while
      '''
          .trim()
          .split(new RegExp(r'\s'));
      var exampleLiterals = [
        '4',
        '4.',
        "'c'",
        '"example string"',
        'example_name'
      ];
      var allTerminalTypesWithoutDuplicates = (new Set()
            ..addAll(operators)
            ..addAll(keywordsExceptTypenames)
            ..addAll(exampleLiterals))
          .join(' ');

      // GIVEN a source code that contains all different types of tokens
      var source = new SourceFile(allTerminalTypesWithoutDuplicates);
      // WHEN I scan it into tokens
      var scanner = new Scanner(source);
      var tokens = [];
      while (scanner.moveNext()) tokens.add(scanner.current);
      tokens.removeLast();
      // THEN every token `TokenType` has matched once
      expect(tokens.length, equals(TokenType.values.length));
      expect(new Set.from(tokens.map((t) => t.type)),
          equals(new Set.from(TokenType.values)));
    });

    test('`stringLiteral` extracts correct value', () {
      var source, token;

      // GIVEN a source `"foo"`
      source = new SourceFile('"foo"');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the value `foo` without quotes is extracted
      expect(token.value, equals(UTF8.encode('foo')));

      // GIVEN a source `"\""`
      source = new SourceFile(r'"\""');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the value `"` extracted, recognizing the escaped backslash
      expect(token.value, equals(UTF8.encode('"')));

      // GIVEN a source `"\\\\\x41\n\u03b1"`
      source = new SourceFile(r'"\\\\\x41\n\u03b1"');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the escaped values (__two backslashes, ASCII uppercase `A`,
      //  linebreak, lowercase alpha__) are extracted
      expect(token.value, equals(UTF8.encode(r'\\A' + '\nα')));
    });

    test('extract character literals', () {
      // GIVEN a source `'a'`
      var source = new SourceFile("'a'");
      // WHEN that source is tokenized
      var token = (new Scanner(source)..moveNext()).current;
      // THEN the value `a` without quotes is extracted
      expect(token.value, equals(97));
    });

    test('extract int literals', () {
      var source, token;

      // GIVEN the literal `0ul`
      source = new SourceFile('0ul');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the decimal number 0 of type `unsigned long` is extracted
      expect(token.value, equals({'value': 0, 'type': NumberType.uint64}));

      // GIVEN the literal `42`
      source = new SourceFile('42');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the decimal number 42 of type `signed int` is extracted
      expect(token.value, equals({'value': 42, 'type': NumberType.sint32}));

      // GIVEN the literal `052`
      source = new SourceFile('052');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the octal number 52 (decimal 42) of type `signed int` is extracted
      expect(token.value, equals({'value': 42, 'type': NumberType.sint32}));

      // GIVEN the literal `0x2a`
      source = new SourceFile('0x2a');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the hex number 0x2a (decimal 42) is extracted
      expect(token.value, equals({'value': 42, 'type': NumberType.sint32}));
    });

    test('extract floating literals', () {
      var source, token;

      // GIVEN the literal `123.456e-67`
      source = new SourceFile('123.456e-67');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the floating point number 123.456e-67 is extracted
      expect(
          token.value, equals({'value': 123.456e-67, 'type': NumberType.fp64}));

      // GIVEN the literal `.1E4f`
      source = new SourceFile('.1E4f');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the floating point number 0.1e4 of type float is extracted
      expect(token.value, equals({'value': .1e4, 'type': NumberType.fp32}));

      // GIVEN the literal `58.`
      source = new SourceFile('58.');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the floating point number 58 is extracted
      expect(token.value, equals({'value': 58.0, 'type': NumberType.fp64}));

      // GIVEN the literal `4e2d`
      source = new SourceFile('4e2d');
      // WHEN that source is tokenized
      token = (new Scanner(source)..moveNext()).current;
      // THEN the floating point number 4e2 of type double is extracted
      expect(token.value, equals({'value': 4e2, 'type': NumberType.fp64}));
    });
  });
}
