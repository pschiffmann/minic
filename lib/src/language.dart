library minic.src.language;

import 'dart:collection' show LinkedHashMap;
import 'expression.dart';
import 'scope.dart';

enum TokenType {
  // operators
  ampamp,
  ampeq,
  amp,
  bangeq,
  bang,
  careteq,
  caret,
  colon,
  comma,
  diveq,
  div,
  dotstar,
  dot,
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
  minusgtstar,
  minusgt,
  minusminus,
  minus,
  percenteq,
  percent,
  pipeeq,
  pipepipe,
  pipe,
  pluseq,
  plusplus,
  plus,
  question,
  rbracket,
  rcbracket,
  rsbracket,
  stareq,
  star,
  tilde,
  newExpr,
  throwExpr,
  sizeofExpr,
  deleteExpr,
  // attributes
  constAttr,
  staticAttr,
  // definitions
  stmtStruct,
  stmtTypedef,
  stmtUnion,
  // flow control
  stmtIf,
  stmtElse,
  semicolon,
  // value literals
  floatLiteral,
  intLiteral,
  stringLiteral,
  charLiteral,
  name,

  /// This token is only emitted once and as the last token. This way we don't
  /// need to check for `null` values.
  endOfFile
}

/// List assigning a pattern to each [TokenType], which can be either a plain
/// `String`, or a [RegExp], depending on the complexity of the pattern.
///
/// This is a [LinkedHashMap], so you will iterate over the patterns in the
/// order they were defined. The elements in `TokenType` in return are ordered
/// putting more restrictive ones before others they collide with, e.g. the `++`
/// token occurs before the `+` token.
final Map<TokenType, Pattern> tokenPattern =
    new LinkedHashMap<TokenType, Pattern>.fromIterables(TokenType.values, [
  '&&',
  '&=',
  '&',
  '!=',
  '!',
  '^=',
  '^',
  ':',
  ',',
  '/=',
  '/',
  '.*',
  '.',
  '==',
  '=',
  '>=',
  '>>=',
  '>>',
  '>',
  '(',
  '{',
  '[',
  '<=',
  '<<=',
  '<<',
  '<',
  '-=',
  '->*',
  '->',
  '--',
  '-',
  '%=',
  '%',
  '|=',
  '||',
  '|',
  '+=',
  '++',
  '+',
  '?',
  ')',
  '}',
  ']',
  '*=',
  '*',
  '~',
  'new',
  'throw',
  'sizeof',
  'delete',
  'if',
  'else',
  ';',
  'const',
  'static',
  new RegExp('-?((?:\d+\.\d*)|(?:\d*\.\d+))f?'),
  new RegExp('-?(0x)?\d+'),
  new RegExp('"[^"]"'),
  new RegExp("'.'"),
  new RegExp('[A-Za-z_]\w*'),
  '\$'
]);

/// The following constants define the precedence levels of expression tokens.
///
/// Operator precedence is taken from [cppreference.com][1]. The comma operator
/// is not recognized here because it is not used as a node in the parsed AST.
/// Instead, we introduce a `name` precedence for names and constants that need
/// to be parsed into the AST.
///
/// Implementation note: This list should probably be an enum, but Dart doesn't
/// support accessing an enum items index as constexpr.
/// (see [dartbug.com/21955][])
///
/// [1]: http://en.cppreference.com/w/cpp/language/operator_precedence
const precedenceName = 1;
const precedenceAssignment = 2;
const precedenceLogicalOr = 3;
const precedenceLogicalAnd = 4;
const precedenceBitwiseOr = 5;
const precedenceBitwiseXor = 6;
const precedenceBitwiseAnd = 7;
const precedenceRelationEquals = 8;
const precedenceRelationLessGreater = 9;
const precedenceShift = 10;
const precedenceAddition = 11;
const precedenceMultiplication = 12;
const precedencePointerToMember = 13;
const precedencePrefix = 14;
const precedenceSuffix = 15;

