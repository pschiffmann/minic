library minic.src.cmachine;

import 'dart:typed_data';
import 'dart:math' show pow;

class VM {
  /// Combined stack and heap in a continous block of memory.
  ///
  /// The stack memory begins at `memory.size - 1` and grows towards zero, while
  /// the heap begins at zero and grows towards infinity.
  ByteData memory;

  /// Points to the lowest currently used address of the stack (in [memory]).
  int stackPointer;

  /// Points to the highest currently used address of the heap (in [memory]).
  int framePointer;

  /// Points to the highest stack index the current function might allocate.
  int extremePointer;

  /// Stores the index into the program code of the next instruction.
  int programCounter;

  VM() : memory = new ByteData.view(new Uint8List(8).buffer);

  /// Execute [instruction] on the current data.
  ///
  /// An instruction is a 32-bit integer with the following sections, ordered
  /// from hsb to lsb:
  ///    ?? bit instruction code: Identifies the assembly instruction. The value
  ///           used is the respective index into [InstructionCode] left shifted
  ///           by 56.
  ///    ?? bit type hints: Only used to arithmetic instructions. Bits in this
  ///           byte are interpreted as flags. The first two bits indicate the
  ///           type (00: unsigned int, 01: signed int, 10: float), the next 3
  ///           bits store the operand size - 1 in bytes (for ints between 0 and
  ///           7, for floats either 3 or 7). The remaining 3 bits aren't used.
  ///   ?? bit operands: ...
  ///
  void execute(int instruction) {
    throw new UnimplementedError();
  }

  /// Take back the last executed instruction.
  ///
  /// Implementation note: use [command]
  /// (http://gameprogrammingpatterns.com/command.html) pattern internally.
  void rollback() {
    throw new UnimplementedError();
  }

  num readMemoryValue(int address, NumberType numberType) {
    switch (numberType) {
      case NumberType.int8:
        return memory.getInt8(address);
      case NumberType.int16:
        return memory.getInt16(address);
      case NumberType.int32:
        return memory.getInt32(address);
      case NumberType.int64:
        return memory.getInt64(address);
      case NumberType.fp32:
        return memory.getFloat32(address);
      case NumberType.fp64:
        return memory.getFloat64(address);
    }
  }

  num popStack(NumberType numberType) {
    var value = readMemoryValue(stackPointer, numberType);
    stackPointer -= numberTypeByteCount[numberType];
    return value;
  }

  void setMemoryValue(int address, NumberType numberType, num value) {
    if (numberType == NumberType.fp32 || numberType == NumberType.fp64) value =
        value.toDouble();
    else value = value.toInt() & numberTypeBitmasks[numberType];

    switch (numberType) {
      case NumberType.int8:
        memory.setInt8(address, value);
        break;
      case NumberType.int16:
        memory.setInt16(address, value);
        break;
      case NumberType.int32:
        memory.setInt32(address, value);
        break;
      case NumberType.int64:
        memory.setInt64(address, value);
        break;
      case NumberType.fp32:
        memory.setFloat32(address, value);
        break;
      case NumberType.fp64:
        memory.setFloat64(address, value);
        break;
    }
  }

  void pushStack(NumberType numberType, num value) {
    stackPointer += numberTypeByteCount[numberType];
    setMemoryValue(stackPointer, numberType, value);
  }
}

enum NumberType {
  int8,
  int16,
  int32,
  int64,
  fp32,
  fp64
}

final Map<NumberType, int> numberTypeByteCount = {
  NumberType.int8: 1,
  NumberType.int16: 2,
  NumberType.int32: 4,
  NumberType.int64: 8
};

final Map<NumberType, int> numberTypeBitmasks =
    new Map<NumberType, int>.fromIterable(numberTypeByteCount.keys,
        key: (numberType) => numberType,
        value: (numberType) => pow(2, 8 * numberTypeByteCount[numberType]) - 1);
