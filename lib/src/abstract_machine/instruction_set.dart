library minic.src.abstract_machine.instruction_set;

import 'dart:math';
import 'dart:typed_data';

import 'vm.dart';
import '../util.dart';

/// This class compiles a list of [Instruction]s into an instruction set. It
/// derives the size (in bytes) of the binary encoding and the codes from its
/// instructions.
class InstructionSet {
  final List<Instruction> instructions;

  /// Number of bytes needed to store distinct numbers for each instruction.
  final int codeWidth;

  /// Remaining bytes in an encoded instruction after the instruction code
  /// (instructionWidth - codeWidth).  At least large enough to store immediate
  /// arguments of all instructions.
  final int argumentWidth;

  /// Number of bytes that are used to store an encoded instruction. Always a
  /// power of 2.
  int get instructionWidth => codeWidth + argumentWidth;

  /// Masks the instruction code in an encoded instruction.
  int get codeBitmask => (pow(2, codeWidth) - 1).toInt() << argumentWidth * 8;

  /// Masks the immediate argument in an encoded instruction.
  int get argumentBitmask => pow(2, argumentWidth) - 1;

  /// Initialize an instruction set for the given instructions.
  ///
  /// The index of an instruction in the assigned list is used as its code.
  factory InstructionSet.fromInstructions(List<Instruction> instructions) {
    var codeWidth = calculateRequiredBytes(instructions.length);
    var argumentWidth = instructions.fold(
        0,
        (int prev, instruction) =>
            max(prev, instruction.immediateArgumentSize));
    return new InstructionSet._internal(instructions, codeWidth, argumentWidth);
  }

  const InstructionSet._internal(
      this.instructions, this.codeWidth, this.argumentWidth);

  /// Retrieve the instruction object matching the assigned instruction code.
  Instruction decode(int instructionCode) {
    var index = (instructionCode & codeBitmask) >> argumentWidth * 8;
    if (index >= instructions.length) {
      throw new ArgumentError.value(instructionCode, "Unrecognized code");
    }
    return instructions[index];
  }

  /// Return the number value representing the assigned instruction.
  ///
  /// The __argument__ part of the return value is set to 0 and needs to be
  /// filled accordingly afterwards.
  ///
  /// Throws [ArgumentError] if `instruction` is not in this instruction set.
  int encode(Instruction instruction) {
    var index = instructions.indexOf(instruction);
    if (index < 0) throw new ArgumentError.value(
        instruction, "not in this instruction set");
    return index << argumentWidth * 8;
  }
}

/// Defines the interface between [VM] and instructions.
///
/// Instructions are instantiated as const objects because we need several
/// different versions of some instructions. For example, [VM] supports integer
/// addition for 8, 16, 32 and 64 bit words. We save a lot of copy-paste by
/// creating four [AddInstruction] objects with appropriate sizes.
abstract class Instruction {

  static ByteData _reinterpreter = new ByteData.view(new Uint8List(8).buffer);

  /// Either the type of the expected immediate argument that [execute] must be
  /// called with, or null.
  NumberType get expectedArgument;

  /// Size of [expectedArgument] in bytes.
  int get argumentSize =>
      expectedArgument == null ? 0 : numberTypeByteCount[expectedArgument];

  const Instruction();

  /// Execute this instruction on `vm`.
  ///
  /// If [expectedArgument] is not null, the VM will pass `immediateArgument` as
  /// second parameter.
  ///
  /// This method may return a boolean to set the carry flag in the VM. If this
  /// method returns null, the VM will reset the carry flag automatically.
  execute(VM vm, num immediateArgument);

  ///
  num extractImmediateArgument(int rawArgumentBytes) {
    _reinterpreter.setUint64(0, rawArgumentBytes & numberTypeBitmasks[expectedArgument]);
    switch (expectedArgument) {
      case NumberType.int8:
        return _reinterpreter.getInt8(0);
      case NumberType.int16:
        return _reinterpreter.getInt16(0);
      case NumberType.int32:
        return _reinterpreter.getInt32(0);
      case NumberType.int64:
        return _reinterpreter.getInt64(0);
      case NumberType.fp32:
        return _reinterpreter.getFloat32(0);
      case NumberType.fp64:
        return _reinterpreter.getFloat64(0);
      default:
        return 0;
    }
  }
}

class PushInstruction extends Instruction {
  final NumberType valueType;

  const PushInstruction(this.valueType);

  void execute(VM vm, num value) {
    vm.pushStack(valueType, value);
  }

  NumberType get expectedArgument => valueType;
}

abstract class ArithmeticOperationInstruction extends Instruction {
  final NumberType numberType;

  NumberType get expectedArgument => null;

  const ArithmeticOperationInstruction(this.numberType);

  bool execute(VM vm, _) {
    var result = calculate(vm.popStack(numberType), vm.popStack(numberType));
    vm.pushStack(numberType, result);
    return result > numberTypeBitmasks[numberType];
  }

  num calculate(num op1, num op2);
}

class AddInstruction extends ArithmeticOperationInstruction {
  const AddInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a + b;
}
