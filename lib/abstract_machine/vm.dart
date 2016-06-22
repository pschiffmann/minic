/// This library implements the target architecture of the minic compiler,
/// consisting of the [instruction set architecture][1] and a [virtual machine]
/// [2] that implements these instructions.
///
/// The code segment and runtime data each have their own address space of
/// 2^16B ≈ 65kB. The instruction set design is heavily inspired by the
/// [Java bytecode instructions][3]: All opcodes have a size of 1 byte, and the
/// following 0..8 bytes store one immediate argument. Because the VM has no
/// general-purpose registers, the instruction set is implemented as a stack
/// machine.
///
/// _A note about wording:
/// In this library, 'instruction' refers to an operation that can be performed
/// by the VM, and therefore to an instance of a subclass of [Instruction]. The
/// term 'opcode' refers to a single-byte integer that identifies such an
/// instruction. An opcode together with its operands is called 'instruction
/// invocation'._
///
/// [1]: https://en.wikipedia.org/wiki/Instruction_set
/// [2]: https://en.wikipedia.org/wiki/Virtual_machine
/// [3]: https://en.wikipedia.org/wiki/Java_bytecode_instruction_listings
library minic.abstract_machine.vm;

import '../memory.dart';

/// All opcodes have a size of one byte.
const NumberType opcodeSize = NumberType.uint8;

/// The VM uses 16-bit pointers, implying it can only address 2^16 bytes.
const NumberType addressSize = NumberType.uint16;

/// Some instructions (for example [AddInstruction]) don't distinct between
/// signed and unsigned integers. This method generates a string similar to
/// [NumberType#toString], but leaves out the sign prefix for integers.
String _unifyIntegerNames(NumberType t) => t.memoryInterpretation ==
    NumberType.float ? t.toString() : 'int${t.sizeInBits}';

