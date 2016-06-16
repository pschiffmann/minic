library minic.abstract_machine.instruction_set;

import 'vm.dart';

/// Allows lookup of an instructions opcode:
///
///     var instruction = new PushInstruction(NumberType.uint8);
///     print(instructionSet.lookup(instruction).opcode);
final Set<Instruction> instructionSet = new Set.from(VM.instructionSet);
