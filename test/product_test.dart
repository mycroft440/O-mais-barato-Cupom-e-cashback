import 'package:flutter_test/flutter_test.dart';
import 'package:o_mais_barato/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preço final aplica desconto do cupom', () {
    const product = Product(
      id: '1',
      name: 'Produto',
      category: 'Tecnologia',
      brand: 'Marca',
      marketplace: 'Loja',
      price: 100,
      originalPrice: 150,
      tags: ['teste'],
      couponDiscount: 20,
    );

    expect(product.finalPrice, 80);
    expect(product.discountPercent, closeTo(46.666, 0.01));
  });

  test('recomendação favorece interesse aprendido', () {
    final engine = PreferenceEngine();
    const tech = Product(
      id: 't',
      name: 'Notebook',
      category: 'Tecnologia',
      brand: 'Marca T',
      marketplace: 'Loja',
      price: 1000,
      originalPrice: 1000,
      tags: ['notebook'],
    );
    const roupa = Product(
      id: 'r',
      name: 'Camiseta',
      category: 'Roupas',
      brand: 'Marca R',
      marketplace: 'Loja',
      price: 100,
      originalPrice: 100,
      tags: ['camiseta'],
    );

    engine.registerClick(tech);
    final ranked = engine.recommend([roupa, tech]);
    expect(ranked.first.id, 't');
  });
}
