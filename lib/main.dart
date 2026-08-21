import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaisBaratoApp());
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.brand,
    required this.marketplace,
    required this.price,
    required this.originalPrice,
    required this.tags,
    this.couponCode,
    this.couponDiscount = 0,
    this.couponVerified = false,
    this.lastCouponCheckMinutes = 999,
    this.catalogProductId,
    this.seller,
    this.imageUrl,
    this.productUrl,
    this.comparisonPrice,
    this.comparedListings = 1,
    this.popularityPosition,
  });

  final String id;
  final String name;
  final String category;
  final String brand;
  final String marketplace;
  final double price;
  final double originalPrice;
  final List<String> tags;
  final String? couponCode;
  final double couponDiscount;
  final bool couponVerified;
  final int lastCouponCheckMinutes;
  final String? catalogProductId;
  final String? seller;
  final String? imageUrl;
  final String? productUrl;
  final double? comparisonPrice;
  final int comparedListings;
  final int? popularityPosition;

  double get finalPrice =>
      (price - couponDiscount).clamp(0, double.infinity).toDouble();

  double get discountPercent =>
      originalPrice <= 0 ? 0 : (1 - finalPrice / originalPrice) * 100;

  double get savingsVsPeersPercent {
    final ref = comparisonPrice;
    if (ref == null || ref <= 0 || finalPrice >= ref) return 0;
    return (1 - finalPrice / ref) * 100;
  }

  bool get isCheapestCompared =>
      comparisonPrice != null && comparedListings > 1 && savingsVsPeersPercent > 0;

  Product copyWith({
    double? comparisonPrice,
    int? comparedListings,
    int? popularityPosition,
  }) {
    return Product(
      id: id,
      name: name,
      category: category,
      brand: brand,
      marketplace: marketplace,
      price: price,
      originalPrice: originalPrice,
      tags: tags,
      couponCode: couponCode,
      couponDiscount: couponDiscount,
      couponVerified: couponVerified,
      lastCouponCheckMinutes: lastCouponCheckMinutes,
      catalogProductId: catalogProductId,
      seller: seller,
      imageUrl: imageUrl,
      productUrl: productUrl,
      comparisonPrice: comparisonPrice ?? this.comparisonPrice,
      comparedListings: comparedListings ?? this.comparedListings,
      popularityPosition: popularityPosition ?? this.popularityPosition,
    );
  }

  factory Product.fromApi(Map<String, dynamic> json) => Product(
        id: json['item_id'] as String? ?? json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Produto',
        category: json['category'] as String? ?? 'Outros',
        brand: json['brand'] as String? ?? '',
        marketplace: json['marketplace'] as String? ?? 'Mercado Livre',
        price: (json['price'] as num? ?? 0).toDouble(),
        originalPrice:
            (json['original_price'] as num? ?? json['price'] as num? ?? 0)
                .toDouble(),
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        couponCode: json['coupon_code'] as String?,
        couponDiscount: (json['coupon_discount'] as num? ?? 0).toDouble(),
        couponVerified: json['coupon_verified'] as bool? ?? false,
        lastCouponCheckMinutes:
            (json['last_coupon_check_minutes'] as num? ?? 999).toInt(),
        catalogProductId: json['catalog_product_id'] as String?,
        seller: json['seller'] as String?,
        imageUrl: json['image_url'] as String?,
        productUrl: json['product_url'] as String?,
        comparisonPrice: (json['comparison_price'] as num?)?.toDouble(),
        comparedListings: (json['compared_listings'] as num? ?? 1).toInt(),
        popularityPosition: (json['popularity_position'] as num?)?.toInt(),
      );
}

class WishItem {
  WishItem({
    required this.productId,
    required this.months,
    required this.createdAt,
    this.targetPrice,
    this.alertCoupon = true,
    this.alertLowerPrice = true,
  });

  final String productId;
  final int months;
  final DateTime createdAt;
  final double? targetPrice;
  final bool alertCoupon;
  final bool alertLowerPrice;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'months': months,
        'createdAt': createdAt.toIso8601String(),
        'targetPrice': targetPrice,
        'alertCoupon': alertCoupon,
        'alertLowerPrice': alertLowerPrice,
      };

  factory WishItem.fromJson(Map<String, dynamic> json) => WishItem(
        productId: json['productId'] as String,
        months: json['months'] as int? ?? 3,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        targetPrice: (json['targetPrice'] as num?)?.toDouble(),
        alertCoupon: json['alertCoupon'] as bool? ?? true,
        alertLowerPrice: json['alertLowerPrice'] as bool? ?? true,
      );
}