/// This class serves as the context to a program execution by providing the
/// memory to store runtime data. This includes the organizational registers
/// and random access memory.
class VM {
  /// This list assigns an opcode to each supported instruction, which is simply
  /// 1 + the index of the respective instruction.
  static final List<Instruction> instructionSet = ((instructions) =>
      instructions
        ..forEach((instruction) =>
            instruction.opcode = 1 + instructions.indexOf(instruction)))([
    new PushInstruction(NumberType.uint8),
    new PushInstruction(NumberType.uint16),
    new PushInstruction(NumberType.uint32),
    new PushInstruction(NumberType.uint64),
    new PopInstruction(),
    new StackAllocateInstruction(),
    new FetchInstruction(),
    new StoreInstruction(),
    new LoadRelativeAddressInstruction(),
    new HaltInstruction(),
    new JumpInstruction(),
    new JumpInstruction(),
    new JumpZeroInstruction(),
    new CallInstruction(),
    new EnterFunctionInstruction(),
    new ReturnInstruction(),
    new TypeConversionInstruction(NumberType.sint8, NumberType.sint16),
    new TypeConversionInstruction(NumberType.sint16, NumberType.sint32),
    new TypeConversionInstruction(NumberType.sint32, NumberType.sint64),
    new TypeConversionInstruction(NumberType.uint32, NumberType.fp32),
    new TypeConversionInstruction(NumberType.sint32, NumberType.fp32),
    new TypeConversionInstruction(NumberType.fp32, NumberType.uint32),
    new TypeConversionInstruction(NumberType.fp32, NumberType.sint32),
    new TypeConversionInstruction(NumberType.uint64, NumberType.fp64),
    new TypeConversionInstruction(NumberType.sint64, NumberType.fp64),
    new TypeConversionInstruction(NumberType.fp64, NumberType.uint64),
    new TypeConversionInstruction(NumberType.fp64, NumberType.sint64),
    new TypeConversionInstruction(NumberType.fp32, NumberType.fp64),
    new TypeConversionInstruction(NumberType.fp64, NumberType.fp32),
    new AddInstruction(NumberType.uint8),
    new AddInstruction(NumberType.uint16),
    new AddInstruction(NumberType.uint32),
    new AddInstruction(NumberType.uint64),
    new AddInstruction(NumberType.fp32),
    new AddInstruction(NumberType.fp64),
    new SubtractInstruction(NumberType.uint8),
    new SubtractInstruction(NumberType.uint16),
    new SubtractInstruction(NumberType.uint32),
    new SubtractInstruction(NumberType.uint64),
    new SubtractInstruction(NumberType.fp32),
    new SubtractInstruction(NumberType.fp64),
    new MultiplyInstruction(NumberType.uint8),
    new MultiplyInstruction(NumberType.uint16),
    new MultiplyInstruction(NumberType.uint32),
    new MultiplyInstruction(NumberType.uint64),
    new MultiplyInstruction(NumberType.fp32),
    new MultiplyInstruction(NumberType.fp64),
    new DivideInstruction(NumberType.uint8),
    new DivideInstruction(NumberType.uint16),
    new DivideInstruction(NumberType.uint32),
    new DivideInstruction(NumberType.uint64),
    new DivideInstruction(NumberType.sint8),
    new DivideInstruction(NumberType.sint16),
    new DivideInstruction(NumberType.sint32),
    new DivideInstruction(NumberType.sint64),
    new DivideInstruction(NumberType.fp32),
    new DivideInstruction(NumberType.fp64),
    new ModuloInstruction(NumberType.uint8),
    new ModuloInstruction(NumberType.uint16),
    new ModuloInstruction(NumberType.uint32),
    new ModuloInstruction(NumberType.uint64),
    new ModuloInstruction(NumberType.sint8),
    new ModuloInstruction(NumberType.sint16),
    new ModuloInstruction(NumberType.sint32),
    new ModuloInstruction(NumberType.sint64),
    new ModuloInstruction(NumberType.fp32),
    new ModuloInstruction(NumberType.fp64),
    new BitwiseAndInstruction(NumberType.uint8),
    new BitwiseAndInstruction(NumberType.uint16),
    new BitwiseAndInstruction(NumberType.uint32),
    new BitwiseAndInstruction(NumberType.uint64),
    new BitwiseOrInstruction(NumberType.uint8),
    new BitwiseOrInstruction(NumberType.uint16),
    new BitwiseOrInstruction(NumberType.uint32),
    new BitwiseOrInstruction(NumberType.uint64),
    new BitwiseExclusiveOrInstruction(NumberType.uint8),
    new BitwiseExclusiveOrInstruction(NumberType.uint16),
    new BitwiseExclusiveOrInstruction(NumberType.uint32),
    new BitwiseExclusiveOrInstruction(NumberType.uint64),
    new EqualsInstruction(NumberType.uint8),
    new EqualsInstruction(NumberType.uint16),
    new EqualsInstruction(NumberType.uint32),
    new EqualsInstruction(NumberType.uint64),
    new EqualsInstruction(NumberType.fp32),
    new EqualsInstruction(NumberType.fp64),
    new GreaterThanInstruction(NumberType.uint8),
    new GreaterThanInstruction(NumberType.uint16),
    new GreaterThanInstruction(NumberType.uint32),
    new GreaterThanInstruction(NumberType.uint64),
    new GreaterThanInstruction(NumberType.sint8),
    new GreaterThanInstruction(NumberType.sint16),
    new GreaterThanInstruction(NumberType.sint32),
    new GreaterThanInstruction(NumberType.sint64),
    new GreaterThanInstruction(NumberType.fp32),
    new GreaterThanInstruction(NumberType.fp64),
    new GreaterEqualsInstruction(NumberType.uint8),
    new GreaterEqualsInstruction(NumberType.uint16),
    new GreaterEqualsInstruction(NumberType.uint32),
    new GreaterEqualsInstruction(NumberType.uint64),
    new GreaterEqualsInstruction(NumberType.sint8),
    new GreaterEqualsInstruction(NumberType.sint16),
    new GreaterEqualsInstruction(NumberType.sint32),
    new GreaterEqualsInstruction(NumberType.sint64),
    new GreaterEqualsInstruction(NumberType.fp32),
    new GreaterEqualsInstruction(NumberType.fp64),
    new LessThanInstruction(NumberType.uint8),
    new LessThanInstruction(NumberType.uint16),
    new LessThanInstruction(NumberType.uint32),
    new LessThanInstruction(NumberType.uint64),
    new LessThanInstruction(NumberType.sint8),
    new LessThanInstruction(NumberType.sint16),
    new LessThanInstruction(NumberType.sint32),
    new LessThanInstruction(NumberType.sint64),
    new LessThanInstruction(NumberType.fp32),
    new LessThanInstruction(NumberType.fp64),
    new LessEqualsInstruction(NumberType.uint8),
    new LessEqualsInstruction(NumberType.uint16),
    new LessEqualsInstruction(NumberType.uint32),
    new LessEqualsInstruction(NumberType.uint64),
    new LessEqualsInstruction(NumberType.sint8),
    new LessEqualsInstruction(NumberType.sint16),
    new LessEqualsInstruction(NumberType.sint32),
    new LessEqualsInstruction(NumberType.sint64),
    new LessEqualsInstruction(NumberType.fp32),
    new LessEqualsInstruction(NumberType.fp64),
    new ToggleBooleanInstruction()
  ]);

