library minic.abstract_machine.code_generator;

import '../ast.dart';
import '../memory.dart';
import '../scanner.dart';
import 'vm.dart';

/// Allows lookup of an operations opcode:
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
  Namespace namespace;

  ///
  Expando<AstNode> addressCache = new Expando<AstNode>('AST address cache');

  ///
  List<Instruction> generatedInstructions = <Instruction>[];

  ///
  MemoryBlock generatedBytecode;

  ///
  CodeGenerator(this.namespace) {
    generate();
  }

  /// Creates [generatedBytecode].
  void generateBytecode() {
    generatedBytecode = new MemoryBlock(generatedInstructions
            .map((instruction) => instruction.operation.immediateArgumentSize)
            .reduce((a, b) => a + b) +
        generatedInstructions.length +
        1);

    int i = 1;
    for (var instruction in generatedInstructions) {
      generatedBytecode.setValue(
          i++, NumberType.uint8, instruction.operation.opcode);
      if (instruction.operation.immediateArgumentSize != null) {
        generatedBytecode.setValue(
            i,
            instruction.operation.immediateArgumentSize,
            instruction.immediateArgument);
        i += instruction.operation.immediateArgumentSize.sizeInBytes;
      }
    }
  }

  /// Append an [Instruction] of type `operation` to [generatedInstructions].
  void append(AluOperation operation, [List<Token> tokens, immediateArgument]) {
    generatedInstructions.add(new Instruction(
        instructionSet.lookup(operation), tokens, immediateArgument));
  }

  ///
  void generate() {
    for (var variable in namespace.globalVariables) {
      if (variable.initializer == null)
        append(new StackAllocateOperation(), [variable.variableName],
            variable.variableType.size);
      else {
        //generateExpression(variable.initializer);
      }
    }

    FunctionDefinition main = namespace.lookUp('main');
    append(new CallOperation(), [main.functionName], main);
    append(new HaltOperation());

    generatedInstructions.forEach((instruction) {
      if (instruction.immediateArgument is AstNode)
        instruction.immediateArgument =
            addressCache[instruction.immediateArgument];
    });
    generateBytecode();
  }
}
