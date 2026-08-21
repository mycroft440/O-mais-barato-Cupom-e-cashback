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

  test('comparador retorna somente o anúncio mais barato do mesmo produto', () {
    const listings = [
      Product(
        id: 'a',
        name: 'Tênis X',
        category: 'Roupas',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 200,
        originalPrice: 300,
        tags: ['tênis'],
        catalogProductId: 'tenis-x',
      ),
      Product(
        id: 'b',
        name: 'Tênis X',
        category: 'Roupas',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 280,
        originalPrice: 300,
        tags: ['tênis'],
        catalogProductId: 'tenis-x',
      ),
      Product(
        id: 'c',
        name: 'Tênis X',
        category: 'Roupas',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 300,
        originalPrice: 300,
        tags: ['tênis'],
        catalogProductId: 'tenis-x',
      ),
    ];

    final winners = MarketComparator.cheapestPerProduct(listings);
    expect(winners, hasLength(1));
    expect(winners.first.id, 'a');
    expect(winners.first.comparisonPrice, 290);
    expect(winners.first.comparedListings, 3);
    expect(winners.first.savingsVsPeersPercent, closeTo(31.03, 0.02));
  });

  test('feed inclui o menor preço mesmo quando diferença é só 5%', () {
    const listings = [
      Product(
        id: 'a',
        name: 'Produto A',
        category: 'Tecnologia',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 95,
        originalPrice: 100,
        tags: [],
        catalogProductId: 'produto-a',
      ),
      Product(
        id: 'b',
        name: 'Produto A',
        category: 'Tecnologia',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 100,
        originalPrice: 100,
        tags: [],
        catalogProductId: 'produto-a',
      ),
    ];

    final feed = MarketComparator.dealFeed(listings);

    expect(feed, hasLength(1));
    expect(feed.first.id, 'a');
    expect(feed.first.finalPrice, 95);
    expect(feed.first.savingsVsPeersPercent, closeTo(5, 0.01));
  });

  test('feed não aplica corte antigo mesmo se parâmetro for informado', () {
    const listings = [
      Product(
        id: 'a',
        name: 'Produto A',
        category: 'Tecnologia',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 98,
        originalPrice: 100,
        tags: [],
        catalogProductId: 'produto-a',
      ),
      Product(
        id: 'b',
        name: 'Produto A',
        category: 'Tecnologia',
        brand: 'Marca',
        marketplace: 'Loja',
        price: 100,
        originalPrice: 100,
        tags: [],
        catalogProductId: 'produto-a',
      ),
    ];

    final feed = MarketComparator.dealFeed(
      listings,
      minSavingsPercent: 20,
    );

    expect(feed.map((e) => e.id), ['a']);
  });
}
