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

    test('handles range overflow by cropping most significant bits', () {
      var memory = new MemoryBlock(8);

      memory.setValue(0, NumberType.uint8, 257);
      expect(memory.getValue(0, NumberType.uint8), equals(1));
    });

    test('arranges bytes in big endian order', () {
      var memory = new MemoryBlock(8);

      memory.setValue(0, NumberType.uint16, 258);
      expect(memory.getValue(0, NumberType.uint8), equals(1));
      expect(memory.getValue(1, NumberType.uint8), equals(2));
    });
  });
}
