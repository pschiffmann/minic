library minic.src.scope;

import 'statement.dart';
import 'memory.dart';

/// Scopes contain named [Definition]s. They can be nested.
///
/// Every block enclosed in curly brackets introduces a scope. These are nested
/// inside their enclosing scope, which might be another block level scope or
/// the global namespace. Name lookups are first done in the current scope, and
/// if the identifier wasn't found, forwarded to the parent.
class Scope {
  Map<String, Definition> _definitions;
  Scope parent;

  Iterable<Variable> get variables =>
      _definitions.values.where((def) => def is Variable);

  Scope(this.parent) : _definitions = <String, Definition>{};

  /// Add `definition` to this scope.
  void define(Definition definition) {
    _definitions[definition.identifier] = definition;
  }

  /// Find a definition with `identifier` or throw an exception.
  Definition lookUp(String identifier) {
    return _definitions.containsKey(identifier)
        ? _definitions[identifier]
        : parent.lookUp(identifier);
  }
}

/// There is one special scope in every C program, which is the global
/// namespace. All top-level functions, typedefs and global variables are added
/// to this scope.
///
/// This class differs from a block scope in two ways: It may contain function
/// definitions, and it contains global variables that are not initialized by
/// a normal statement, but before the execution of the `main` function.
class Namespace extends Scope {
  List<ExpressionStatement> initializers;

  Namespace()
      : super(null),
        initializers = <ExpressionStatement>[];
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

/// Represents a native type, typedef, struct, enum or union definition –
/// everything that you can allocate memory for.
abstract class VariableType extends Definition {
  /// Size in byte, e.g. 1 for char
  final int size;
  VariableType(String name, this.size) : super(name);
}

/// Represents a native type or typedef that aliases a native type.
class LiteralType extends VariableType {
  final NumberType numberType;

  LiteralType(String name, NumberType numberType)
      : super(name, numberTypeByteCount[numberType]),
        numberType = numberType;
}

/// Represents a variable definition, like `int x`.
class Variable extends Definition {
  final VariableType type;
  final bool isConst;
  Variable(identifier, this.type, {this.isConst: false}) : super(identifier);
}

class Function extends Definition {
  VariableType returnValue;
  List<Variable> parameters;
  CompoundStatement body;

  Function(name) : super(name);
}
