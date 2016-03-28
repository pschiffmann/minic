/// Parsing describes the process of constructing an abstract syntax tree from a
/// plain string input. This task is done by [Parser], which works on a
/// [Scanner] as input and creates an [AstNode] tree from it.
///
/// [Definition]s and [Statement]s are parsed with a [recursive descent][1]
/// approach. That means that parsing of each of these types is implemented in
/// a separate method. These methods call each other recursively to resolve
/// nested structures. Each method validates the AST nodes it builds before
/// returning.
/// To deal with operator precedence, [Expression]s are parsed using a
/// [Pratt parser][2]. Read the linked article for an excellent explanation.
/// Both parts are implemented in the [Parser] class.
///
/// To use the parser, simply instantiate it and call `parse`. All other
/// methods, despite being public, are considered internal API.
///
/// [1]: https://en.wikipedia.org/wiki/Recursive_descent_parser
/// [2]: http://journal.stuffwithstuff.com/2011/03/19/pratt-parsers-expression-parsing-made-easy/
library minic.src.parser;

import 'ast.dart';
import 'scanner.dart';
import 'memory.dart' show NumberType;

/// Default predefined types and functions available for use in the program.
/// This includes the basic types, `malloc`, or `printf`.
List<Definition> basicTypes = <Definition>[
  new BasicType('char', NumberType.sint8),
  new BasicType('short', NumberType.sint16),
  new BasicType('int', NumberType.sint32),
  new BasicType('long', NumberType.sint64),
  new BasicType('float', NumberType.fp32),
  new BasicType('double', NumberType.fp64),
  new VoidType()
];

BasicType getVariableTypeForNumberType(NumberType numberType) =>
    basicTypes.firstWhere((t) => (t as BasicType)?.numberType == numberType);

Map<TokenType, PrefixParselet> prefixParselets = <TokenType, PrefixParselet>{
  TokenType.intLiteral: const IntegerParselet()
};
Map<TokenType, InfixParselet> infixParselets = {};

/// Callback function that establishes the child relation between a [Statement]
/// node and its parent. Return the parent node.
typedef AstNode linkToParent(AstNode child);

/// This class controls the parsing process of a source code into an AST.
///
/// To use it, you need to create a new parser, then call [parse] on it. That
/// method will fill the `namespace` property.
class Parser {
  /// The source code processed during parsing.
  ///
  /// When a `parse*` method is called, [_scanner.current] contains the first
  /// token it should process.
  Scanner scanner;

  /// The root of the parsed AST. This property is `null` until you call
  /// [parse].
  Namespace namespace;

  /// The size in bytes of pointer types, aka `sizeof(size_t)` or
  /// `sizeof(intptr_t)`.
  int pointerSize;

  /// The current context in which identifiers are looked up.
  ///
  /// `parse*` methods may replace this variable as needed. If a method does,
  /// it must back up the current value and restore it before returning.
  Scope currentScope;

  /// The function currently being parsed, or `null`.
  FunctionDefinition get function => currentScope.parents
      .firstWhere((node) => node is FunctionDefinition, orElse: () => null);

  Parser(this.scanner, this.pointerSize);

  /// Start the parsing process.
  ///
  /// This method will create the AST only on the first call; Subsequent calls
  /// don't change the state of this object.
  ///
  /// Throws the following exceptions:
  ///   * [UnrecognizedSourceCodeException] on ...
  void parse() {
    if (namespace != null) return;

    currentScope = new Namespace();
    for (var definition in basicTypes) {
      currentScope.define(definition);
    }

    scanner.moveNext();
    while (!scanner.checkCurrent([TokenType.endOfFile])) {
      parseNamespaceDefinition();
    }

    var main = currentScope.lookUp('main');
    if (main is! FunctionDefinition)
      throw new LanguageViolationException('`main` not found', null);
    if (main.returnValue != currentScope.lookUp('int'))
      throw new LanguageViolationException(
          '`main` must return `int`', main.functionName);
    if (!main.parameters.isEmpty)
      throw new LanguageViolationException(
          '`main` must not expect function arguments', main.functionName);

    namespace = currentScope;
    currentScope = null;
  }