  /// The program that is executed when calling [run].
  final MemoryBlock program;

  /// Stores the index into [program] of the next instruction.
  int programCounter = 0;

  /// Combined stack and heap in a contiguous block of memory.
  ///
  /// The stack memory begins at `memory.size - 1` and grows towards zero, while
  /// the heap begins at zero and grows towards infinity.
  MemoryBlock memory;

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

  /// Initialize the VM with `memorySize` bytes available memory.
  ///
  /// Throw an `ArgumentError` when either `program.length` or `memorySize` are
  /// greater than the addressing limit of 2^16 bytes.
  VM(this.program, [int memorySize = 1 << 16])
      : memory = new MemoryBlock(memorySize),
        stackPointer = memorySize,
        framePointer = memorySize,
        extremePointer = memorySize {
    if (program.buffer.lengthInBytes > (1 << 16))
      throw new ArgumentError.value(
          program.buffer.lengthInBytes, 'program', 'maximum size is 2^16');
    if (memorySize > (1 << 16))
      throw new ArgumentError.value(
          memorySize, 'memorySize', 'maximum size is 2^16');
  }

  /// Run [program] until it terminates. Return the value returned from the
  /// programs `main` function.
  ///
  /// Throw [SegfaultSignal] when a runtime error occurs.
  int run() {
    try {
      while (true) executeNextInstruction();
    } on HaltSignal catch (signal) {
      return signal.statusCode;
    }
  }

  /// Execute the instruction invocation currently referenced by the instruction
  /// pointer.
  ///
  /// Throw [SegfaultSignal] when a runtime error occurs.
  void executeNextInstruction() {
    var instruction;
    try {
      var opcode = program.getValue(programCounter++, NumberType.uint8) - 1;
      instruction = instructionSet[opcode];
    } on RangeError {
      throw new SegfaultSignal(programCounter, 'Undefined opcode');
    }

    var immediateArgument;
    if (instruction.immediateArgumentSize != null) {
      immediateArgument =
          program.getValue(programCounter, instruction.immediateArgumentSize);
      programCounter += instruction.immediateArgumentSize.sizeInBytes;
    }
    instruction.execute(this, immediateArgument);
  }

  /// Read [memory] at address as the specified number type.
  num readMemoryValue(int address, NumberType numberType) {
    try {
      return memory.getValue(address, numberType);
    } on RangeError {
      throw new SegfaultSignal(address, 'Out of range');
    }
  }

  /// Read [memory] at the current stack pointer as the specified number type,
  /// then decrease the stack by the size of that value.
  num popStack(NumberType numberType) {
    var value = readMemoryValue(stackPointer, numberType);
    stackPointer += numberType.sizeInBytes;
    return value;
  }

  /// Insert value into [memory] at the specified address, encoded as the
  /// specified number type.
  void setMemoryValue(int address, NumberType numberType, num value) {
    try {
      memory.setValue(address, numberType, value);
    } on RangeError {
      throw new SegfaultSignal(address, 'Out of range');
    }
  }

  /// Encode value as the specified number type, increase the stack by the size
  /// of that value, then place the encoded value into [memory] at that address.
  void pushStack(NumberType numberType, num value) {
    stackPointer -= numberType.sizeInBytes;
    setMemoryValue(stackPointer, numberType, value);
  }
}

