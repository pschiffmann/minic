import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:minic/src/ast.dart';
import 'package:minic/src/parser.dart';
import 'package:minic/src/scanner.dart';

void main() {
  group('Parser parses single', () {
    addMainAndParse(code) => new Parser(
        new Scanner(new SourceFile(code +
            '''
              int main() {
                return 0;
              }
            ''')),
        4)..parse();

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
  });
}
