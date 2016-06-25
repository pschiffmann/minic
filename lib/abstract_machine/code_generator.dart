library minic.abstract_machine.code_generator;

import '../ast.dart';
import '../memory.dart';
import '../scanner.dart';
import 'vm.dart';

/// Allows lookup of an operationss opcode:
///
///     var operation = new PushOperation(NumberType.uint8);
///     print(instructionSet.lookup(operation).opcode);
final Set<AluOperation> instructionSet = new Set.from(VM.instructionSet);

///
class Instruction {
  /// The operation of this instruction. Must always reference an element of
  /// `VM.instructionSet`.
  AluOperation operation;

  /// The immediate argument passed to `operation.execute`.
  ///
  /// If the value is a constant literal, this will be an [int]. If the value is
  /// an address however, it will temporarily be an [AstNode], and resolved to
  /// an integer by `CodeGenerator.addressCache`.
  var immediateArgument;

  /// The C tokens that ultimately led to the instantiation of this instruction.
  List<Token> tokens;

  Instruction(this.operation, [this.immediateArgument, this.tokens]);
}

///
class CodeGenerator {
  ///
  Expando<AstNode> addressCache = new Expando<AstNode>('AST address cache');

  ///
  List<Instruction> generatedInstructions = <Instruction>[];

  ///
  MemoryBlock generatedBytecode;

  /// Creates [generatedBytecode].
  void generateBytecode() {
    generatedBytecode = new MemoryBlock(generatedInstructions
            .map((instruction) => instruction.operation.immediateArgumentSize)
            .reduce((a, b) => a + b) +
        generatedInstructions.length);
    int i = 1;
    for (var instruction in generatedInstructions) {
      generatedBytecode.setValue(
          i++, NumberType.uint8, instruction.operation.opcode);
    }
  }

  /// Append an [Instruction] of type `operation` to [generatedInstructions].
  void _append(AluOperation operation, [immediateArgument]) {
    generatedInstructions.add(
        new Instruction(instructionSet.lookup(operation), immediateArgument));
  }

  void generateNamespace(Namespace namespace) {
    _append(new CallOperation(), namespace.lookUp('main'));
    _append(new HaltOperation());
  }
}