/// Implements a machine instruction that can be executed by a [VM].
///
/// Instructions are instantiated as constant objects because we need several
/// different versions of some of them. For example, we need integer addition
/// for 8, 16, 32 and 64 bit words, but don't want to implement 4 different
/// methods for it. Instead, [AddInstruction] is instantiated for each number
/// type.
abstract class Instruction {
  /// A verbose mnemonic for this instruction. If two instructions have the same
  /// name, they yield the same result if executed on a VM.
  String get name;

  /// This number of bytes immediately following this instruction are passed to
  /// [execute] as `immediateArgument`.
  NumberType get immediateArgumentSize => null;

  /// The opcode of this instruction. Is assigned by `VM.instructionSet`.
  int opcode;

  Instruction();

  /// Execute this instruction on `vm`.
  void execute(VM vm, num immediateArgument);

  /// Return true if this instruction yields the same result as `other` when
  /// executed on a VM. Because [name] generates strings with the same goal in
  /// mind, we can simply compare these strings.
  bool operator ==(Object other) => other is Instruction && name == other.name;

  /// Return the hash code of [name]. Look at [operator==] for an explanation.
  int get hashCode => name.hashCode;
}

/// Superclass for instructions that are overloaded with a single number type.
/// This includes all overloaded instructions except
/// [TypeConversionInstruction].
abstract class OverloadedInstruction extends Instruction {
  /// Size of the value that is pushed to the stack.
  final NumberType valueType;

  OverloadedInstruction(this.valueType);
}

/// Pushes the immediate argument on the stack.
class PushInstruction extends OverloadedInstruction {
  String get name => 'loadc<${valueType.sizeInBits}>';

  NumberType get immediateArgumentSize => valueType;

  PushInstruction(NumberType valueType) : super(valueType);

  void execute(VM vm, num value) {
    vm.pushStack(valueType, value);
  }
}

/// Reduces the stack by _n_ bytes, encoded as immediate argument.
class PopInstruction extends Instruction {
  String get name => 'pop';

  NumberType get immediateArgumentSize => NumberType.uint16;

  PopInstruction();

  void execute(VM vm, int numberOfBytes) {
    vm.stackPointer += numberOfBytes;
  }
}

/// Increases the stack by _n_ bytes, encoded as immediate argument.
class StackAllocateInstruction extends Instruction {
  String get name => 'alloc';

  NumberType get immediateArgumentSize => addressSize;

  StackAllocateInstruction();

  void execute(VM vm, int numberOfBytes) {
    vm.stackPointer -= numberOfBytes;
  }
}

/// Loads _n_ bytes from _address_ to the stack, where _n_ is encoded as
/// immediate argument in the instruction, and _address_ is read from the stack.
class FetchInstruction extends Instruction {
  String get name => 'loada';

  NumberType get immediateArgumentSize => addressSize;

  FetchInstruction();

  void execute(VM vm, int numberOfBytes) {
    var sourceAddress = vm.popStack(addressSize);
    var targetAddress = vm.stackPointer = vm.stackPointer - numberOfBytes;
    while (numberOfBytes > 0) {
      var chunk = const [
        NumberType.uint64,
        NumberType.uint32,
        NumberType.uint16,
        NumberType.uint8
      ].firstWhere((numberType) => numberOfBytes >= numberType.sizeInBytes);
      vm.setMemoryValue(
          targetAddress, chunk, vm.readMemoryValue(sourceAddress, chunk));
      numberOfBytes -= chunk.sizeInBytes;
      sourceAddress += chunk.sizeInBytes;
      targetAddress += chunk.sizeInBytes;
    }
  }
}

/// Stores _n_ bytes at _address_ on the stack, where _n_ is encoded as
/// immediate argument in the instruction, and _address_ is read from the stack.
class StoreInstruction extends Instruction {
  String get name => 'store';

  NumberType get immediateArgumentSize => addressSize;

  StoreInstruction();

  void execute(VM vm, num numberOfBytes) {
    var address = vm.popStack(addressSize);
    while (numberOfBytes > 0) {
      var chunk = const [
        NumberType.uint64,
        NumberType.uint32,
        NumberType.uint16,
        NumberType.uint8
      ].firstWhere((numberType) => numberOfBytes >= numberType.sizeInBytes);
      vm.setMemoryValue(address, chunk, vm.popStack(chunk));
      numberOfBytes -= chunk.sizeInBytes;
      address += chunk.sizeInBytes;
    }
  }
}

