/// This library implements the target architecture of the minic compiler,
/// consisting of the [instruction set architecture][1] and a [virtual machine]
/// [2] that implements these instructions.
///
/// The [VM] provides a 16-bit address space; code segment and runtime data
/// share 2^16B ≈ 65kB. All opcodes have a size of 4 bytes, where the two lower
/// bytes are reserved for one immediate argument. Because the VM has no
/// general-purpose registers, the instruction set is implemented as a stack
/// machine.
///
/// [1]: https://en.wikipedia.org/wiki/Instruction_set
/// [2]: https://en.wikipedia.org/wiki/Virtual_machine
library minic.src.cmachine;

import 'dart:math' show pow;
import '../ast.dart' show AstNode;
import '../memory.dart';
import '../scanner.dart' show Token;

/// This library works with a static size of 4 bytes for all opcodes.
const NumberType instructionSize = NumberType.uint32;

/// If an immediate argument is encoded in an opcode, its size is 2 bytes.
const NumberType addressSize = NumberType.uint16;

/// This class serves as the context to a program execution by providing the
/// memory to store runtime data. This includes the organizational registers and
/// random access memory.
///
/// The following diagram describes the structure of the memory block:
///
///          stack          -- address: stackPointer..max
///            ⋮
///     <unused segment>
///            ⋮
///          heap           -- address: codeSegmentSize..<property not implemented>
///            ⋮
///          code           -- address: 0..codeSegmentSize - 1
class VM {
  /// Combined stack and heap in a continuous block of memory.
  ///
  /// The stack memory begins at `memory.size - 1` and grows towards zero, while
  /// the heap begins at zero and grows towards infinity.
  MemoryBlock memory;

  /// The program that is executed when calling [run].
  List<Instruction> program;

  /// Number of bytes in the VMs memory that is reserved for the [program].
  int get codeSegmentSize => program.length * instructionSize.size;

  /// Points to the lowest currently used byte of the stack (in [memory]).
  int stackPointer;

  /// Points to the last byte in the stack that is not owned by the current
  /// function invocation. This register is used to determine the memory address
  /// of local variables. Look at [LoadRelativeAddressInstruction] for details.
  int framePointer;

  /// Points to the highest stack index the current function might allocate.
  ///
  /// TODO: Will be used to detect stack overflows, once heap memory allocation
  /// is implemented.
  int extremePointer;

  /// Stores the index into the program code of the next instruction.
  ///
  /// Note: this index references the _nth instruction_, not the instruction
  /// at _address n_! The address of the referenced instruction in bytes is
  /// `programCounter * instructionSize.size`.
  int programCounter = 0;

  /// The instruction that should be executed next, according to the flow
  /// control of the program.
  Instruction get nextInstruction => program[programCounter];

  /// Initialize the VM with `memorySize` bytes available memory, of which the
  /// bytes `[0..codeSegmentSize)` are read-only.
  VM(this.program, [int memorySize]) {
    memorySize ??= pow(2, 16);
    if (memorySize > pow(2, 16))
      throw new ArgumentError.value(
          memorySize, 'memorySize', 'Exceeding maximum valid value of 2^16');
    memory = new MemoryBlock(memorySize - codeSegmentSize);
    stackPointer = framePointer = extremePointer = memorySize;
  }

  /// Run [program] until it terminates. Return the value returned from the
  /// programs `main` function.
  int run() {
    try {
      while (true) {
        execute(nextInstruction);
      }
    } on HaltSignal catch (signal) {
      return signal.statusCode;
    }
  }

  /// Execute a single `instruction` in the context of this VM.
  void execute(Instruction instruction) {
    programCounter++;
    instruction.implementation.execute(this, instruction.argument);
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
    if (address < codeSegmentSize)
      // TODO: Encode the instruction(s) at `address`, and return the according
      // byte value.
      throw new UnimplementedError('Reading from code segment not implemented');
    try {
      return memory.getValue(address - codeSegmentSize, numberType);
    } on RangeError {
      throw new SegfaultSignal(address, 'Out of range');
    }
  }

  /// Read [memory] at the current stack pointer as the specified number type,
  /// then decrease the stack pointer by the size of that value.
  num popStack(NumberType numberType) {
    var value = readMemoryValue(stackPointer, numberType);
    stackPointer += numberType.size;
    return value;
  }

  /// Insert value into [memory] at the specified address, encoded as the
  /// specified number type.
  void setMemoryValue(int address, NumberType numberType, num value) {
    if (address < codeSegmentSize)
      throw new SegfaultSignal(address, 'The code segment is read-only');
    try {
      memory.setValue(address, numberType, value);
    } on RangeError {
      throw new SegfaultSignal(address, 'Out of range');
    }
  }

