import 'package:test/test.dart';
import 'package:minic/src/scanner.dart';
import 'dart:math' show Point;

void main() {
  group('TokenType.values', () {
    // http://en.cppreference.com/w/c/language/operator_precedence
    var operators = '''
      ++ -- ( ) [ ] . ->
      ! ~ sizeof
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
    '''.trim();

    // http://en.cppreference.com/w/c/keyword
    var keywords = '''
      auto
      break
      case const continue
      default do
      else enum extern
      for
      goto
      if
      long
      register return
      short signed static struct switch
      typedef
      union unsigned
      void volatile
      while
    '''.trim();
    var builtinNames = 'char double float int';

    test('covers all C operators', () {
      var it = new Scanner(operators);
      for (var expectedMatch in operators.split(new RegExp(r'\s+'))) {
        it.moveNext();
        // Correct substring matched?
        expect(it.current.value, equals(expectedMatch));
        // Matched by correct pattern?
        expect(it.current.type, equals(TokenType.values[expectedMatch]));
      }
    });

    test('covers all C keywords (pre C99)', () {
      var it = new Scanner(keywords);
      for (var expectedMatch in keywords.split(new RegExp(r'\s+'))) {
        it.moveNext();
        // Correct substring matched?
        expect(it.current.value, equals(expectedMatch));
        // Matched by correct pattern?
        expect(it.current.type, equals(TokenType.values[expectedMatch]));
      }

      it = new Scanner(builtinNames);
      for (var expectedMatch in builtinNames.split(new RegExp(r'\s+'))) {
        it.moveNext();
        // Correct substring matched?
        expect(it.current.value, equals(expectedMatch));
        // Matched by correct pattern?
        expect(it.current.type, equals(TokenType.values['name']));
      }
    });

    test('matches literals', () {
      var it = new Scanner('''
        42 052 0x2a 0X2A
        123.456e-67 .1E4f 58. 4e2
        \'c\'
        "hello world"
      ''');

      for (var literal in [
        '42',
        '052',
        '0x2a',
        '0X2A',
        '123.456e-67',
        '.1E4f',
        '58.',
        '4e2'
      ]) {
        it.moveNext();
        expect(it.current.value, equals(literal));
        expect(it.current.type, equals(TokenType.values['numberLiteral']));
      }
      it.moveNext();
      expect(it.current.value, equals("'c'"));
      expect(it.current.type, equals(TokenType.values['charLiteral']));
      it.moveNext();
      expect(it.current.value, equals('"hello world"'));
      expect(it.current.type, equals(TokenType.values['stringLiteral']));
    });

    test("doesn't recognize undefined stuff", () {
      var allRecognizedTokenTypes = new List.from(TokenType.values.values);
      var allInputs = [
        operators,
        keywords,
        '4',
        '"example string"',
        "'c'",
        'example_name'
      ].join(" ");
      var it = new Scanner(allInputs);
      while (it.moveNext() && it.current.type != TokenType.endOfFile) {
        expect(allRecognizedTokenTypes.remove(it.current.type), equals(true),
            reason: "`${it.current.type.name}` has matched twice");
      }
      expect(allRecognizedTokenTypes, equals([]));
    });
  });

  group('Scanner', () {
    test('recognizes correct token positions', () {
      var scanner = new Scanner('''
first second
  third
fourth fifth'''
      );
      var expected = [
            new Token(null, 'first', new Point(0, 0)),
            new Token(null, 'second', new Point(6, 0)),
            new Token(null, 'third', new Point(3, 1)),
            new Token(null, 'fourth', new Point(0, 2)),
            new Token(null, 'fifth', new Point(7, 2)),
            new Token(null, null, new Point(12, 2))
          ];
      while (scanner.moveNext()) {
        expect(scanner.current.value, equals(expected.first.value));
        expect(scanner.current.position, equals(expected.first.position));
        expected.removeAt(0);
      }
    });
  });
}
