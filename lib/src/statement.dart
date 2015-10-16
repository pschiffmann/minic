library minic.src.statement;

import 'scope.dart';
import 'expression.dart';

class StatementParser {}

class Statement {
  /// String or null
  var label;
}

class ExpressionStatement {
  Expression expression;
  ExpressionStatement(this.expression);
}

class CompoundStatement extends Statement {
  Scope localScope;
  List<Statement> statements;

  CompoundStatement(this.localScope, this.statements);
}
