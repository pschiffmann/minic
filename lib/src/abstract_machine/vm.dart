library minic.src.cmachine;

import 'instruction_set.dart' show Instruction, InstructionSet;
import '../memory.dart';

class VM {
  /// Combined stack and heap in a continous block of memory.
  ///
  /// The stack memory begins at `memory.size - 1` and grows towards zero, while
  /// the heap begins at zero and grows towards infinity.
  MemoryBlock memory;

  /// Points to the lowest currently used address of the stack (in [memory]).
  int stackPointer;

  /// Points to the highest currently used address of the heap (in [memory]).
  int framePointer;

  /// Points to the highest stack index the current function might allocate.
  int extremePointer;

  /// Stores the index into the program code of the next instruction.
  int programCounter;

  /// All instructions share a single carry flag.
  bool carryFlag;

  /// The instructions this VM can execute.
  final InstructionSet instructionSet;

  /// Used in [execute] to extract the immedate argument from opcodes.
  MemoryBlock _reinterpreter = new MemoryBlock(8);

  VM(this.instructionSet, int memorySize)
      : memory = new MemoryBlock(memorySize);

  /// Execute [instruction] on the current data.
  ///
  /// See [Instruction.execute] for details.
  void execute(int opcode) {
    var instruction = instructionSet.decode(opcode);
    var argument;
    var argType = instruction.expectedArgument;
    if (argType != null) {
      _reinterpreter.setValue(0, NumberType.uint64, opcode);
      _reinterpreter.getValue(8 - numberTypeByteCount[argType], argType);
    }
    var result = instruction.execute(this, argument);
    carryFlag = result is bool ? result : false;
  }

  /// Take back the last executed instruction.
  ///
  /// Implementation note: use [command]
  /// (http://gameprogrammingpatterns.com/command.html) pattern internally.
  void rollback() {
    throw new UnimplementedError();
  }

  /// Read [memory] at address as the specified number type.
  num readMemoryValue(int address, NumberType numberType) {
    return memory.getValue(address, numberType);
  }

  /// Read [memory] at the current stack pointer as the specified number type,
  /// then decrease the stack pointer by the size of that value.
  num popStack(NumberType numberType) {
    var value = readMemoryValue(stackPointer, numberType);
    stackPointer -= numberTypeByteCount[numberType];
    return value;
  }

  /// Insert value into [memory] at the specified address, encoded as the
  /// specified number type.
  void setMemoryValue(int address, NumberType numberType, num value) {
    memory.setValue(address, numberType, value);
  }

  /// Encode value as the specified number type, increase the stack pointer by
  /// the size of that value, then place the encoded value into [memory] at that
  /// address.
  void pushStack(NumberType numberType, num value) {
    stackPointer += numberTypeByteCount[numberType];
    setMemoryValue(stackPointer, numberType, value);
  }
}
