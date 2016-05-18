import 'package:test/test.dart';
import 'package:minic/src/abstract_machine/vm.dart';
import 'package:minic/src/memory.dart';

void main() {
  VM vm = new VM([]);

  group('InstructionSet', () {});
  test('AddInstruction sums two stack values', () {
    vm.pushStack(NumberType.uint8, 2);
    vm.pushStack(NumberType.uint8, 4);
    (new AddInstruction(NumberType.uint8)).execute(vm, 0);
    expect(vm.readMemoryValue(vm.stackPointer, NumberType.uint8), 2 + 4);
  });

  test('PushInstruction pushes value on the stack', () {
    var sp = vm.stackPointer - NumberType.uint8.sizeInBytes;
    (new PushInstruction(NumberType.uint8)).execute(vm, 4);
    expect(vm.stackPointer, sp);
    expect(vm.readMemoryValue(vm.stackPointer, NumberType.uint8), 4);
  });
}