  /// Encode value as the specified number type, increase the stack pointer by
  /// the size of that value, then place the encoded value into [memory] at that
  /// address.
  void pushStack(NumberType numberType, num value) {
    stackPointer -= numberType.size;
    setMemoryValue(stackPointer, numberType, value);
  }
}

/// Contains a single instruction that was generated for a portion of the AST.
/// It can be executed by a [VM].
class Instruction {
  /// These tokens are taken from the AST nodes that produced this instruction.
  /// For example, for an [AddInstruction], `tokens` will reference a `+` token.
  /// This relation is saved to be displayed in the UI.
  List<Token> tokens;

  /// The immediate argument that is encoded in the instruction. This can be
  ///   * `null` if the implementation takes no argument
  ///   * `int` if the value can be directly resolved
  ///   * An [AstNode] if the value can't be determined at the time when this
  ///     object is created. This happens when a flow control instruction jumps
  ///     "forward", targeting an instruction with a higher address that itself.
  var immediateValue;

  /// References the instruction type, or [opcode]
  /// (https://en.wikipedia.org/wiki/Opcode).
  InstructionTemplate implementation;

  /// If `implementation` does not expect an argument, return `null`. Else
  /// resolve `immediateValue` to an integer value.
  int get argument => immediateValue is AstNode
      ? immediateValue.compilerInformation
      : immediateValue;

  Instruction(this.implementation, this.tokens, [this.immediateValue]);

  String toString() => immediateValue != null
      ? '${implementation.name} $argument'
      : implementation.name;
}

/// Implements a machine instruction that can be executed by a [VM].
///
/// Instructions are instantiated as const objects because we need several
/// different versions of some instructions. For example, we need integer
/// addition for 8, 16, 32 and 64 bit words.
abstract class InstructionTemplate {
  /// The short name of this opcode, e.g. `push` for a [PushInstruction].
  String get name;

  const InstructionTemplate();

  /// Execute this instruction on `vm`.
  void execute(VM vm, num immediateArgument);
}

/// Pushes the immediate argument on the stack.
class PushInstruction extends InstructionTemplate {
  /// Size of the value that is pushed to the stack.
  final NumberType valueType;

  String get name => 'loadc<${valueType.size}>';

  const PushInstruction(this.valueType);

  void execute(VM vm, num value) {
    vm.pushStack(valueType, value);
  }
}

/// Reduces the stack by _n_ bytes, encoded as immediate argument.
class PopInstruction extends InstructionTemplate {
  String get name => 'pop';

  const PopInstruction();

  void execute(VM vm, int numberOfBytes) {
    vm.stackPointer += numberOfBytes;
  }
}

/// Increases the stack by _n_ bytes, encoded as immediate argument.
class StackAllocateInstruction extends InstructionTemplate {
  String get name => 'alloc';

  const StackAllocateInstruction();

  void execute(VM vm, int numberOfBytes) {
    vm.stackPointer -= numberOfBytes;
  }
}

/// Loads _n_ bytes from _address_ to the stack, where _n_ is encoded as
/// immediate argument in the instruction, and _address_ is read from the stack.
class FetchInstruction extends InstructionTemplate {
  final NumberType addressSize;

  String get name => 'loada';

  const FetchInstruction(this.addressSize);

  void execute(VM vm, num numberOfBytes) {
    var address = vm.popStack(addressSize);
    while (numberOfBytes > 0) {
      var chunk = const [
        NumberType.uint64,
        NumberType.uint32,
        NumberType.uint16,
        NumberType.uint8
      ].firstWhere((numberType) => numberOfBytes >= numberType.size);
      vm.pushStack(chunk, vm.readMemoryValue(address, chunk));
      numberOfBytes -= chunk.size;
      address += chunk.size;
    }
  }
}

/// Stores _n_ bytes at _address_ on the stack, where _n_ is encoded as
/// immediate argument in the instruction, and _address_ is read from the stack.
class StoreInstruction extends InstructionTemplate {
  final NumberType addressSize;

  String get name => 'store';

  const StoreInstruction(this.addressSize);

  void execute(VM vm, num numberOfBytes) {
    var address = vm.popStack(addressSize);
    while (numberOfBytes > 0) {
      var chunk = const [
        NumberType.uint64,
        NumberType.uint32,
        NumberType.uint16,
        NumberType.uint8
      ].firstWhere((numberType) => numberOfBytes >= numberType.size);
      vm.setMemoryValue(address, chunk, vm.popStack(chunk));
      numberOfBytes -= chunk.size;
      address += chunk.size;
    }
  }
}