/// Mapping from tokens to appropriate parselets for tokens that may start an
/// expression.
final Map<TokenType, PrefixParselet> prefixParselets =
    <TokenType, PrefixParselet>{
  TokenType.amp: const PrefixOperatorParselet(precedencePrefix),
  TokenType.bang: const PrefixOperatorParselet(precedencePrefix),
  TokenType.minusminus: const PrefixOperatorParselet(precedencePrefix),
  TokenType.minus: const PrefixOperatorParselet(precedencePrefix),
  TokenType.plusplus: const PrefixOperatorParselet(precedencePrefix),
  TokenType.plus: const PrefixOperatorParselet(precedencePrefix),
  TokenType.star: const PrefixOperatorParselet(precedencePrefix),
  TokenType.tilde: const PrefixOperatorParselet(precedencePrefix),
  TokenType.sizeofExpr: const PrefixOperatorParselet(precedencePrefix),
  TokenType.newExpr: const PrefixOperatorParselet(precedencePrefix),
  TokenType.deleteExpr: const PrefixOperatorParselet(precedencePrefix),
  TokenType.throwExpr: const PrefixOperatorParselet(precedenceAssignment),
  TokenType.name: const NameParselet()
};

/// Mapping from tokens to appropriate parselets for tokens that may occur right
/// hand of another expression, ordered by precedence.
final Map<TokenType, InfixParselet> infixParselets = <TokenType, InfixParselet>{
  // suffix, function call, member/array access
  TokenType.plusplus: const PostfixOperatorParselet(precedenceSuffix),
  TokenType.minusminus: const PostfixOperatorParselet(precedenceSuffix),
  TokenType.lbracket: const CallOperatorParselet(),
  TokenType.lsbracket: const SubscriptOperatorParselet(),
  TokenType.dot: const InfixOperatorParselet(precedenceSuffix),
  TokenType.minusgt: const InfixOperatorParselet(precedenceSuffix),
  // pointer to member
  TokenType.dotstar: const InfixOperatorParselet(precedencePointerToMember),
  TokenType.minusgtstar: const InfixOperatorParselet(precedencePointerToMember),
  // multiplication
  TokenType.star: const InfixOperatorParselet(precedenceMultiplication),
  TokenType.div: const InfixOperatorParselet(precedenceMultiplication),
  TokenType.percent: const InfixOperatorParselet(precedenceMultiplication),
  // addition
  TokenType.minus: const InfixOperatorParselet(precedenceAddition),
  TokenType.plus: const InfixOperatorParselet(precedenceShift),
  // shift
  TokenType.gtgt: const InfixOperatorParselet(precedenceShift),
  TokenType.ltlt: const InfixOperatorParselet(precedenceShift),
  // less/greater relation
  TokenType.lteq: const InfixOperatorParselet(precedenceRelationLessGreater),
  TokenType.lt: const InfixOperatorParselet(precedenceRelationLessGreater),
  TokenType.gteq: const InfixOperatorParselet(precedenceRelationLessGreater),
  TokenType.gt: const InfixOperatorParselet(precedenceRelationLessGreater),
  // equality relation
  TokenType.eqeq: const InfixOperatorParselet(precedenceRelationEquals),
  TokenType.bangeq: const InfixOperatorParselet(precedenceRelationEquals),
  // bitwise and
  TokenType.amp: const InfixOperatorParselet(precedenceBitwiseAnd),
  // bitwise xor
  TokenType.caret: const InfixOperatorParselet(precedenceBitwiseXor),
  // bitwise or
  TokenType.pipe: const InfixOperatorParselet(precedenceBitwiseOr),
  // logical and
  TokenType.ampamp: const InfixOperatorParselet(precedenceLogicalAnd),
  // logical or
  TokenType.pipepipe: const InfixOperatorParselet(precedenceLogicalOr),
  // assignment
  TokenType.eq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.pluseq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.minuseq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.stareq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.diveq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.percenteq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.ltlteq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.gtgteq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.ampeq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.careteq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.pipeeq:
      const InfixOperatorParselet(precedenceAssignment, rightAssociative: true),
  TokenType.question: const TernaryOperatorParselet()
};

final List<LiteralType> compilerBuiltins = <LiteralType>[
  new LiteralType('char', MemoryInterpretation.uint8),
  new LiteralType('int', MemoryInterpretation.sint32),
  new LiteralType('float', MemoryInterpretation.fp32),
  new LiteralType('double', MemoryInterpretation.fp64),
];