/// Load the value `vm.framePointer` - _immediate value_ to the stack.
class LoadRelativeAddressInstruction extends Instruction {
  String get name => 'loadr';

  NumberType get immediateArgumentSize => addressSize;

  LoadRelativeAddressInstruction();

  void execute(VM vm, int offset) {
    vm.pushStack(addressSize, vm.framePointer - offset);
  }
}

/// Halts the program execution by throwing [HaltSignal]. Reads the exit code
/// from the stack as `uint32`.
class HaltInstruction extends Instruction {
  String get name => 'halt';

  HaltInstruction();

  void execute(VM vm, _) =>
      throw new HaltSignal(vm.popStack(NumberType.uint32));
}

/// Sets the program counter to the immediate value.
class JumpInstruction extends Instruction {
  String get name => 'jump';

  NumberType get immediateArgumentSize => addressSize;

  JumpInstruction();

  void execute(VM vm, int address) {
    vm.programCounter = address;
  }
}

/// Pops the top byte from the stack; if it equals zero, jump to the immediate
/// address.
class JumpZeroInstruction extends Instruction {
  String get name => 'jumpz';

  NumberType get immediateArgumentSize => addressSize;

  JumpZeroInstruction();

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
class CallInstruction extends Instruction {
  String get name => 'call';

  NumberType get immediateArgumentSize => addressSize;

  CallInstruction();

  void execute(VM vm, int offset) {
    var jumpTarget = vm.popStack(addressSize);
    var oldStackPointer = vm.stackPointer;
    vm.pushStack(addressSize, vm.extremePointer);
    vm.pushStack(addressSize, vm.framePointer);
    vm.pushStack(addressSize, oldStackPointer + offset);
    vm.pushStack(addressSize, vm.programCounter);
    vm.programCounter = jumpTarget;
    vm.framePointer = vm.stackPointer;
  }
}

/// Completes the runtime context of a function invocation by setting the
/// extreme pointer.
class EnterFunctionInstruction extends Instruction {
  String get name => 'enter';

  NumberType get immediateArgumentSize => addressSize;

  EnterFunctionInstruction();

  void execute(VM vm, int offset) {
    vm.extremePointer = vm.framePointer - offset;
  }
}

/// Returns from a function call. Restores the organizational registers from the
/// backed up values on the stack.
class ReturnInstruction extends Instruction {
  String get name => 'return';

  ReturnInstruction();

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
/// type conversion `float↦uint32` on the value `1.0` yields `1` (which has
/// a different bit pattern).
///
/// The VM instruction set only supports a small subset of all to/from
/// conversion pairs, because a large part can be constructed with these and
/// other instructions:
///
///   * Casts between unsigned sizes can be done with `push<n> 0` and `pop n`,
///     where _n_ is the size difference.
///   * Reducing the size of signed integers can be done with `pop n`.
///   * Other casts not supported natively can be constructed in multiple steps;
///     for example `sint16↦float` can be implemented as
///     `sint16↦sint32, sint32↦float`.
///
/// The implemented instances are signed integer width expansion between
/// adjacent sizes,
///
///     sint8↦sint16
///     sint16↦sint32
///     sint32↦sint64
///
/// int/float conversion between same-size types,
///
///     uint32↦float
///     sint32↦float
///     float↦uint32
///     float↦sint32
///     uint64↦double
///     sint64↦double
///     double↦uint64
///     double↦sint64
///
/// and float/double conversion.
///
///     float↦double
///     double↦float
class TypeConversionInstruction extends Instruction {
  final NumberType from;
  final NumberType to;

  String get name => 'cast<$from↦$to>';

  TypeConversionInstruction(this.from, this.to);

  void execute(VM vm, _) => vm.pushStack(to, vm.popStack(from));
}

/// Superclass for all side effect-free arithmetic and bitwise operators with
/// two operands. Subclasses need only implement the `calculate` method.
abstract class ArithmeticOperationInstruction extends OverloadedInstruction {
  ArithmeticOperationInstruction(NumberType numberType) : super(numberType);

