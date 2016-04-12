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

    group('[CompoundStatement]:', () {
      test('empty brackets', () {
        var parser = addMainAndParse('''void f() {
            {}
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(statement, const isInstanceOf<CompoundStatement>());
      });

      test('adds definitions to self', () {
        var parser = addMainAndParse('''void f() {
            {
              int x;
            }
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(statement.definitions.containsKey('x'), isTrue);
      });

      test('adds statements to self', () {
        var parser = addMainAndParse('''void f() {
            {
              return;
            }
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(
            statement.statements.first, const isInstanceOf<ReturnStatement>());
      });
    });

    group('[ReturnStatement]:', () {
      test('void return value, empty return expression', () {
        var parser = addMainAndParse('''void f() {
            return;
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(statement, const isInstanceOf<ReturnStatement>());
      });

      test('non-void return value, matching return expression', () {
        var parser = addMainAndParse('''int f() {
            return 1;
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(statement.expression,
            const isInstanceOf<NumberLiteralExpression>());
      });

      test('detects void return value, empty return expression', () {
        var parser = addMainAndParse('''void f() {
            return;
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(statement, const isInstanceOf<ReturnStatement>());
      });
    });

    group('[ExpressionStatement]:', () {
      test('contains expression', () {
        var parser = addMainAndParse('''void f() {
            42;
          }''');
        var statement = parser.namespace.lookUp('f').body.statements.first;
        expect(statement, const isInstanceOf<ExpressionStatement>());
        expect(statement.expression, const isInstanceOf<Expression>());
      });
    });

    group('[ExpressionStatement] with local variable:', () {
      test('single variable is added to scope', () {
        var parser = addMainAndParse('''void f() {
            int x;
          }''');
        var functionBody = parser.namespace.lookUp('f').body;
        expect(functionBody.lookUp('x'), const isInstanceOf<Variable>());
        expect(functionBody.statements, isEmpty);
      });

      test('single variable is added to scope, initializer to statements', () {
        var parser = addMainAndParse('''void f() {
            int x = 0;
          }''');
        var functionBody = parser.namespace.lookUp('f').body;
        expect(functionBody.lookUp('x'), const isInstanceOf<Variable>());
        expect(functionBody.statements.first,
            const isInstanceOf<ExpressionStatement>());
        expect(functionBody.statements.first.expression,
            const isInstanceOf<AssignmentExpression>());
      });

      test('multiple variables with and without initializer', () {
        var parser = addMainAndParse('''void f() {
            int x = 0, y, z = 1;
          }''');
        var functionBody = parser.namespace.lookUp('f').body;
        var x = functionBody.lookUp('x');
        var y = functionBody.lookUp('y');
        var z = functionBody.lookUp('z');
        expect(x, const isInstanceOf<Variable>());
        expect(y, const isInstanceOf<Variable>());
        expect(z, const isInstanceOf<Variable>());
        expect(functionBody.statements[0].expression.left.variable, equals(x));
        expect(functionBody.statements[0].expression.left.variable, equals(z));
      }, skip: 'not implemented');

      test('multiple variables with and without pointer type', () {
        var parser = addMainAndParse('''void f() {
            int a = 1, *b;
            int c* = 0, d;
          }''');
        var functionBody = parser.namespace.lookUp('f').body;
        var a = functionBody.lookUp('a');
        var b = functionBody.lookUp('b');
        var c = functionBody.lookUp('c');
        var d = functionBody.lookUp('d');
        expect(a.variableType, const isInstanceOf<BasicType>());
        expect(b.variableType, const isInstanceOf<PointerType>());
        expect(c.variableType, const isInstanceOf<PointerType>());
        expect(d.variableType, const isInstanceOf<BasicType>());
      }, skip: 'not implemented');
    });
  });
}
