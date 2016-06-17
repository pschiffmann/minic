import 'dart:math' show pow;
import 'package:test/test.dart';
import 'package:minic/abstract_machine/code_generator.dart' show instructionSet;
import 'package:minic/abstract_machine/vm.dart';
import 'package:minic/memory.dart';

const isSegfaultSignal = const isInstanceOf<SegfaultSignal>();
final throwsSegfaultSignal = throwsA(isSegfaultSignal);

VM vm;
MemoryBlock program;
int _firstUnusedByteInProgram;

void encodeInstruction(Instruction instruction) => program.setValue(
    _firstUnusedByteInProgram++,
    NumberType.uint8,
    instructionSet.lookup(instruction).opcode);

void encodeImmediateArgument(NumberType size, num value) {
  program.setValue(_firstUnusedByteInProgram, size, value);
  _firstUnusedByteInProgram += size.sizeInBytes;
}

void main() {
  setUp(() {
    program = new MemoryBlock(256);
    vm = new VM(program, 256);
    _firstUnusedByteInProgram = 0;
  });

  group('VM', () {
    test('stack grows towards 0', () {
      var sp = vm.stackPointer;
      vm.pushStack(NumberType.uint8, 42);
      expect(vm.stackPointer, equals(sp - 1));
    });

    test('writing to out-of-bounds memory a address causes a segfault', () {
      expect(() => vm.setMemoryValue(999, NumberType.uint8, 1), throwsSegfaultSignal);
      expect(() => vm.setMemoryValue(-1, NumberType.uint8, 1), throwsSegfaultSignal);
    });

    test('reading from out-of-bounds memory a address causes a segfault', () {
      expect(() => vm.readMemoryValue(999, NumberType.uint8), throwsSegfaultSignal);
      expect(() => vm.readMemoryValue(-1, NumberType.uint8), throwsSegfaultSignal);
    });

    test('executing instruction not in memory causes a segfault', () {
      vm.programCounter = 999;
      expect(vm.executeNextInstruction, throwsSegfaultSignal);

      vm.programCounter = -1;
      expect(vm.executeNextInstruction, throwsSegfaultSignal);
    });

    test('executing undefined opcode causes a segfault', () {
      program.setValue(0, NumberType.uint8, 255);
      expect(vm.executeNextInstruction, throwsSegfaultSignal);
    });

    test('.executeNextInstruction() increases programCounter and respects immediate arguments', () {
      encodeInstruction(new PushInstruction(NumberType.uint8));
      encodeImmediateArgument(NumberType.uint8, 1);
      encodeInstruction(new PushInstruction(NumberType.uint16));
      encodeImmediateArgument(NumberType.uint16, 1);
      encodeInstruction(new TypeConversionInstruction(NumberType.uint16, NumberType.uint8));

      vm.executeNextInstruction();
      expect(vm.programCounter, equals(2));
      vm.executeNextInstruction();
      expect(vm.programCounter, equals(5));
      vm.executeNextInstruction();
      expect(vm.programCounter, equals(6));
    });
  });

  group('instruction set:', () {
    group('push', () {
      test('places immediate argument on the stack', () {
        var values = {
          NumberType.uint8: 11,
          NumberType.sint16: -123,
          NumberType.fp32: 4.25,
          NumberType.fp64: 3.141e-20,
          NumberType.sint64: -pow(2, 63)
        };
        values.forEach((numberType, value) {
          encodeInstruction(new PushInstruction(numberType));
          encodeImmediateArgument(numberType, value);

          vm.executeNextInstruction();
          expect(vm.popStack(numberType), equals(value));
        });
      });
    });
  });

}
