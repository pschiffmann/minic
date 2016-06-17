import 'dart:math' show pow, Random;
import 'package:test/test.dart';
import 'package:minic/abstract_machine/code_generator.dart' show instructionSet;
import 'package:minic/abstract_machine/vm.dart';
import 'package:minic/memory.dart';

const isSegfaultSignal = const isInstanceOf<SegfaultSignal>();
final throwsSegfaultSignal = throwsA(isSegfaultSignal);

VM vm;
MemoryBlock program;
int _firstUnusedByteInProgram;

void encodeInstruction(Instruction instruction, [int address]) =>
    program.setValue(address ?? _firstUnusedByteInProgram++, NumberType.uint8,
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

    group('pop', () {
      test('reduces stack size by immediate argument value', () {
        encodeInstruction(new PopInstruction());
        encodeImmediateArgument(NumberType.uint16, 20);
        vm.stackPointer = 32;

        vm.executeNextInstruction();
        expect(vm.stackPointer, equals(52));
      });
    });

    group('alloc', () {
      test('increases stack size by immediate argument value', () {
        encodeInstruction(new StackAllocateInstruction());
        encodeImmediateArgument(NumberType.uint16, 20);
        vm.stackPointer = 32;

        vm.executeNextInstruction();
        expect(vm.stackPointer, equals(12));
      });
    });

    group('loada', () {
      for (var numberOfBytes in new Iterable.generate(20, (x) => x + 1)) {
        test('fetches memory chunks of $numberOfBytes bytes', () {
          var random = new Random(numberOfBytes);
          var dataAddress = random.nextInt(200);
          var data = new List.generate(numberOfBytes,
              (x) => random.nextInt(255));

          // create test data
          for (int i = 0; i < data.length; i++) {
            vm.setMemoryValue(dataAddress + i, NumberType.uint8, data[i]);
          }

          // execute instruction
          vm.pushStack(addressSize, dataAddress);
          encodeInstruction(new FetchInstruction());
          encodeImmediateArgument(addressSize, numberOfBytes);
          vm.executeNextInstruction();

          // validate copied data
          for (int i in data) {
            expect(vm.popStack(NumberType.uint8), equals(i));
          }
        });
      }
    });

    group('store', () {
      for (var numberOfBytes in new Iterable.generate(20, (x) => x + 1)) {
        test('moves memory chunks of $numberOfBytes bytes', () {
          var random = new Random(numberOfBytes);
          var dataAddress = random.nextInt(200);
          var data = new List.generate(numberOfBytes,
              (x) => random.nextInt(255));

          // create test data
          for (int i in data.reversed) {
            vm.pushStack(NumberType.uint8, i);
          }

          // execute instruction
          vm.pushStack(addressSize, dataAddress);
          encodeInstruction(new StoreInstruction());
          encodeImmediateArgument(addressSize, numberOfBytes);
          vm.executeNextInstruction();

          // validate copied data
          for (int i = 0; i < data.length; i++) {
            expect(vm.readMemoryValue(dataAddress + i, NumberType.uint8),
                equals(data[i]));
          }
        });
      }
    });

    group('loadr', () {
      test('offsets immediate argument by current frame pointer', () {
        vm.framePointer = vm.stackPointer = 100;
        encodeInstruction(new LoadRelativeAddressInstruction());
        encodeImmediateArgument(addressSize, 20);
        vm.executeNextInstruction();
        expect(vm.popStack(addressSize), equals(80));
      });

      test('can target addresses outside of the current frame', () {
        vm.framePointer = vm.stackPointer = 100;
        encodeInstruction(new LoadRelativeAddressInstruction());
        encodeImmediateArgument(addressSize, -10);
        vm.executeNextInstruction();
        expect(vm.popStack(addressSize), equals(110));
      });
    });

    group('halt', () {
      test('throws HaltSignal with exit code from stack', () {
        vm.pushStack(NumberType.uint32, 156);
        encodeInstruction(new HaltInstruction());
        expect(vm.executeNextInstruction, throwsA(predicate(
            (signal) => signal is HaltSignal && signal.statusCode == 156)));
      });
    });

    group('jump', () {
      test('sets VM.programCounter to immediate value', () {
        encodeInstruction(new JumpInstruction());
        encodeImmediateArgument(addressSize, 33);
        vm.executeNextInstruction();
        expect(vm.programCounter, equals(33));
      });
    });

    group('jumpz', () {
      test('jumps to immediate value if top stack byte is 0', () {
        vm.pushStack(NumberType.uint8, 0);
        encodeInstruction(new JumpZeroInstruction());
        encodeImmediateArgument(addressSize, 9);
        vm.executeNextInstruction();
        expect(vm.programCounter, equals(9));
      });

      test('advances as normal if top stack byte is not 0', () {
        vm.pushStack(NumberType.uint8, 22);
        encodeInstruction(new JumpZeroInstruction());
        encodeImmediateArgument(addressSize, 78);
        vm.executeNextInstruction();
        expect(vm.programCounter, equals(3));
      });
    });

    group('call / return', () {
      test('call backs up and overrides SP, FP and PC', () {
        vm.programCounter = 78;
        vm.stackPointer = 155;
        vm.framePointer = 150;
        vm.extremePointer = 140;
        var expectedNewStackPointer = vm.stackPointer - 4 * addressSize.sizeInBytes;

        encodeInstruction(new CallInstruction(), 78);
        vm.pushStack(addressSize, 199);
        vm.executeNextInstruction();

        expect(vm.stackPointer, equals(expectedNewStackPointer));
        expect(vm.framePointer, equals(expectedNewStackPointer));
        expect(vm.programCounter, equals(199));

        expect(vm.popStack(addressSize), equals(78 + 3));
        expect(vm.popStack(addressSize), equals(155));
        expect(vm.popStack(addressSize), equals(150));
        expect(vm.popStack(addressSize), equals(140));
      });

      test('return restores SP, FP, EP, PC', () {
        vm.stackPointer = 220;
        vm.framePointer = 230;
        vm.extremePointer = 210;
        vm.programCounter = 10;
        encodeInstruction(new CallInstruction(), 10);
        encodeInstruction(new ReturnInstruction(), 50);
        vm.pushStack(addressSize, 50);

        vm.executeNextInstruction();
        vm.executeNextInstruction();

        expect(vm.stackPointer, equals(220));
        expect(vm.framePointer, equals(230));
        expect(vm.extremePointer, equals(210));
        expect(vm.programCounter, equals(13));
      });
    });

    group('enter', () {
      test('sets extreme pointer to immediate argument', () {
        vm.framePointer = 53;
        encodeInstruction(new EnterFunctionInstruction());
        encodeImmediateArgument(addressSize, 23);
        vm.executeNextInstruction();
        expect(vm.extremePointer, equals(30));
      });
    });
  });
}
