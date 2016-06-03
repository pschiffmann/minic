/// This library implements the target architecture of the minic compiler,
/// consisting of the [instruction set architecture][1] and a [virtual machine]
/// [2] that implements these instructions.
///
/// The [VM] provides a 16-bit address space; code segment and runtime data
/// share 2^16B ≈ 65kB. The instruction set design is heavily inspired by the
/// [Java bytecode instructions][3]: All opcodes have a size of 1 byte, and the
/// following 0..8 bytes store one immediate argument. Because the VM has no
/// general-purpose registers, the instruction set is implemented as a stack
/// machine.
///
/// [1]: https://en.wikipedia.org/wiki/Instruction_set
/// [2]: https://en.wikipedia.org/wiki/Virtual_machine
/// [3]: https://en.wikipedia.org/wiki/Java_bytecode_instruction_listings
library minic.src.cmachine;

import 'dart:math' show pow;
import '../ast.dart' show AstNode;
import '../memory.dart';
import '../scanner.dart' show Token;

/// All opcodes have a size of one byte.
const NumberType opcodeSize = NumberType.uint8;

/// The memory of a VM is limited to 2^16 bytes; therefore, a 16-bit integer is
/// sufficient to allow byte-level addressing.
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
  int get codeSegmentSize =>
      0; // TODO: update this when a better structure for [program] is implemented.

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
    stackPointer += numberType.sizeInBytes;
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
    stackPointer -= numberType.sizeInBytes;
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
  InstructionImplementation implementation;

  /// If `implementation` does not expect an argument, return `null`. Else
  /// resolve `immediateValue` to an integer value.
  int get argument => immediateValue is AstNode
      ? immediateValue.compilerInformation
      : immediateValue;

  Instruction(this.implementation, this.tokens, [this.immediateValue]);

  String toString() => implementation.immediateArgumentSize == 0
      ? implementation.name
      : '${implementation.name} $argument';
}

/// Implements a machine instruction that can be executed by a [VM].
///
/// Instructions are instantiated as objects because we need several different
/// versions of some of them. For example, we need integer addition for 8, 16,
/// 32 and 64 bit words.
abstract class InstructionImplementation {
  /// A verbose mnemonic for this instruction.
  String get name;

  /// This number of bytes immediately following this instruction are passed to
  /// [execute] as `immediateArgument`.
  int get immediateArgumentSize => 0;

  const InstructionImplementation();

  /// Execute this instruction on `vm`.
  void execute(VM vm, num immediateArgument);
}

/// Superclass for implementations that are overloaded with a single type. This
/// includes all overloaded implementations except [TypeConversionInstruction].
abstract class OverloadedImplementation extends InstructionImplementation {
  /// Some implementations (for example [AddInstruction]) don't distinct between
  /// signed and unsigned integers. This method generates a string similar to
  /// [NumberType#toString], but leaves out the sign prefix for integers.
  static String _unifyIntegerNames(NumberType t) => t.memoryInterpretation ==
      NumberType.float ? t.toString() : 'int${t.sizeInBits}';

  /// Size of the value that is pushed to the stack.
  final NumberType valueType;

  String get name => format(valueType);

  const OverloadedImplementation(this.valueType);

  /// Return a mnemonic for the given overloaded type. This is used by
  /// [InstructionSet#resolveForType].
  ///
  /// _This method should be static, but static methods are not part and a class
  /// interface and difficult to call dynamically._
  String format(NumberType t);
}

/// Pushes the immediate argument on the stack.
class PushInstruction extends OverloadedImplementation {
  int get immediateArgumentSize => valueType.sizeInBytes;

  const PushInstruction(NumberType valueType) : super(valueType);

  void execute(VM vm, num value) {
    vm.pushStack(valueType, value);
  }

  String format(NumberType t) => 'loadc<${t.sizeInBits}>';
}

/// Reduces the stack by _n_ bytes, encoded as immediate argument.
class PopInstruction extends InstructionImplementation {
  String get name => 'pop';

  const PopInstruction();

  void execute(VM vm, int numberOfBytes) {
    vm.stackPointer += numberOfBytes;
  }
}