class PreferenceEngine extends ChangeNotifier {
  static const categories = <String>[
    'Roupas',
    'Acessórios',
    'Brinquedos',
    'Tecnologia',
    'Suplementos',
  ];

  final Map<String, double> _weights = {};
  final Set<String> _explicit = {};
  final List<String> _recentSearches = [];
  final List<WishItem> _wishlist = [];

  Map<String, double> get weights => Map.unmodifiable(_weights);
  Set<String> get explicit => Set.unmodifiable(_explicit);
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  List<WishItem> get wishlist => List.unmodifiable(_wishlist);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawWeights = prefs.getString('interest_weights');
    if (rawWeights != null) {
      final decoded = jsonDecode(rawWeights) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        _weights[entry.key] = (entry.value as num).toDouble();
      }
    }
    _explicit.addAll(prefs.getStringList('explicit_interests') ?? const []);
    _recentSearches.addAll(prefs.getStringList('recent_searches') ?? const []);
    final rawWishlist = prefs.getStringList('wishlist') ?? const [];
    for (final item in rawWishlist) {
      try {
        _wishlist.add(WishItem.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('interest_weights', jsonEncode(_weights));
    await prefs.setStringList('explicit_interests', _explicit.toList());
    await prefs.setStringList('recent_searches', _recentSearches.take(20).toList());
    await prefs.setStringList('wishlist', _wishlist.map((e) => jsonEncode(e.toJson())).toList());
  }

  void setExplicit(String category, bool enabled) {
    if (enabled) {
      _explicit.add(category);
      _bump(category, 8);
    } else {
      _explicit.remove(category);
      _weights[category] = ((_weights[category] ?? 0) - 5).clamp(0, 100).toDouble();
    }
    _persist();
    notifyListeners();
  }

  void registerSearch(String query, Iterable<Product> matches) {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return;
    _recentSearches.remove(cleaned);
    _recentSearches.insert(0, cleaned);
    for (final product in matches.take(5)) {
      _bump(product.category, 1.5);
      _bump(product.brand, .7);
      for (final tag in product.tags) {
        _bump(tag, .25);
      }
    }
    _persist();
    notifyListeners();
  }

  void registerClick(Product product) => _learn(product, 3);

  void _learn(Product product, double strength) {
    _bump(product.category, strength);
    _bump(product.brand, strength * .45);
    for (final tag in product.tags) {
      _bump(tag, strength * .18);
    }
    _persist();
    notifyListeners();
  }

  void _bump(String key, double amount) {
    if (key.isEmpty) return;
    _weights[key] = ((_weights[key] ?? 0) + amount).clamp(0, 100).toDouble();
  }

  double score(Product product) {
    var score = product.discountPercent * .35;
    score += product.savingsVsPeersPercent * 1.5;
    score += (_weights[product.category] ?? 0) * 1.8;
    score += (_weights[product.brand] ?? 0) * .9;
    if (_explicit.contains(product.category)) score += 18;
    if (product.couponVerified) score += 12;
    if (product.lastCouponCheckMinutes <= 30) score += 4;
    if (product.popularityPosition != null) {
      score += (25 - product.popularityPosition!.clamp(1, 20)) * .7;
    }
    return score;
  }

  List<Product> recommend(List<Product> products) {
    final result = [...products];
    result.sort((a, b) => score(b).compareTo(score(a)));
    return result;
  }

  bool isWatching(String productId) => _wishlist.any((item) => item.productId == productId);

  void addWish(Product product, {required int months, double? targetPrice}) {
    _wishlist.removeWhere((item) => item.productId == product.id);
    _wishlist.add(WishItem(
      productId: product.id,
      months: months,
      createdAt: DateTime.now(),
      targetPrice: targetPrice,
    ));
    _learn(product, 10);
  }

  void removeWish(String productId) {
    _wishlist.removeWhere((item) => item.productId == productId);
    _persist();
    notifyListeners();
  }
}

class MarketComparator {
  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static List<Product> cheapestPerProduct(Iterable<Product> listings) {
    final groups = <String, List<Product>>{};
    for (final item in listings) {
      final key = item.catalogProductId ?? item.name.toLowerCase();
      groups.putIfAbsent(key, () => []).add(item);
    }

    final winners = <Product>[];
    for (final group in groups.values) {
      group.sort((a, b) => a.finalPrice.compareTo(b.finalPrice));
      final cheapest = group.first;
      final peerPrices = group.skip(1).map((e) => e.finalPrice).where((e) => e > 0).toList();
      winners.add(cheapest.copyWith(
        comparisonPrice: peerPrices.isEmpty ? null : _median(peerPrices),
        comparedListings: group.length,
      ));
    }

    winners.sort((a, b) {
      final pa = a.popularityPosition ?? 9999;
      final pb = b.popularityPosition ?? 9999;
      final popular = pa.compareTo(pb);
      if (popular != 0) return popular;
      return b.savingsVsPeersPercent.compareTo(a.savingsVsPeersPercent);
    });
    return winners;
  }

  static List<Product> dealFeed(
    Iterable<Product> listings, {
    double minSavingsPercent = 20,
  }) {
    return cheapestPerProduct(listings)
        .where((p) => p.comparedListings >= 2 && p.savingsVsPeersPercent >= minSavingsPercent)
        .toList()
      ..sort((a, b) => b.savingsVsPeersPercent.compareTo(a.savingsVsPeersPercent));
  }
}

class ProductSearchService {
  ProductSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  Future<List<Product>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return MarketComparator.cheapestPerProduct(demoListings);

    if (_apiBaseUrl.isNotEmpty) {
      try {
        final uri = Uri.parse('$_apiBaseUrl/search').replace(queryParameters: {'q': cleaned, 'limit': '20'});
        final response = await _client.get(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final data = decoded['results'] as List<dynamic>? ?? const [];
          final products = data
              .map((e) => Product.fromApi(e as Map<String, dynamic>))
              .where((p) => p.id.isNotEmpty)
              .toList();
          if (products.isNotEmpty) return products;
        }
      } catch (_) {
      }
    }

    final q = cleaned.toLowerCase();
    final matches = demoListings.where((p) {
      final haystack = '${p.name} ${p.category} ${p.brand} ${p.tags.join(' ')}'.toLowerCase();
      return haystack.contains(q) || (q == 'tenis' && haystack.contains('tênis'));
    });
    return MarketComparator.cheapestPerProduct(matches);
  }
}