  /// Parse a single namespace-level definition and add it to [currentScope].
  void parseNamespaceDefinition() {
    switch (scanner.current.type) {
      case TokenType.kw_const:
      case TokenType.identifier:
        var constToken = scanner.consumeIfMatches([TokenType.kw_const]);
        var type = parseType();
        if (scanner.checkNext([TokenType.lbracket]))
          parseFunctionDefinition(constToken, type);
        else
          parseGlobalVariable(constToken, type);
        break;
      case TokenType.kw_struct:
        throw new UnimplementedError(
            'The `struct` keyword is currently not supported.');
      case TokenType.kw_typedef:
        throw new UnimplementedError(
            'The `typedef` keyword is currently not supported.');
      case TokenType.kw_union:
        throw new UnimplementedError(
            'The `union` keyword is currently not supported.');
      default:
        throw new UnexpectedTokenException(
            'Invalid token on namespace level', scanner.current);
    }
  }

  /// Parse a function definition, then add it to [currentScope].
  void parseFunctionDefinition(Token constToken, VariableType returnValue) {
    var nameToken = scanner.consume([TokenType.identifier]);
    scanner.consume([TokenType.lbracket]);

    var parameters = <Variable>[];
    while (!scanner.checkCurrent([TokenType.rbracket])) {
      var parameterConst = scanner.consumeIfMatches([TokenType.kw_const]);
      var parameterType = parseType();
      var parameterName = scanner.consume([TokenType.identifier]);
      parameters.add(new Variable(
          constToken: parameterConst,
          variableTypeName: null,
          variableName: parameterName,
          variableType: parameterType,
          initializer: null));
      if (scanner.consumeIfMatches([TokenType.comma]) == null) break;
    }
    scanner.consume([TokenType.rbracket]);

    var function = new FunctionDefinition(
        functionName: nameToken,
        returnValue: returnValue,
        parameters: parameters);
    currentScope.define(function);
    parseCompoundStatement((stmt) => function..body = stmt,
        variables: parameters);
  }

  /// Parse definition and optional initializer expression of a global variable,
  /// then add it to [currentScope].
  void parseGlobalVariable(Token constToken, VariableType variableType) {
    var nameToken = scanner.consume([TokenType.identifier]);
    var initializer;
    if (scanner.checkCurrent([TokenType.eq])) {
      scanner.consume();
      initializer = parseExpression();
    }
    scanner.consume([TokenType.semicolon]);
    currentScope.define(new Variable(
        constToken: constToken,
        variableTypeName: null,
        variableName: nameToken,
        variableType: variableType,
        initializer: initializer));
  }

  /// Call any of the `parse*Statement` methods, depending on `scanner.current`.
  Statement parseStatement(linkToParent link) {
    var labels = parseLabels();
    switch (scanner.current.type) {
      case TokenType.lcbracket:
        return parseCompoundStatement(link, labels: labels);
      case TokenType.kw_return:
        return parseReturnStatement(link, labels);
      default:
        throw new UnexpectedTokenException(
            'Invalid token at the start of a statement', scanner.current);
    }
  }

  /// Parse and return a compound statement. Sets the newly created object as
  /// `currentScope`.
  ///
  /// If `variables` are passed, they are added to this scope. This is useful
  /// for function arguments.
  CompoundStatement parseCompoundStatement(linkToParent link,
      {Iterable<Label> labels: const <Label>[],
      Iterable<Definition> variables: const []}) {
    var openingBracket = scanner.consume([TokenType.lcbracket]);
    var parentScope = currentScope;
    var compoundStatement = currentScope =
        new CompoundStatement(openingBracket: openingBracket, labels: labels);

    compoundStatement.parent = link(compoundStatement);
    for (var variable in variables) {
      compoundStatement.define(variable);
    }

    while (!scanner.checkCurrent([TokenType.rcbracket])) {
      parseStatement((stmt) => compoundStatement..statements.add(stmt));
    }

    compoundStatement.closingBracket = scanner.consume([TokenType.rcbracket]);
    currentScope = parentScope;
    return compoundStatement;
  }

  /// Parse and return a return statement. Validate that the return value
  /// matches the type of the current function.
  ReturnStatement parseReturnStatement(linkToParent link, List<Label> labels) {
    var returnKeyword = scanner.consume([TokenType.kw_return]);
    var expression;
    if (!scanner.checkCurrent([TokenType.semicolon])) {
      expression = parseExpression();
      if (!expression.type.canBeConvertedTo(function.returnValue))
        throw new LanguageViolationException(
            'The value type of the `return` expression does not match the one of the enclosing function',
            returnKeyword);
    }
    scanner.consume([TokenType.semicolon]);
    return new ReturnStatement(
        returnKeyword: returnKeyword, expression: expression, labels: labels);
  }