/// Load the value `vm.framePointer` - _immediate value_ to the stack.
class LoadRelativeAddressInstruction extends InstructionTemplate {
  final NumberType addressSize;

  String get name => 'loadr';

  const LoadRelativeAddressInstruction(this.addressSize);

  void execute(VM vm, int offset) {
    vm.pushStack(addressSize, vm.framePointer - offset);
  }
}

/// Halts the program execution by throwing [HaltSignal]. Reads the exit code
/// from the stack as `uint32`.
class HaltInstruction extends InstructionTemplate {
  String get name => 'halt';

  const HaltInstruction();

  void execute(VM vm, _) =>
      throw new HaltSignal(vm.popStack(NumberType.uint32));
}

/// Sets the program counter to the immediate value.
class JumpInstruction extends InstructionTemplate {
  String get name => 'jump';

  const JumpInstruction();

  void execute(VM vm, int address) {
    vm.programCounter = address;
  }
}

/// Pops the top byte from the stack; if it equals zero, jump to the immediate
/// address.
class JumpZeroInstruction extends InstructionTemplate {
  String get name => 'jumpz';

  const JumpZeroInstruction();

  void execute(VM vm, int address) {
    if (vm.popStack(NumberType.uint8) == 0) vm.programCounter = address;
  }
}

/// Calls the function referenced by the top stack value by setting the program
/// counter to that value.
///
/// Stores the current organizational registers on the stack. These are (from
/// stack top to bottom):
///   * return address / program counter
///   * stack pointer + _offset_, which is passed as immediate argument; the
///     resulting value points to the address of the return value in the callees
///     context.
///   * frame pointer
///   * extreme pointer
///
/// Points the frame pointer to the top of the stack (and therefore on the
/// return address).
class CallInstruction extends InstructionTemplate {
  final NumberType addressSize;

  String get name => 'call';

  const CallInstruction(this.addressSize);

  void execute(VM vm, int offset) {
    vm.programCounter = vm.popStack(addressSize);
    vm.pushStack(addressSize, vm.extremePointer);
    vm.pushStack(addressSize, vm.framePointer);
    vm.pushStack(addressSize, vm.stackPointer + offset);
    vm.pushStack(addressSize, vm.programCounter);
    vm.framePointer = vm.stackPointer;
  }
}

/// Completes the runtime context of a function invocation by setting the
/// extreme pointer.
class EnterFunctionInstruction extends InstructionTemplate {
  String get name => 'enter';

  const EnterFunctionInstruction();

  void execute(VM vm, int offset) {
    vm.extremePointer = vm.framePointer - offset;
  }
}

/// Returns from a function call. Restores the organizational registers from the
/// backed up values on the stack.
class ReturnInstruction extends InstructionTemplate {
  final NumberType addressSize;

  String get name => 'return';

  const ReturnInstruction(this.addressSize);

  void execute(VM vm, _) {
    var localOffset = (int n) => vm.framePointer + n * addressSize.size;
    vm
      ..programCounter = vm.readMemoryValue(localOffset(0), addressSize)
      ..stackPointer = vm.readMemoryValue(localOffset(1), addressSize)
      ..extremePointer = vm.readMemoryValue(localOffset(3), addressSize)
      ..framePointer = vm.readMemoryValue(localOffset(2), addressSize);
  }
}

/// Converts the top stack element between the specified types. Instead of
/// reinterpreting the memory, the value is retained. For example, executing a
/// type conversion `double32 ↦ int32` on the value `1.0` yields `1` (which has
/// a different bit pattern).
class TypeConversionInstruction extends InstructionTemplate {
  final NumberType from;
  final NumberType to;

  String get name => 'cast<$from↦$to>';

  const TypeConversionInstruction(this.from, this.to);

  void execute(VM vm, _) => vm.pushStack(to, vm.popStack(from));
}

/// Superclass for all side effect-free arithmetic, bitwise and logical
/// operators with two operands. Subclasses need only implement the `calculate`
/// method.
abstract class ArithmeticOperationInstruction extends InstructionTemplate {
  final NumberType numberType;

  const ArithmeticOperationInstruction(this.numberType);

  /// Pop two `numberType` elements from the stack, pass them to `calculate`
  /// and push the result back onto the stack.
  void execute(VM vm, _) {
    var arg1 = vm.popStack(numberType);
    var arg2 = vm.popStack(numberType);
    vm.pushStack(numberType, calculate(arg1, arg2));
  }

  /// Extension point for subclasses; implements the specific operation.
  num calculate(num op1, num op2);
}