class MaisBaratoApp extends StatefulWidget {
  const MaisBaratoApp({super.key});

  @override
  State<MaisBaratoApp> createState() => _MaisBaratoAppState();
}

class _MaisBaratoAppState extends State<MaisBaratoApp> {
  final engine = PreferenceEngine();

  @override
  void initState() {
    super.initState();
    engine.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'O Mais Barato',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F6FA),
      ),
      home: HomeShell(engine: engine),
    );
  }
}

const demoListings = <Product>[
  Product(id: 'nike-a', name: 'Tênis Nike Revolution 7', category: 'Roupas', brand: 'Nike', marketplace: 'Mercado Livre', seller: 'Loja A', price: 209, originalPrice: 299, tags: ['tênis', 'corrida'], catalogProductId: 'nike-revolution-7', popularityPosition: 1),
  Product(id: 'nike-b', name: 'Tênis Nike Revolution 7', category: 'Roupas', brand: 'Nike', marketplace: 'Mercado Livre', seller: 'Loja B', price: 279, originalPrice: 299, tags: ['tênis', 'corrida'], catalogProductId: 'nike-revolution-7', popularityPosition: 1),
  Product(id: 'nike-c', name: 'Tênis Nike Revolution 7', category: 'Roupas', brand: 'Nike', marketplace: 'Mercado Livre', seller: 'Loja C', price: 289, originalPrice: 319, tags: ['tênis', 'corrida'], catalogProductId: 'nike-revolution-7', popularityPosition: 1),
  Product(id: 'adidas-a', name: 'Tênis Adidas Duramo SL', category: 'Roupas', brand: 'Adidas', marketplace: 'Mercado Livre', seller: 'Loja D', price: 239, originalPrice: 349, tags: ['tênis', 'corrida'], catalogProductId: 'adidas-duramo-sl', popularityPosition: 2),
  Product(id: 'adidas-b', name: 'Tênis Adidas Duramo SL', category: 'Roupas', brand: 'Adidas', marketplace: 'Mercado Livre', seller: 'Loja E', price: 329, originalPrice: 349, tags: ['tênis', 'corrida'], catalogProductId: 'adidas-duramo-sl', popularityPosition: 2),
  Product(id: 'adidas-c', name: 'Tênis Adidas Duramo SL', category: 'Roupas', brand: 'Adidas', marketplace: 'Mercado Livre', seller: 'Loja F', price: 319, originalPrice: 349, tags: ['tênis', 'corrida'], catalogProductId: 'adidas-duramo-sl', popularityPosition: 2),
  Product(id: 'olympikus-a', name: 'Tênis Olympikus Corre 4', category: 'Roupas', brand: 'Olympikus', marketplace: 'Mercado Livre', seller: 'Loja G', price: 399, originalPrice: 499, tags: ['tênis', 'corrida'], catalogProductId: 'olympikus-corre-4', popularityPosition: 3),
  Product(id: 'olympikus-b', name: 'Tênis Olympikus Corre 4', category: 'Roupas', brand: 'Olympikus', marketplace: 'Mercado Livre', seller: 'Loja H', price: 429, originalPrice: 499, tags: ['tênis', 'corrida'], catalogProductId: 'olympikus-corre-4', popularityPosition: 3),
  Product(id: 'puma-a', name: 'Tênis Puma Flyer Runner', category: 'Roupas', brand: 'Puma', marketplace: 'Mercado Livre', seller: 'Loja I', price: 189, originalPrice: 299, tags: ['tênis', 'corrida'], catalogProductId: 'puma-flyer-runner', popularityPosition: 4),
  Product(id: 'puma-b', name: 'Tênis Puma Flyer Runner', category: 'Roupas', brand: 'Puma', marketplace: 'Mercado Livre', seller: 'Loja J', price: 259, originalPrice: 299, tags: ['tênis', 'corrida'], catalogProductId: 'puma-flyer-runner', popularityPosition: 4),
  Product(id: 'puma-c', name: 'Tênis Puma Flyer Runner', category: 'Roupas', brand: 'Puma', marketplace: 'Mercado Livre', seller: 'Loja K', price: 269, originalPrice: 309, tags: ['tênis', 'corrida'], catalogProductId: 'puma-flyer-runner', popularityPosition: 4),
  Product(id: 'galaxy-a', name: 'Smartphone Galaxy 256 GB', category: 'Tecnologia', brand: 'Samsung', marketplace: 'Mercado Livre', seller: 'Tech A', price: 2199, originalPrice: 2699, tags: ['celular', 'android'], catalogProductId: 'galaxy-256', couponCode: 'TECH150', couponDiscount: 150, couponVerified: true, lastCouponCheckMinutes: 8, popularityPosition: 2),
  Product(id: 'galaxy-b', name: 'Smartphone Galaxy 256 GB', category: 'Tecnologia', brand: 'Samsung', marketplace: 'Mercado Livre', seller: 'Tech B', price: 2599, originalPrice: 2699, tags: ['celular', 'android'], catalogProductId: 'galaxy-256', popularityPosition: 2),
  Product(id: 'galaxy-c', name: 'Smartphone Galaxy 256 GB', category: 'Tecnologia', brand: 'Samsung', marketplace: 'Mercado Livre', seller: 'Tech C', price: 2699, originalPrice: 2799, tags: ['celular', 'android'], catalogProductId: 'galaxy-256', popularityPosition: 2),
  Product(id: 'creatina-a', name: 'Creatina 300 g', category: 'Suplementos', brand: 'NutriLab', marketplace: 'Mercado Livre', seller: 'Fit A', price: 79, originalPrice: 109, tags: ['creatina', 'academia'], catalogProductId: 'creatina-300', popularityPosition: 5),
  Product(id: 'creatina-b', name: 'Creatina 300 g', category: 'Suplementos', brand: 'NutriLab', marketplace: 'Mercado Livre', seller: 'Fit B', price: 96, originalPrice: 109, tags: ['creatina', 'academia'], catalogProductId: 'creatina-300', popularityPosition: 5),
];