  /// Parse `scanner.current` as expression.
  ///
  /// This method uses a Pratt parser approach (see library docs):
  /// The `precedence` parameter is used by [PrefixParselet] and [InfixParselet]
  /// and controls the binding of the parsed tokens to its left and right side.
  /// For example, if we parse `x - y * z` and the subtract and multiply
  /// operators have a precedence of 11 and 12, `y` will bind to multiplication
  /// because it has the higher precedence.
  Expression parseExpression([int precedence = 0]) {
    var parselet = prefixParselets[scanner.current.type];
    if (parselet == null)
      throw new UnexpectedTokenException(
          'Invalid start of expression', scanner.current);

    var left = parselet.parse(this);

    while ((parselet = infixParselets[scanner.current.type]) != null &&
        precedence < parselet.precedence) {
      left = parselet.parse(this, left);
    }

    return left;
  }

  /// Parse and return a [VariableType]. Throw `UnexpectedTokenException` if
  /// the current token is not an identifier.
  ///
  /// TODO: Handle `unsigned` etc tokens
  VariableType parseType() {
    var typeToken = scanner.consume([TokenType.identifier]);
    var type = currentScope.lookUp(typeToken.value);
    while (scanner.current.type == TokenType.star) {
      type = new PointerType(target: type, size: pointerSize);
      scanner.moveNext();
    }
    return type;
  }

  /// Parse and return a list of statement labels.
  ///
  /// Validate that all labels are unique inside the function scope, `case` and
  /// `default` labels only occur inside a [SwitchStatement], and `case` values
  /// match the type of one enclosing `switch`.
  List<Label> parseLabels() {
    var parsedLabels = <Label>[];
    var functionWideLabels =
        function.body.labeledStatements.expand((statement) => statement.labels);
    var switchStatements =
        currentScope.parents.where((node) => node is SwitchStatement);
    loop: while (true) {
      var label;
      var token = scanner.current;
      switch (scanner.current.type) {
        case TokenType.kw_case:
          scanner.consume();
          label = new CaseLabel(parseExpression());
          break;
        case TokenType.kw_default:
          label = const DefaultLabel();
          scanner.consume();
          break;
        case TokenType.identifier:
          if (!scanner.checkNext([TokenType.colon])) continue exit;
          label = new GotoLabel(scanner.consume().value);
          break;
        exit: default:
          return parsedLabels;
      }
      scanner.consume([TokenType.colon]);
      if (functionWideLabels.contains(label) || parsedLabels.contains(label))
        throw new LanguageViolationException(
            'Labels must be unique inside a function', token);
      if ((label is CaseLabel || label is DefaultLabel) &&
          switchStatements.isEmpty)
        throw new LanguageViolationException(
            '`case` and `default` labels must be nested inside a `switch` statement',
            token);
      if (label is CaseLabel &&
          !switchStatements.any(
              (SwitchStatement node) => node.value.type == label.value.type))
        throw new LanguageViolationException(
            'The type of `case` values must match the one of the surrounding '
            '`switch` statement expression',
            token);
    }
  }
}

/// Parses the beginning of an expression, like prefix operators or variables.
abstract class PrefixParselet {
  const PrefixParselet();
  Expression parse(Parser parser);
}

/// Parses every expression that requires a left hand side, including infix and
/// postfix operators, function calls, and ternary operator.
abstract class InfixParselet {
  final int precedence;
  const InfixParselet(this.precedence);

  Expression parse(Parser parser, Expression left);
}

/// Parses [TokenType.intLiteral] into an [IntegerLiteral].
class IntegerParselet extends PrefixParselet {
  const IntegerParselet();

  Expression parse(Parser parser) {
    var literalToken = parser.scanner.consume([TokenType.intLiteral]);
    return new IntegerLiteral(
        value: literalToken.value['value'],
        type: getVariableTypeForNumberType(literalToken.value['type']),
        literalToken: literalToken);
  }
}

/// Thrown to indicate a semantic error, like the use of an undefined name.
class LanguageViolationException implements Exception {
  String message;
  Token token;

  LanguageViolationException(this.message, this.token);
}