/// Increases the stack by _n_ bytes, encoded as immediate argument.
class StackAllocateInstruction extends InstructionImplementation {
  String get name => 'alloc';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const StackAllocateInstruction();

  void execute(VM vm, int numberOfBytes) {
    vm.stackPointer -= numberOfBytes;
  }
}

/// Loads _n_ bytes from _address_ to the stack, where _n_ is encoded as
/// immediate argument in the instruction, and _address_ is read from the stack.
class FetchInstruction extends InstructionImplementation {
  String get name => 'loada';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const FetchInstruction();

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
class StoreInstruction extends InstructionImplementation {
  String get name => 'store';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const StoreInstruction();

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
class LoadRelativeAddressInstruction extends InstructionImplementation {
  String get name => 'loadr';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const LoadRelativeAddressInstruction();

  void execute(VM vm, int offset) {
    vm.pushStack(addressSize, vm.framePointer - offset);
  }
}

/// Halts the program execution by throwing [HaltSignal]. Reads the exit code
/// from the stack as `uint32`.
class HaltInstruction extends InstructionImplementation {
  String get name => 'halt';

  const HaltInstruction();

  void execute(VM vm, _) =>
      throw new HaltSignal(vm.popStack(NumberType.uint32));
}

/// Sets the program counter to the immediate value.
class JumpInstruction extends InstructionImplementation {
  String get name => 'jump';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const JumpInstruction();

  void execute(VM vm, int address) {
    vm.programCounter = address;
  }
}

/// Pops the top byte from the stack; if it equals zero, jump to the immediate
/// address.
class JumpZeroInstruction extends InstructionImplementation {
  String get name => 'jumpz';

  int get immediateArgumentSize => addressSize.sizeInBytes;

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
class CallInstruction extends InstructionImplementation {
  String get name => 'call';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const CallInstruction();

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
class EnterFunctionInstruction extends InstructionImplementation {
  String get name => 'enter';

  int get immediateArgumentSize => addressSize.sizeInBytes;

  const EnterFunctionInstruction();

  void execute(VM vm, int offset) {
    vm.extremePointer = vm.framePointer - offset;
  }
}

/// Returns from a function call. Restores the organizational registers from the
/// backed up values on the stack.
class ReturnInstruction extends InstructionImplementation {
  String get name => 'return';

  const ReturnInstruction();

  void execute(VM vm, _) {
    var localOffset = (int n) => vm.framePointer + n * addressSize.sizeInBytes;
    vm
      ..programCounter = vm.readMemoryValue(localOffset(0), addressSize)
      ..stackPointer = vm.readMemoryValue(localOffset(1), addressSize)
      ..extremePointer = vm.readMemoryValue(localOffset(3), addressSize)
      ..framePointer = vm.readMemoryValue(localOffset(2), addressSize);
  }
}

/// Converts the top stack element between the specified types. Instead of
/// reinterpreting the memory, the value is retained. For example, executing a
/// type conversion `double32↦int32` on the value `1.0` yields `1` (which has
/// a different bit pattern).
class TypeConversionInstruction extends InstructionImplementation {
  final NumberType from;
  final NumberType to;

  String get name => format(from, to);

  const TypeConversionInstruction(this.from, this.to);

  void execute(VM vm, _) => vm.pushStack(to, vm.popStack(from));

  String format(NumberType from, NumberType to) => 'cast<$from↦$to>';
}

/// Superclass for all side effect-free arithmetic, bitwise and logical
/// operators with two operands. Subclasses need only implement the `calculate`
/// method.
abstract class ArithmeticOperationInstruction extends OverloadedImplementation {
  const ArithmeticOperationInstruction(NumberType numberType)
      : super(numberType);

  /// Pop two `numberType` elements from the stack, pass them to `calculate`
  /// and push the result back onto the stack.
  void execute(VM vm, _) {
    var arg1 = vm.popStack(valueType);
    var arg2 = vm.popStack(valueType);
    vm.pushStack(valueType, calculate(arg1, arg2));
  }

  /// Extension point for subclasses; implements the specific operation.
  num calculate(num op1, num op2);
}

/// Adds the two top stack elements.
class AddInstruction extends ArithmeticOperationInstruction {
  const AddInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a + b;

