/// This module contains all classes that are used to represent a program as an
/// [abstract syntax tree][1]. The root of every AST is a [Namespace] object.
/// You can parse code into this structure using the `minic.src.parser` library.
///
/// [1]: https://en.wikipedia.org/wiki/Abstract_syntax_tree
library minic.src.ast;

import 'dart:collection' show LinkedHashMap;

import 'package:meta/meta.dart';
import 'memory.dart' show NumberType, numberTypeByteCount;
import 'scanner.dart' show Token;

///
abstract class AstNode {
  /// The parent node in the AST.
  AstNode parent;

  /// Returns an Iterable of all child nodes. By default, this Iterable is
  /// empty.
  Iterable<AstNode> get children => const Iterable.empty();

  /// Yields all parent nodes, beginning with the direct parent. The last
  /// element will always be a [Namespace].
  Iterable<AstNode> get parents sync* {
    if (parent != null) {
      yield parent;
      yield* parent.parents;
    }
  }
}

/// Scopes contain named [Definition]s. They can be nested.
///
/// Every block enclosed in curly brackets introduces a scope. These are nested
/// inside their enclosing scope, which might be another block level scope or
/// the global namespace. Name lookups are first done in the current scope, and
/// if the identifier wasn't found, forwarded to the parent.
///
/// This class must be used as a mixin to [AstNode], as it depends on a
/// `parents` property.
abstract class Scope implements AstNode {
  LinkedHashMap<String, Definition> definitions =
      new LinkedHashMap<String, Definition>();

  Scope get parentScope => parents.firstWhere((AstNode node) => node is Scope);

  /// Add `definition` to this scope. Set `definition.parent` to `this`.
  ///
  /// Throw [NameCollisionException] when an entity with the same `identifier`
  /// already exists.
  void define(Definition definition) {
    var id = definition.identifier;
    if (definitions.containsKey(id))
      throw new NameCollisionException(definitions[id], definition);
    definition.parent = this;
    definitions[id] = definition;
  }

  /// Find a definition with `identifier` or throw [UndefinedNameException].
  Definition lookUp(String identifier) {
    return definitions.containsKey(identifier)
        ? definitions[identifier]
        : parentScope.lookUp(identifier);
  }
}

/// There is one special scope in every C program, which is the global
/// namespace. All top-level functions, typedefs and global variables are added
/// to this scope.
///
/// The `parent` of a namespace object is `null`.
class Namespace extends AstNode with Scope {
  Namespace();

  @override
  Iterable<AstNode> get children => definitions.values;

  @override
  Definition lookUp(String identifier) {
    if (definitions.containsKey(identifier)) return definitions[identifier];
    throw new UndefinedNameException(identifier);
  }
}

/// Represents anything with a name, like variables, types and functions. A
/// class must extend this class to be added to a [Scope].
///
/// Because this compiler doesn't support forward declaration, we don't distinct
/// between declaration and definition and every name introduced into a
/// namespace must be defined directly.
abstract class Definition extends AstNode {
  /// The name of this function, variable or type.
  String identifier;

  Definition(this.identifier);
}

/// Superclass for native types, typedefs, structs, enums and unions.
abstract class VariableType extends Definition {
  /// Size in byte, e.g. 1 for `char`
  int size;

  VariableType(String identifier, this.size) : super(identifier);
}

/// Represents a [basic type](http://en.cppreference.com/w/c/language/type).
/// These are never created by the parser, but a list of all available basic
/// types is defined in library `minic.src.language`.
class BasicType extends VariableType {
  NumberType numberType;

  BasicType(String identifier, NumberType numberType)
      : super(identifier, numberType.size),
        numberType = numberType;
}

/// Represents the void type for function return values. This object is never
/// created by the parser, but a list of all available basic types is defined in
/// library `minic.src.language`.
class VoidType extends VariableType {
  VoidType() : super('void', 0);
}

/// Represents a pointer type that references a variable of type `target`.
class PointerType extends VariableType {
  VariableType target;

  PointerType({@required VariableType target, @required int size})
      : super(target.identifier + '*', size),
        target = target;
}

/// Represents a variable definition in an expression, a function argument list,
/// or the global namespace.
class Variable extends Definition {
  Token constToken;
  Token variableTypeName;
  Token variableName;
  VariableType variableType;

  /// The expression that initializes this value, or `null`.
  Expression initializer;

