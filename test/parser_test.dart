import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:minic/src/ast.dart';
import 'package:minic/src/parser.dart';
import 'package:minic/src/scanner.dart';

addMainAndParse(code) => new Parser(
    new Scanner(new SourceFile(code +
        '''
          int main() {
            return 0;
          }
        ''')),
    4)..parse();

void main() {
  group('Parser parses a single', () {
    test('dummy `main` function', () {
      var parser = addMainAndParse('');
      expect(parser.namespace.lookUp('main'),
          new isInstanceOf<FunctionDefinition>());
    });

    test('global variable', () {
      var parser = addMainAndParse('int x;');
      var variable = parser.namespace.lookUp('x');
      expect(variable, new isInstanceOf<Variable>());
      expect((variable as Variable).variableType,
          equals(parser.namespace.lookUp('int')));
    });

    test('global variable with initializer', () {
      var parser = addMainAndParse('int x = 5;');
      var variable = parser.namespace.lookUp('x');
      expect(variable, new isInstanceOf<Variable>());
      expect(variable.initializer.value, equals(5));
    });

    test('local variable', () {
      var parser = addMainAndParse('void f() { int y; }');
      var variable = parser.namespace.lookUp(('f')).body.lookUp('y');
      expect(variable, new isInstanceOf<Variable>());
    });

    test('local variable with initializer', () {
      var parser = addMainAndParse('void f() { int y = 5; }');
      var variable = parser.namespace.lookUp(('f')).body.lookUp('y');
      expect(variable, new isInstanceOf<Variable>());
      var expression =
          parser.namespace.lookUp(('f')).body.statements.first.expression;
      expect(expression, new isInstanceOf<AssignmentExpression>());
    });

    test('integer literal', () {
      var parser = addMainAndParse('void f() { 42; }');
      var expression =
          parser.namespace.lookUp('f').body.statements.first.expression;
      expect(expression, new isInstanceOf<NumberLiteralExpression>());
      expect(expression.type, equals(basicTypes['int']));
      expect(expression.value, equals(42));
    });

    test('floating point literal', () {
      var parser = addMainAndParse('void f() { .5; }');
      var expression =
          parser.namespace.lookUp('f').body.statements.first.expression;
      expect(expression, new isInstanceOf<NumberLiteralExpression>());
      expect(expression.type, equals(basicTypes['double']));
      expect(expression.value, equals(0.5));
    });

    test('char literal', () {
      var parser = addMainAndParse("void f() { 'b'; }");
      var expression =
          parser.namespace.lookUp('f').body.statements.first.expression;
      expect(expression, new isInstanceOf<NumberLiteralExpression>());
      expect(expression.type, equals(basicTypes['char']));
      expect(expression.value, equals(98));
    });
  });

  group('Parsing statement', () {
    group('[GotoStatement]:', () {
      test('label before statement can be parsed', () {
        var parser = addMainAndParse('''void f() {
            a: goto a;
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect((statement as GotoStatement).targetStatement, equals(statement));
      });

      test('statement before label can be parsed', () {
        var parser = addMainAndParse('''void f() {
            goto a;
            a: return;
          }''');
        var statements = parser.namespace.lookUp('f').body.statements;
        expect((statements[0] as GotoStatement).targetStatement,
            equals(statements[1]));
      });

      test('missing target can be detected', () {
        expect(() => addMainAndParse('''void f() {
            goto a;
          }'''), throwsA(const isInstanceOf<LanguageViolationException>()));
      });
    });
  });
}