/// Adds the two top stack elements.
class AddInstruction extends ArithmeticOperationInstruction {
  String get name => 'add<${numberType}>';

  const AddInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a + b;
}

/// Subtracts the two top stack elements.
class SubtractInstruction extends ArithmeticOperationInstruction {
  String get name => 'sub<${numberType}>';

  const SubtractInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a - b;
}

/// Multiplies the two top stack elements.
class MultiplyInstruction extends ArithmeticOperationInstruction {
  String get name => 'mul<${numberType}>';

  const MultiplyInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a * b;
}

/// Divides the two top stack elements.
class DivideInstruction extends ArithmeticOperationInstruction {
  String get name => 'div<${numberType}>';

  const DivideInstruction(numberType) : super(numberType);

  num calculate(num a, num b) =>
      numberType.memoryInterpretation == double ? a / b : a ~/ b;
}

/// Calculates the modulo of the two top stack elements.
class ModuloInstruction extends ArithmeticOperationInstruction {
  String get name => 'mod<${numberType}>';

  const ModuloInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a % b;
}

/// Arithmetic inversion of the top stack element.
class InverseInstruction extends InstructionTemplate {
  final NumberType numberType;

  String get name => 'neg<${numberType}>';

  const InverseInstruction(this.numberType);

  void execute(VM vm, _) => vm.pushStack(numberType, -vm.popStack(numberType));
}

/// Bitwise inverse of the top stack element.
class BitwiseNotInstruction extends InstructionTemplate {
  final NumberType numberType;

  String get name => 'inv<${numberType}>';

  const BitwiseNotInstruction(this.numberType);

  void execute(VM vm, _) =>
      vm.pushStack(numberType, ~(vm.popStack(numberType) as int));
}

/// Bitwise _and_ of the two top stack elements.
class BitwiseAndInstruction extends ArithmeticOperationInstruction {
  String get name => 'and<${numberType}>';

  const BitwiseAndInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a & b;
}

/// Bitwise _or_ of the two top stack elements.
class BitwiseOrInstruction extends ArithmeticOperationInstruction {
  String get name => 'or<${numberType}>';

  const BitwiseOrInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a | b;
}

/// Bitwise _xor_ of the two top stack elements.
class BitwiseExclusiveOrInstruction extends ArithmeticOperationInstruction {
  String get name => 'xor<${numberType}>';

  const BitwiseExclusiveOrInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a ^ b;
}

/// Compares the two top stack elements using `==`.
class EqualsInstruction extends ArithmeticOperationInstruction {
  String get name => 'eq<${numberType.size * 8}>';

  const EqualsInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a == b ? 1 : 0;
}

/// Compares the two top stack elements using `>`.
class GreaterThanInstruction extends ArithmeticOperationInstruction {
  String get name => 'gt<${numberType}>';

  const GreaterThanInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a > b ? 1 : 0;
}

/// Compares the two top stack elements using `≥`.
class GreaterEqualsInstruction extends ArithmeticOperationInstruction {
  String get name => 'ge<${numberType}>';

  const GreaterEqualsInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a >= b ? 1 : 0;
}

/// Compares the two top stack elements using `<`.
class LessThanInstruction extends ArithmeticOperationInstruction {
  String get name => 'lt<${numberType}>';

  const LessThanInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a < b ? 1 : 0;
}

/// Compares the two top stack elements using `≤`.
class LessEqualsInstruction extends ArithmeticOperationInstruction {
  String get name => 'le<${numberType}>';

  const LessEqualsInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a <= b ? 1 : 0;
}

/// Logical negation of the top stack element.
class NegateInstruction extends InstructionTemplate {
  String get name => 'not';

  const NegateInstruction();

  void execute(VM vm, _) => vm.pushStack(
      NumberType.uint8, vm.popStack(NumberType.uint8) == 0 ? 1 : 0);
}

/// Thrown when the execution of a program reaches the end of the `main`
/// function or encounters a call to `exit`.
class HaltSignal implements Exception {
  /// The value returned by `main` or passed to `exit`.
  int statusCode;

  HaltSignal(this.statusCode);

  String toString() => 'HaltSignal($statusCode)';
}

/// Thrown by [VM] to handle [memory access violations][1].
///
/// [1]: https://en.wikipedia.org/wiki/Segmentation_fault
class SegfaultSignal implements Exception {
  /// The address that was accessed.
  int address;

  /// Explanation why the signal was thrown.
  String message;

  SegfaultSignal(this.address, this.message);

  String toString() => 'Segfault at $address: $message';
}