  Variable(
      {@required this.constToken,
      @required this.variableTypeName,
      @required Token variableName,
      @required this.variableType,
      @required this.initializer})
      : super(variableName.value),
        variableName = variableName;
}

/// Represents a function definition.
class FunctionDefinition extends Definition {
  Token functionName;
  VariableType returnValue;
  List<Variable> parameters;
  CompoundStatement body;

  FunctionDefinition(
      {@required Token functionName,
      @required this.returnValue,
      @required this.parameters})
      : super(functionName.value),
        functionName = functionName;

  @override
  Iterable<AstNode> get children sync* {
    yield body;
    yield* parameters;
  }
}

/// Superclass for statement labels. Every statement in a C program can be
/// labeled. This class is empty because the different kinds of labels
/// ([GotoLabel], [CaseLabel], [DefaultLabel]) don't share any properties or
/// behaviour.
abstract class Label {
  const Label();
}

class GotoLabel extends Label {
  String identifier;

  GotoLabel(this.identifier);

  @override
  bool operator ==(other) {
    if (other is! GotoLabel) return false;
    return identifier == other.identifier;
  }
}

class CaseLabel extends Label {
  Expression value;

  CaseLabel(this.value);

  @override
  bool operator ==(other) {
    if (other is! CaseLabel) return false;
    return value.evaluate() == other.value.evaluate();
  }
}

class DefaultLabel extends Label {
  const DefaultLabel();
}

/// Represents a [statement][1].
///
/// [1]: http://en.cppreference.com/w/c/language/statements
abstract class Statement extends AstNode {
  List<Label> labels;

  /// Return all statements underneath this AST branch, including `this`, that
  /// are labeled.
  Iterable<Statement> get labeledStatements sync* {
    if (!labels.isEmpty) yield this;
    for (var child in children) {
      if (child is Statement) yield* child.labeledStatements;
    }
  }

  Statement(this.labels);
}

/// Represents a code block surrounded by curly brackets, including the bodies
/// of functions and flow control statements.
///
/// Note: This class is also instantiated as the body of `if`, `switch`, `for`,
/// `while`, and `do-while`, even if their body is __not__ enclosed by brackets,
/// because (since C99) these statements still introduce a new scope. You can
/// check for this with the `isSynthetic` property.
class CompoundStatement extends Statement with Scope {
  Token openingBracket;
  Token closingBracket;
  List<Statement> statements = [];

  bool get isSynthetic => openingBracket == null;

  @override
  Iterable<AstNode> get children sync* {
    yield* definitions.values;
    yield* statements;
  }

  CompoundStatement(
      {@required this.openingBracket,
      @required List<Label> labels})
      : super(labels);
}

/// If statement.
class IfStatement extends Statement {
  Expression expression;
  CompoundStatement body;

  @override
  Iterable<AstNode> get children sync* {
    yield expression;
    yield body;
  }

  IfStatement(
      {@required this.expression,
      @required this.body,
      @required List<Label> labels})
      : super(labels);
}

class SwitchStatement extends Statement {
  /// Token of type `kw_switch`.
  Token switchKeyword;

  /// The expression that selects to which branch to switch.
  Expression value;

  SwitchStatement(
      {@required this.switchKeyword,
      @required this.value,
      @required List<Label> labels})
      : super(labels);
}

/// Expression statement.
class ExpressionStatement extends Statement {
  Expression expression;

  @override
  Iterable<AstNode> get children => <AstNode>[expression];

  ExpressionStatement(
      {@required this.expression,
      @required List<Label> labels})
      : super(labels);
}

/// Placeholder
abstract class Expression extends AstNode {
  VariableType type;

  Expression();

  Expression evaluate();
}

/// Thrown by [Namespace.lookUp] if `identifier` was looked up and not found.
/// Note that [Scope]s forward lookups to their parent; because [Namespace]
/// doesn't have a parent, it will throw this exception instead.
class UndefinedNameException implements Exception {
  /// The name that was looked up.
  String identifier;

  UndefinedNameException(this.identifier);
}

/// Thrown by [Scope]`.define` if the identifier of the assigned definition
/// already exists in that scope.
class NameCollisionException implements Exception {
  /// The definition that already existed in the scope.
  Definition first;

  /// The definition that was added last and caused the collision with `first`.
  Definition second;

  NameCollisionException(this.first, this.second);
}
