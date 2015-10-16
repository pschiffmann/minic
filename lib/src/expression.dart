library minic.src.expression;

import 'language.dart';
import 'token.dart';
import 'parser.dart' show Parser;

/// Parselets
///
/// Parselets parse part of an expression, mostly a single operator.

/// Parses the beginning of an expression, like prefix operators or variables.
abstract class PrefixParselet {
  const PrefixParselet();
  Expression parse(Parser parser);
}

/// Parses a name, like a variable or type name.
class NameParselet extends PrefixParselet {
  const NameParselet();

  Expression parse(Parser parser) {
    return new Name(parser.tokens.current);
  }
}

/// Parses a prefix operator like `++`, `!` or `throw`.
class PrefixOperatorParselet extends PrefixParselet {
  final int precedence;
  const PrefixOperatorParselet(this.precedence);

  Expression parse(Parser parser) {
    // All prefix operators are right-to-left associative, so use reduced
    // precedence for the call to `parseExpression()`.
    return new PrefixOperator(
        parser.tokens.current, parser.parseExpression(precedence - 1));
  }
}

/// Parses every expression that requires a left hand side, including infix and
/// postfix operators, function calls, and ternary operator.
abstract class InfixParselet {
  final int precedence;
  const InfixParselet(this.precedence);

  Expression parse(Parser parser, Expression left);
}

/// Parses postfix operators `++` and `--`.
class PostfixOperatorParselet extends InfixParselet {
  const PostfixOperatorParselet(precedence) : super(precedence);

  Expression parse(Parser parser, Expression lhs) {
    return new PostfixOperator(parser.tokens.current, lhs);
  }
}

/// Parses infix operators like `+` and `=`.
class InfixOperatorParselet extends InfixParselet {
  // Assignment is right-to-left associative.
  final int rightPrecedence;
  const InfixOperatorParselet(precedence, {rightAssociative: false})
      : super(precedence),
        rightPrecedence = precedence - (rightAssociative ? 1 : 0);

  Expression parse(Parser parser, Expression lhs) {
    var token = parser.tokens.current;
    return new InfixOperator(
        token, lhs, parser.parseExpression(rightPrecedence));
  }
}

/// Parses the ternary operator `?:`.
class TernaryOperatorParselet extends InfixParselet {
  const TernaryOperatorParselet() : super(precedenceAssignment - 1);

  Expression parse(Parser parser, Expression lhs) {
    var ifBranch = parser.parseExpression(precedence);
    parser.tokens.consume(TokenType.colon);
    var elseBranch = parser.parseExpression(precedence);
    return new TernaryOperator(lhs, ifBranch, elseBranch);
  }
}

/// Parses the function call operator `()`
class CallOperatorParselet extends InfixParselet {
  const CallOperatorParselet() : super(precedenceSuffix);

  Expression parse(Parser parser, Expression lhs) {
    var args = [];
    while (parser.tokens.next.type != TokenType.rbracket) {
      args.add(parser.parseExpression());
      if (parser.tokens.next?.type != TokenType.comma) break;
      parser.tokens.consume(TokenType.comma);
    }
    parser.tokens.consume(TokenType.rbracket);
    return new CallOperator(lhs, args);
  }
}

/// Parses the subscript operator `[]`
class SubscriptOperatorParselet extends InfixParselet {
  const SubscriptOperatorParselet() : super(precedenceSuffix);

  Expression parse(Parser parser, Expression lhs) {
    var index = parser.parseExpression();
    parser.tokens.consume(TokenType.rsbracket);
    return new SubscriptOperator(lhs, index);
  }
}

/// Expressions
///
///
///
abstract class Expression {}

/// Represents a variable, function, ...
class Name implements Expression {
  Token name;

  bool get isLValue => true;
  bool get isConst => true;
  Name(this.name);
}

/*enum LiteralType {
  intLiteral,
  floatLiteral,
  stringLiteral,
  charLiteral
  // bool, null?
}
*/
class Literal implements Expression {
  Token value;

  Literal(this.value);
}

class PrefixOperator implements Expression {
  Token op;
  Expression rhs;

  PrefixOperator(this.op, this.rhs);
}

class PostfixOperator implements Expression {
  Token op;
  Expression lhs;

  PostfixOperator(this.op, this.lhs);
}

class InfixOperator implements Expression {
  Expression lhs;
  Expression rhs;
  Token op;

  InfixOperator(this.op, this.lhs, this.rhs);
}

class TernaryOperator implements Expression {
  Expression condition;
  Expression ifBranch;
  Expression elseBranch;

  TernaryOperator(this.condition, this.ifBranch, this.elseBranch);
}

class CallOperator implements Expression {
  Expression callee;
  List<Expression> arguments;

  CallOperator(this.callee, this.arguments);
}

class SubscriptOperator implements Expression {
  Expression callee;
  Expression index;

  SubscriptOperator(this.callee, this.index);
}