List<Product> get demoProducts => MarketComparator.cheapestPerProduct(demoListings);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.engine});
  final PreferenceEngine engine;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DealsPage(engine: widget.engine),
      SearchPage(engine: widget.engine),
      WishlistPage(engine: widget.engine),
      CouponsPage(engine: widget.engine),
      PreferencesPage(engine: widget.engine),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: 'Ofertas'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'Quero comprar'),
          NavigationDestination(icon: Icon(Icons.confirmation_num_outlined), selectedIcon: Icon(Icons.confirmation_num), label: 'Cupons'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Preferências'),
        ],
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
        ]),
      );
}

class DealsPage extends StatelessWidget {
  const DealsPage({super.key, required this.engine});
  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: engine,
        builder: (context, _) {
          final deals = engine.recommend(MarketComparator.dealFeed(demoListings, minSavingsPercent: 20));
          return ListView(children: [
            const PageTitle('20%+ mais barato', 'Só entram ofertas realmente mais baratas que os outros anúncios equivalentes do mesmo produto.'),
            if (deals.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma oferta passou do corte de 20% neste momento.')),
            ...deals.map((p) => ProductCard(product: p, engine: engine)),
            const SizedBox(height: 24),
          ]);
        },
      );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.engine});
  final PreferenceEngine engine;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final service = ProductSearchService();
  String query = '';
  bool loading = false;
  String? error;
  List<Product> results = const [];

  Future<void> submit(String value) async {
    final cleaned = value.trim();
    setState(() {
      query = cleaned;
      loading = true;
      error = null;
    });
    try {
      final found = await service.search(cleaned);
      widget.engine.registerSearch(cleaned, found);
      if (!mounted) return;
      setState(() => results = found);
    } catch (_) {
      if (!mounted) return;
      setState(() => error = 'Não foi possível atualizar os preços agora.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const PageTitle('Buscar o menor preço', 'Mostramos os modelos mais populares e apenas o anúncio mais barato de cada produto.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            hintText: 'Ex.: tênis, celular, creatina',
            leading: const Icon(Icons.search),
            onChanged: (value) => query = value,
            onSubmitted: submit,
            trailing: [IconButton(onPressed: () => submit(query), icon: const Icon(Icons.arrow_forward))],
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 8),
        if (!loading && results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Mais populares • melhor anúncio de cada modelo', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
        Expanded(
          child: results.isEmpty && !loading
              ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Pesquise um produto. Exemplo: “tênis”.', textAlign: TextAlign.center)))
              : ListView(children: results.map((p) => ProductCard(product: p, engine: widget.engine)).toList()),
        ),
      ]);
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.engine});
  final Product product;
  final PreferenceEngine engine;

  String money(double value) => 'R$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          engine.registerClick(product);
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailsPage(product: product, engine: engine)));
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: product.imageUrl == null
                  ? Icon(_iconFor(product.category), size: 32)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(_iconFor(product.category), size: 32)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (product.popularityPosition != null && product.popularityPosition! <= 20)
                  Text('#${product.popularityPosition} entre os mais vendidos', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${product.marketplace}${product.seller == null ? '' : ' • ${product.seller}'}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 8),
                Text(money(product.finalPrice), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                if (product.isCheapestCompared) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.check_circle, size: 16), label: Text('Mais barato entre ${product.comparedListings} anúncios')),
                    if (product.savingsVsPeersPercent >= 1)
                      Chip(visualDensity: VisualDensity.compact, label: Text('${product.savingsVsPeersPercent.round()}% abaixo dos demais')),
                  ]),
                  Text('Referência dos outros anúncios: ${money(product.comparisonPrice!)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
                if (product.couponCode != null) ...[
                  const SizedBox(height: 6),
                  Text('Cupom ${product.couponCode} • ${money(product.couponDiscount)} OFF'),
                ],
              ]),
            ),
            IconButton(
              tooltip: 'Quero comprar',
              onPressed: () => showWishDialog(context, product, engine),
              icon: Icon(engine.isWatching(product.id) ? Icons.bookmark : Icons.bookmark_border),
            ),
          ]),
        ),
      ),
    );
  }

  static IconData _iconFor(String category) => switch (category) {
        'Roupas' => Icons.checkroom,
        'Acessórios' => Icons.watch_outlined,
        'Brinquedos' => Icons.toys_outlined,
        'Tecnologia' => Icons.devices,
        'Suplementos' => Icons.fitness_center,
        _ => Icons.shopping_bag_outlined,
      };
}

