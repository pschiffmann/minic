library minic.src.parser;

import 'language.dart';
import 'token.dart';
import 'expression.dart';
import 'scope.dart';
import 'statement.dart';
import 'exception.dart';

/// This class controls parsing of a source code string into an AST.
///
/// To parse a source code string, create a [TokenIterator] from it and pass it
/// to [parse].
class Parser {
  /// The tokens processed during parsing.
  ///
  /// When a `parse*` method is called, [tokens.current] always contains the
  /// first token it should process.
  TokenIterator tokens;

  /// The current context in which identifiers are looked up.
  ///
  /// `parse*` methods may replace this variable as needed. The caller of these
  /// methods is responsible of backing up the previous value and restoring it
  /// afterwards.
  Scope currentScope;

  /// Parse [tokens] and return a [Scope] with all built definitions.
  Scope parse(TokenIterator tokens) {
    this.tokens = tokens;
    currentScope = new Scope();
    for (var builtin in compilerBuiltins) {
      currentScope.define(builtin);
    }
    parseNamespace();
    return currentScope;
  }

  /// Parse namespace-level definitions into [currentScope].
  void parseNamespace() {
    while (tokens.current.type != TokenType.endOfFile) {
      // Decide what we're parsing based on the current token. We expect one of
      // the following pattern:
      //   typedef:  typedef [ <name> | struct <namespace> ] <name>
      //   struct:   struct <name> <namespace>
      //   variable: <type> <identifier> [ = <expression> ] ;
      //   function: <type> <identifier> (<argument list>) <compound statement>
      switch (tokens.current.type) {
        case TokenType.stmtTypedef:
          throw new UnimplementedError();
        case TokenType.stmtStruct:
          throw new UnimplementedError();
        case TokenType.constAttr:
        case TokenType.name:
          // Parse optional `const`
          var isConst = tokens.current.type == TokenType.constAttr;
          // Parse variable or return type
          var t = currentScope.lookUp(tokens.consume(TokenType.name).value);
          if (t is! CType) throw new UnexpectedTokenException(
              'Expected type name', tokens.current);
          // Parse <identifier>
          var identifier = tokens.consume(TokenType.name);
          try {
            // TODO: handle function overloading
            currentScope.lookUp(identifier.value);
            throw new UnexpectedTokenException(
                'Name already defined', identifier);
          } catch (UndefinedNameException) {}
          // Decide whether we parse a variable or function definition
          var variableOrFunction = tokens
              .consume([TokenType.eq, TokenType.semicolon, TokenType.lbracket]);
          if (variableOrFunction.type ==
              TokenType.lbracket) parseFunctionDefinition(
              isConst, t, identifier);
          else parseGlobalVariable(isConst, t, identifier);
          break;
        default:
          throw new UnexpectedTokenException(
              'Invalid token in namespace scope', tokens.current);
      }
    }
  }

  /// Parse [tokens] as a global variable and add it to [currentScope].
  ///
  /// When this method is called, [tokens.current] must be of type
  /// [TokenType.eq] or [TokenType.semicolon].
  void parseGlobalVariable(bool isConst, CType variableType, Token identifier) {
    var variable = new Variable(identifier, variableType, isConst: isConst);
    if (tokens.current.type == TokenType.eq) {
      var eq = tokens.current;
      tokens.moveNext();
      var initializer = new InfixOperator(
          eq, new Name(identifier), parseExpression(precedenceAssignment - 1));
      currentScope.initializers.add(new ExpressionStatement(initializer));
    }
    currentScope.define(variable);
    tokens.moveNext();
  }

  /// Parse [tokens] as a function definition and add it to [currentScope].
  ///
  /// When this method is called, [tokens.current] must be of type
  /// [TokenType.lbracket].
  void parseFunctionDefinition(
      bool isConst, CType returnType, Token identifier) {}

  Variable parseVariableDeclaration() {
    var isConst = false;
    if (tokens.current.type == TokenType.constAttr) {
      isConst = true;
      tokens.moveNext();
    }
    var identifier = tokens.checkCurrent(TokenType.name);
    var variableType = tokens.consume(TokenType.name);
    return new Variable(identifier, variableType, isConst: isConst);
  }

  ///
  Statement parseStatement() {
    return null;
  }

  ///
  CompoundStatement parseCompoundStatement() {
    currentScope = new Scope(currentScope);
    var children = [];
    try {
      while (children.add(parseStatement()));
    } catch (Exception) {}
    return new CompoundStatement(currentScope, children);
  }

  /// Parse the current tokens into an [Expression].
  ///
  /// The `precedence` parameter is used by [PrefixParselet] and [InfixParselet]
  /// and controls the binding of the parsed tokens to its left and right side.
  /// For example, if we parse `x - y * z` and the subtract and multiply
  /// operators have a precedence of 11 and 12, `y` will bind to multiplication
  /// because it has the higher precedence.
  Expression parseExpression([int precedence = 0]) {
    var parselet = prefixParselets[tokens.next?.type];
    if (parselet ==
        null) throw new UnexpectedTokenException('', tokens.current);

    tokens.moveNext();
    var left = parselet.parse(this);

    while ((parselet = infixParselets[tokens.next?.type]) != null &&
        precedence < parselet.precedence) {
      tokens.moveNext();
      left = parselet.parse(this, left);
    }

    return left;
  }
}
