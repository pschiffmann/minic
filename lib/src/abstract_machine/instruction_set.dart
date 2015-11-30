library minic.src.abstract_machine.instruction_set;

import 'vm.dart';

abstract class Instruction {
  execute(VM vm, [int immediateArgument]);
}

abstract class ArithmeticOperationInstruction implements Instruction {
  final NumberType numberType;

  const ArithmeticOperationInstruction(this.numberType);

  int execute(VM vm, [_]) {
    var result = calculate(vm.popStack(numberType), vm.popStack(numberType));
    vm.pushStack(numberType, result);
    return result > numberTypeBitmasks[numberType] ? 1 : 0;
  }

  num calculate(num op1, num op2);
}

class AddInstruction extends ArithmeticOperationInstruction {
  const AddInstruction(numberType) : super(numberType);

  num calculate(num a, num b) => a + b;
}
