library minic.src.abstract_machine.instruction_set;

import 'vm.dart';
import '../ast.dart';
import '../memory.dart';

/// The code generator assumes an address size of 32 bit,
const NumberType addressSize = NumberType.uint32;

/// Generate [Instruction]s that implement the behaviour of the assigned node.
/// Calling this function with a [Namespace] will yield an executable program.
///
/// This function uses the `AstNode.compilerInformation` property to store
/// addresses as `int`. This value is interpreted differently depending on the
/// type of node:
///   * For statements and expressions, this is the address of the generated
///     instruction.
///   * For global variables, this is the absolute address.
///   * For local variables, this is the local address relative to the VMs frame
///     pointer.
///   * For other node types, the property is not used.
List<Instruction> generate(AstNode node) => _generators[node.runtimeType](node);

/// The generator functions used by [generate].
final Map<Type, Function> _generators = <Type, Function>{}

  /// Generate instructions for every [Definition] in the namespace.
  ..[Namespace] = (Namespace node) {
    var program = <Instruction>[];
    var variables = <Variable>[], functions = <FunctionDefinition>[];
    for (var definition in node.children)
      (definition is Variable ? variables : functions).add(definition);

    program.addAll(variables.map((Variable variable) {
      switch (variable.variableType.runtimeType) {
        case BasicType:
          return new Instruction(const PushInstruction(NumberType.uint8),
              [variable.variableName], variable.initializer.evaluate());
        default:
          throw new UnimplementedError(
              'Can only generate instructions for basic types');
      }
    }));
    for (var function in functions) {
      program.addAll(generate(function));
    }
    return program;
  }

  ///
  ..[Variable] = (Variable variable) {}

  ///
  ..[FunctionDefinition] = (FunctionDefinition node) {}

  ///
  ..[AssignmentExpression] = (AssignmentExpression node) sync* {
    yield new Instruction(const LoadRelativeAddressInstruction(addressSize),
        [node.left.identifier], node.left.compilerInformation);
    yield* generate(node.right);
    yield new Instruction(const StoreInstruction(NumberType.uint8), [node.token]);
  };