  /// Pop two `numberType` elements from the stack, pass them to `calculate`
  /// and push the result back onto the stack.
  void execute(VM vm, _) {
    var arg2 = vm.popStack(valueType);
    var arg1 = vm.popStack(valueType);
    vm.pushStack(valueType, calculate(arg1, arg2));
  }

  /// Extension point for subclasses; implements the specific operation.
  num calculate(num op1, num op2);
}

/// Adds the two top stack elements.
class AddInstruction extends ArithmeticOperationInstruction {
  String get name => 'add<${_unifyIntegerNames(valueType)}>';

  AddInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a + b;
}

/// Subtracts the two top stack elements.
class SubtractInstruction extends ArithmeticOperationInstruction {
  String get name => 'sub<${_unifyIntegerNames(valueType)}>';

  SubtractInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a - b;
}

/// Multiplies the two top stack elements.
class MultiplyInstruction extends ArithmeticOperationInstruction {
  String get name => 'mul<${_unifyIntegerNames(valueType)}>';

  MultiplyInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a * b;
}

/// Divides the two top stack elements.
class DivideInstruction extends ArithmeticOperationInstruction {
  String get name => 'div<$valueType>';

  DivideInstruction(numberType) : super(numberType);

  num calculate(num a, num b) =>
      valueType.memoryInterpretation == NumberType.float ? a / b : a ~/ b;
}

/// Calculates the modulo of the two top stack elements.
class ModuloInstruction extends ArithmeticOperationInstruction {
  String get name => 'mod<$valueType>';

  ModuloInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a % b;
}

/// Bitwise _and_ of the two top stack elements.
class BitwiseAndInstruction extends ArithmeticOperationInstruction {
  String get name => 'and<${valueType.sizeInBits}>';

  BitwiseAndInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a & b;
}

/// Bitwise _or_ of the two top stack elements.
class BitwiseOrInstruction extends ArithmeticOperationInstruction {
  String get name => 'or<${valueType.sizeInBits}>';

  BitwiseOrInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a | b;
}

/// Bitwise _xor_ of the two top stack elements.
class BitwiseExclusiveOrInstruction extends ArithmeticOperationInstruction {
  String get name => 'xor<${valueType.sizeInBits}>';

  BitwiseExclusiveOrInstruction(numberType) : super(numberType);

  int calculate(int a, int b) => a ^ b;
}

/// Superclass for all side effect-free comparison operators. Subclasses need
/// only implement the `compare` method.
///
/// The result is always a single byte, indipendent from the operand size.
abstract class ComparisonInstruction extends OverloadedInstruction {
  ComparisonInstruction(numberType) : super(numberType);

  void execute(VM vm, _) {
    var op2 = vm.popStack(valueType);
    var op1 = vm.popStack(valueType);
    vm.pushStack(NumberType.uint8, compare(op1, op2) ? 1 : 0);
  }

  bool compare(num a, num b);
}

/// Compares the two top stack elements using `==`.
class EqualsInstruction extends ComparisonInstruction {
  String get name => 'eq<${_unifyIntegerNames(valueType)}>';

  EqualsInstruction(numberType) : super(numberType);

  bool compare(num a, num b) => a == b;
}

/// Compares the two top stack elements using `>`.
class GreaterThanInstruction extends ComparisonInstruction {
  String get name => 'gt<$valueType>';

  GreaterThanInstruction(numberType) : super(numberType);

  bool compare(num a, num b) => a > b;
}

/// Compares the two top stack elements using `≥`.
class GreaterEqualsInstruction extends ComparisonInstruction {
  String get name => 'ge<$valueType>';

  GreaterEqualsInstruction(numberType) : super(numberType);

  bool compare(num a, num b) => a >= b;
}

/// Compares the two top stack elements using `<`.
class LessThanInstruction extends ComparisonInstruction {
  String get name => 'lt<$valueType>';

  LessThanInstruction(numberType) : super(numberType);

  bool compare(num a, num b) => a < b;
}

/// Compares the two top stack elements using `≤`.
class LessEqualsInstruction extends ComparisonInstruction {
  String get name => 'le<$valueType>';

  LessEqualsInstruction(numberType) : super(numberType);

  bool compare(num a, num b) => a <= b;
}

/// Logical negation of the top stack element.
class ToggleBooleanInstruction extends Instruction {
  String get name => 'not';

  ToggleBooleanInstruction();

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
