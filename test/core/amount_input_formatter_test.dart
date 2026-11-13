
import 'package:al_hisob/core/widgets/amount_input_formatter.dart';

void main() {
  String format(String typed, {int? max}) => AmountInputFormatter(max: max)
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: typed))
      .text;

  group('без предела', () {
    test('группирует по три и убирает лишнее', () {
      expect(format('1250000'), '1 250 000');
      expect(format('12a3'), '123');
      expect(format(''), '');
    });
  });

  group('с пределом', () {
    test('число в пределах не меняется', () {
      expect(format('500', max: 1000), '500');
      expect(format('1000', max: 1000), '1 000');
    });

    test('число больше предела заменяется пределом', () {
      expect(format('1001', max: 1000), '1 000');
      expect(format('2000', max: 1000), '1 000');
      expect(format('999999999', max: 1250000), '1 250 000');
    });

    test('предел 0: ввести ничего нельзя', () {
      expect(format('5', max: 0), '');
    });

    test('курсор ставится в конец', () {
      final v = const AmountInputFormatter(max: 1000)
          .formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '5000'));
      expect(v.selection.baseOffset, v.text.length);
    });
  });
}