class ProductDetailsPage extends StatelessWidget {
  const ProductDetailsPage({super.key, required this.product, required this.engine});
  final Product product;
  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Melhor anúncio')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(product.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('${product.marketplace} • ${product.brand}${product.seller == null ? '' : ' • ${product.seller}'}'),
        const SizedBox(height: 18),
        Text('R$ ${product.finalPrice.toStringAsFixed(2).replaceAll('.', ',')}', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
        if (product.isCheapestCompared)
          Card(
            child: ListTile(
              leading: const Icon(Icons.price_check),
              title: Text('${product.savingsVsPeersPercent.round()}% mais barato que a referência'),
              subtitle: Text('Comparado com ${product.comparedListings - 1} outros anúncios equivalentes. Referência: R$ ${product.comparisonPrice!.toStringAsFixed(2).replaceAll('.', ',')}.'),
            ),
          ),
        if (product.couponCode != null)
          Card(
            child: ListTile(
              leading: Icon(product.couponVerified ? Icons.verified : Icons.warning_amber),
              title: Text('Cupom ${product.couponCode}'),
              subtitle: Text(product.couponVerified ? 'Cupom verificado.' : 'Cupom ainda não confirmado.'),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => showWishDialog(context, product, engine), icon: const Icon(Icons.notifications_active_outlined), label: const Text('Quero comprar — monitorar')),
      ]),
    );
  }
}

