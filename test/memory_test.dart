import 'package:test/test.dart';
import 'package:minic/memory.dart';

void main() {
  group('[MemoryBlock]:', () {
    test('setValue converts values before insertion', () {
      var memory = new MemoryBlock(8);

      memory.setValue(0, NumberType.uint8, 1.0);
      expect(memory.getValue(0, NumberType.uint8), equals(1));

      memory.setValue(0, NumberType.fp32, 1);
      expect(memory.getValue(0, NumberType.fp32), equals(1.0));
    });
  });
}
