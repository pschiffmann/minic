library minic.src.scope;

import 'token.dart';
import 'statement.dart';
import 'exception.dart';
import 'expression.dart';

/// Scopes contain named [Definition]s. They can be nested.
///
/// There is one special scope in every C program, which is the global
/// namespace. All top-level functions, typedefs and global variables are added
/// to this scope.
/// Additionally, every block enclosed in curly brackets introduces a scope.
/// These are nested inside their enclosing scope, which might be another block
/// level scope or a namespace.
/// Lookups are first done in the current scope, and if the identifier wasn't
/// found, forwarded to the parent. If there is no parent, which is the case for
/// the global namespace, an exception is thrown.
///
/// TODO: Add support for named scopes for `namespace` and class definitions and
/// implement access using the `::` operator.
class Scope {
  Map<String, Definition> _definitions;
  List<ExpressionStatement> initializers;
  Scope parent;

  Scope([Scope this.parent = null])
      : _definitions = <String, Definition>{},
        initializers = <ExpressionStatement>[];

  /// Add [definition] to this scope.
  void define(Definition definition) {
    _definitions[definition.identifier] = definition;
  }

  /// Find a definition with [identifier] or throw an exception.
  Definition lookUp(String identifier) {
    if (_definitions.containsKey(identifier)) return _definitions[identifier];
    if (parent != null) return parent.lookUp(identifier);
    throw new UndefinedNameException('`$identifier` is not defined.');
  }
}

/// Represents anything with a name, like variables, types and functions.
///
/// Because this compiler doesn't support forward declaration, we don't distinct
/// between declaration and definition and every name introduced into a
/// namespace must be defined directly.
abstract class Definition {
  final String identifier;
  Definition(this.identifier);
}

/// Represents a native type, typedef, struct or class definition.
abstract class CType extends Definition {
  /// Size in byte, e.g. 1 for char
  final int size;
  CType(String name, this.size) : super(name);
}

/// Possible ways to interpret memory.
///
/// Other memory sizes are not supported by [ByteData][1], so we don't support
/// them either.
///
/// [1][https://api.dartlang.org/1.12.1/dart-typed_data/ByteData-class.html]
enum MemoryInterpretation {
  uint8,
  uint16,
  uint32,
  uint64,
  sint8,
  sint16,
  sint32,
  sint64,
  fp32,
  fp64,
  bool
}

/// Represents a native type or typedef that aliases a native type.
class LiteralType extends CType {
  final MemoryInterpretation interpretation;

  static final Map _sizes = <MemoryInterpretation, int>{
    MemoryInterpretation.bool: 1,
    MemoryInterpretation.uint8: 1,
    MemoryInterpretation.sint8: 1,
    MemoryInterpretation.uint16: 2,
    MemoryInterpretation.sint16: 2,
    MemoryInterpretation.fp32: 4,
    MemoryInterpretation.uint32: 4,
    MemoryInterpretation.sint32: 4,
    MemoryInterpretation.fp64: 8,
    MemoryInterpretation.uint64: 8,
    MemoryInterpretation.sint64: 8,
  };

  LiteralType(String name, MemoryInterpretation interpretation)
      : super(name, _sizes[interpretation]),
        interpretation = interpretation;
}

/*
/// Represents a class or struct.
class CompoundType extends CType {
  List<Variable> staticProperties;
  List<Variable> properties;
}*/

/// Represents a variable definition, like `int x`.
class Variable extends Definition {
  final CType type;
  final bool isConst;
  Variable(identifier, this.type, {this.isConst: false}) : super(identifier);
}

class Function extends Definition {
  CType returnValue;
  List<Variable> parameters;
  CompoundStatement body;

  Function(name) : super(name);
}

///
class ScopeParser {
  TokenIterator tokens;
}

class ScopeException implements Exception {
  final String message;
  ScopeException(this.message);
}

/// Thrown by [Scope] if an undefined [identifier] is looked up.
class UndefinedNameException implements Exception {
  final String identifier;
  UndefinedNameException(this.identifier);
}