Future<void> showWishDialog(BuildContext context, Product product, PreferenceEngine engine) async {
  var months = 3;
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Quero comprar'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          const Text('Monitorar por'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [1, 3, 6, 12].map((m) => ChoiceChip(label: Text('$m ${m == 1 ? 'mês' : 'meses'}'), selected: months == m, onSelected: (_) => setDialogState(() => months = m))).toList()),
          const SizedBox(height: 14),
          TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Preço-alvo (opcional)', prefixText: 'R$ ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Monitorar')),
        ],
      ),
    ),
  );
  final typed = controller.text;
  controller.dispose();
  if (confirmed == true) {
    final parsed = double.tryParse(typed.replaceAll(',', '.'));
    engine.addWish(product, months: months, targetPrice: parsed);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} será monitorado.')));
    }
  }
}

class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key, required this.engine});
  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: engine,
        builder: (context, _) {
          final items = engine.wishlist;
          return Column(children: [
            const PageTitle('Quero comprar', 'Acompanhe um produto e receba alertas quando aparecer uma oferta melhor.'),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Nenhum produto monitorado.'))
                  : ListView(
                      children: items.map((item) {
                        Product? product;
                        for (final candidate in demoProducts) {
                          if (candidate.id == item.productId) {
                            product = candidate;
                            break;
                          }
                        }
                        if (product == null) return const SizedBox.shrink();
                        return ListTile(
                          title: Text(product.name),
                          subtitle: item.targetPrice == null ? const Text('Sem preço-alvo') : Text('Alvo: R$ ${item.targetPrice!.toStringAsFixed(2).replaceAll('.', ',')}'),
                          trailing: IconButton(onPressed: () => engine.removeWish(item.productId), icon: const Icon(Icons.delete_outline)),
                        );
                      }).toList(),
                    ),
            ),
          ]);
        },
      );
}

class CouponsPage extends StatelessWidget {
  const CouponsPage({super.key, required this.engine});
  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: engine,
        builder: (context, _) {
          final coupons = engine.recommend(demoProducts.where((p) => p.couponCode != null).toList());
          return ListView(children: [
            const PageTitle('Cupons recomendados', 'Cupons vinculados ao melhor anúncio encontrado para cada produto.'),
            if (coupons.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nenhum cupom disponível.')),
            ...coupons.map((p) => ProductCard(product: p, engine: engine)),
          ]);
        },
      );
}

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key, required this.engine});
  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: engine,
        builder: (context, _) {
          final learned = engine.weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return ListView(children: [
            const PageTitle('Suas preferências', 'O app aprende com suas pesquisas, cliques e produtos monitorados.'),
            ...PreferenceEngine.categories.map((category) => SwitchListTile(title: Text(category), value: engine.explicit.contains(category), onChanged: (value) => engine.setExplicit(category, value))),
            const Divider(),
            if (learned.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('Ainda não há comportamento suficiente.')),
            ...learned.take(12).map((entry) => ListTile(title: Text(entry.key), trailing: Text('${entry.value.round()} pts'), subtitle: LinearProgressIndicator(value: (entry.value / 100).clamp(0, 1).toDouble()))),
          ]);
        },
      );
}