  String format(NumberType t) =>
      'add<${OverloadedImplementation._unifyIntegerNames(t)}>';
}

/// Subtracts the two top stack elements.
class SubtractInstruction extends ArithmeticOperationInstruction {
  const SubtractInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a - b;

  String format(NumberType t) =>
      'sub<${OverloadedImplementation._unifyIntegerNames(t)}>';
}

/// Multiplies the two top stack elements.
class MultiplyInstruction extends ArithmeticOperationInstruction {
  const MultiplyInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a * b;

  String format(NumberType t) =>
      'mul<${OverloadedImplementation._unifyIntegerNames(t)}>';
}

/// Divides the two top stack elements.
class DivideInstruction extends ArithmeticOperationInstruction {
  const DivideInstruction(numberType) : super(numberType);

  num calculate(num a, num b) =>
      valueType.memoryInterpretation == NumberType.float ? a / b : a ~/ b;

  String format(NumberType t) =>
      'div<${OverloadedImplementation._unifyIntegerNames(t)}>';
}

/// Calculates the modulo of the two top stack elements.
class ModuloInstruction extends ArithmeticOperationInstruction {
  const ModuloInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a % b;

  String format(NumberType t) =>
      'mod<${OverloadedImplementation._unifyIntegerNames(t)}>';
}

/// Arithmetic inversion of the top stack element.
class InverseInstruction extends OverloadedImplementation {
  const InverseInstruction(NumberType valueType) : super(valueType);

  void execute(VM vm, _) => vm.pushStack(valueType, -vm.popStack(valueType));

  String format(NumberType t) => 'neg<$t>';
}

/// Bitwise inverse of the top stack element.
class BitwiseNotInstruction extends OverloadedImplementation {
  const BitwiseNotInstruction(NumberType valueType) : super(valueType);

  void execute(VM vm, _) =>
      vm.pushStack(valueType, ~(vm.popStack(valueType) as int));

  String format(NumberType t) => 'inv<${t.sizeInBits}>';
}

/// Bitwise _and_ of the two top stack elements.
class BitwiseAndInstruction extends ArithmeticOperationInstruction {
  const BitwiseAndInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a & b;

  String format(NumberType t) => 'and<${t.sizeInBits}>';
}

/// Bitwise _or_ of the two top stack elements.
class BitwiseOrInstruction extends ArithmeticOperationInstruction {
  const BitwiseOrInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a | b;

  String format(NumberType t) => 'or<${t.sizeInBits}>';
}

/// Bitwise _xor_ of the two top stack elements.
class BitwiseExclusiveOrInstruction extends ArithmeticOperationInstruction {
  const BitwiseExclusiveOrInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a ^ b;

  String format(NumberType t) => 'xor<${t.sizeInBits}>';
}

/// Compares the two top stack elements using `==`.
class EqualsInstruction extends ArithmeticOperationInstruction {
  const EqualsInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a == b ? 1 : 0;

  String format(NumberType t) => 'eq<${t.sizeInBits}>';
}

/// Compares the two top stack elements using `>`.
class GreaterThanInstruction extends ArithmeticOperationInstruction {
  const GreaterThanInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a > b ? 1 : 0;

  String format(NumberType t) => 'gt<$t>';
}

/// Compares the two top stack elements using `≥`.
class GreaterEqualsInstruction extends ArithmeticOperationInstruction {
  const GreaterEqualsInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a >= b ? 1 : 0;

  String format(NumberType t) => 'ge<$t>';
}

/// Compares the two top stack elements using `<`.
class LessThanInstruction extends ArithmeticOperationInstruction {
  const LessThanInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a < b ? 1 : 0;

  String format(NumberType t) => 'lt<$t>';
}

/// Compares the two top stack elements using `≤`.
class LessEqualsInstruction extends ArithmeticOperationInstruction {
  const LessEqualsInstruction(numberType) : super(numberType);

  int calculate(num a, num b) => a <= b ? 1 : 0;

  String format(NumberType t) => 'le<$t>';
}

/// Logical negation of the top stack element.
class NegateInstruction extends InstructionImplementation {
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
