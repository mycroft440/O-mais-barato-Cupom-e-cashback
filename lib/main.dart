import "dart:convert";

import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";

const _currency = r"R$";

String brl(double value) {
  final formatted = value.toStringAsFixed(2).replaceAll(".", ",");
  return "$_currency $formatted";
}

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
    this.affiliateUrl,
    this.comparisonPrice,
    this.comparedListings = 1,
    this.popularityPosition,
    this.comparedSources = const [],
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
  final String? affiliateUrl;
  final double? comparisonPrice;
  final int comparedListings;
  final int? popularityPosition;
  final List<String> comparedSources;

  double get finalPrice =>
      (price - couponDiscount).clamp(0, double.infinity).toDouble();

  double get discountPercent =>
      originalPrice <= 0 ? 0 : (1 - finalPrice / originalPrice) * 100;

  double get savingsVsPeersPercent {
    final reference = comparisonPrice;
    if (reference == null || reference <= 0 || finalPrice >= reference) {
      return 0;
    }
    return (1 - finalPrice / reference) * 100;
  }

  bool get isCheapestCompared => comparisonPrice != null && comparedListings > 1;

  String? get outboundUrl {
    final affiliate = affiliateUrl?.trim();
    if (affiliate != null && affiliate.isNotEmpty) return affiliate;
    final product = productUrl?.trim();
    return product == null || product.isEmpty ? null : product;
  }

  Product copyWith({
    double? comparisonPrice,
    int? comparedListings,
    int? popularityPosition,
    List<String>? comparedSources,
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
      affiliateUrl: affiliateUrl,
      comparisonPrice: comparisonPrice ?? this.comparisonPrice,
      comparedListings: comparedListings ?? this.comparedListings,
      popularityPosition: popularityPosition ?? this.popularityPosition,
      comparedSources: comparedSources ?? this.comparedSources,
    );
  }

  factory Product.fromApi(Map<String, dynamic> json) {
    final rawTags = json["tags"] as List<dynamic>? ?? const [];
    final rawSources = json["compared_sources"] as List<dynamic>? ?? const [];
    return Product(
      id: json["item_id"] as String? ?? json["id"] as String? ?? "",
      name: json["name"] as String? ?? "Produto",
      category: json["category"] as String? ?? "Outros",
      brand: json["brand"] as String? ?? "",
      marketplace: json["marketplace"] as String? ?? "Loja",
      price: (json["price"] as num? ?? 0).toDouble(),
      originalPrice:
          (json["original_price"] as num? ?? json["price"] as num? ?? 0)
              .toDouble(),
      tags: rawTags.map((value) => value.toString()).toList(),
      couponCode: json["coupon_code"] as String?,
      couponDiscount: (json["coupon_discount"] as num? ?? 0).toDouble(),
      couponVerified: json["coupon_verified"] as bool? ?? false,
      lastCouponCheckMinutes:
          (json["last_coupon_check_minutes"] as num? ?? 999).toInt(),
      catalogProductId: json["catalog_product_id"] as String? ??
          json["canonical_product_id"] as String?,
      seller: json["seller"]?.toString(),
      imageUrl: json["image_url"] as String?,
      productUrl: json["product_url"] as String?,
      affiliateUrl: json["affiliate_url"] as String?,
      comparisonPrice: (json["comparison_price"] as num?)?.toDouble(),
      comparedListings: (json["compared_listings"] as num? ?? 1).toInt(),
      popularityPosition: (json["popularity_position"] as num?)?.toInt(),
      comparedSources: rawSources.map((value) => value.toString()).toList(),
    );
  }
}

class WishItem {
  const WishItem({
    required this.productId,
    required this.months,
    required this.createdAt,
    this.targetPrice,
  });

  final String productId;
  final int months;
  final DateTime createdAt;
  final double? targetPrice;

  Map<String, dynamic> toJson() => {
        "productId": productId,
        "months": months,
        "createdAt": createdAt.toIso8601String(),
        "targetPrice": targetPrice,
      };

  factory WishItem.fromJson(Map<String, dynamic> json) {
    return WishItem(
      productId: json["productId"] as String,
      months: json["months"] as int? ?? 3,
      createdAt: DateTime.tryParse(json["createdAt"] as String? ?? "") ??
          DateTime.now(),
      targetPrice: (json["targetPrice"] as num?)?.toDouble(),
    );
  }
}

class PreferenceEngine extends ChangeNotifier {
  static const categories = <String>[
    "Roupas",
    "Acessórios",
    "Brinquedos",
    "Tecnologia",
    "Suplementos",
  ];

  final Map<String, double> _weights = {};
  final Set<String> _explicit = {};
  final List<WishItem> _wishlist = [];

  Map<String, double> get weights => Map.unmodifiable(_weights);
  Set<String> get explicit => Set.unmodifiable(_explicit);
  List<WishItem> get wishlist => List.unmodifiable(_wishlist);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawWeights = prefs.getString("interest_weights");
    if (rawWeights != null) {
      try {
        final decoded = jsonDecode(rawWeights) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _weights[entry.key] = (entry.value as num).toDouble();
        }
      } catch (_) {}
    }
    _explicit.addAll(prefs.getStringList("explicit_interests") ?? const []);
    for (final raw in prefs.getStringList("wishlist") ?? const []) {
      try {
        _wishlist.add(WishItem.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("interest_weights", jsonEncode(_weights));
    await prefs.setStringList("explicit_interests", _explicit.toList());
    await prefs.setStringList(
      "wishlist",
      _wishlist.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  void setExplicit(String category, bool enabled) {
    if (enabled) {
      _explicit.add(category);
      _bump(category, 8);
    } else {
      _explicit.remove(category);
      _weights[category] =
          ((_weights[category] ?? 0) - 5).clamp(0, 100).toDouble();
    }
    _persist();
    notifyListeners();
  }

  void registerSearch(String query, Iterable<Product> matches) {
    if (query.trim().isEmpty) return;
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

  List<Product> recommend(List<Product> products) {
    final result = [...products];
    result.sort((a, b) {
      final popularityA = a.popularityPosition ?? 9999;
      final popularityB = b.popularityPosition ?? 9999;
      final popularity = popularityA.compareTo(popularityB);
      if (popularity != 0) return popularity;
      final learnedA = (_weights[a.category] ?? 0) + (_weights[a.brand] ?? 0);
      final learnedB = (_weights[b.category] ?? 0) + (_weights[b.brand] ?? 0);
      return learnedB.compareTo(learnedA);
    });
    return result;
  }

  bool isWatching(String productId) =>
      _wishlist.any((item) => item.productId == productId);

  void addWish(Product product, {required int months, double? targetPrice}) {
    _wishlist.removeWhere((item) => item.productId == product.id);
    _wishlist.add(
      WishItem(
        productId: product.id,
        months: months,
        createdAt: DateTime.now(),
        targetPrice: targetPrice,
      ),
    );
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
      final peerPrices = group
          .skip(1)
          .map((item) => item.finalPrice)
          .where((value) => value > 0)
          .toList();
      winners.add(
        cheapest.copyWith(
          comparisonPrice: peerPrices.isEmpty ? null : _median(peerPrices),
          comparedListings: group.length,
        ),
      );
    }

    winners.sort((a, b) {
      final popularityA = a.popularityPosition ?? 9999;
      final popularityB = b.popularityPosition ?? 9999;
      final popularity = popularityA.compareTo(popularityB);
      if (popularity != 0) return popularity;
      return a.finalPrice.compareTo(b.finalPrice);
    });
    return winners;
  }

  static List<Product> dealFeed(
    Iterable<Product> listings, {
    double? minSavingsPercent,
  }) {
    return cheapestPerProduct(listings)
        .where((product) => product.comparedListings >= 2)
        .toList();
  }
}

class ProductSearchService {
  ProductSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _apiBaseUrl =
      String.fromEnvironment("API_BASE_URL", defaultValue: "");

  Future<List<Product>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) {
      return MarketComparator.cheapestPerProduct(demoListings);
    }

    if (_apiBaseUrl.isNotEmpty) {
      try {
        final uri = Uri.parse("$_apiBaseUrl/search").replace(
          queryParameters: {
            "q": cleaned,
            "limit": "20",
            "comparable_only": "true",
          },
        );
        final response =
            await _client.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final rawResults = decoded["results"] as List<dynamic>? ?? const [];
          final products = rawResults
              .whereType<Map<String, dynamic>>()
              .map(Product.fromApi)
              .where((product) => product.id.isNotEmpty)
              .toList();
          if (products.isNotEmpty) return products;
        }
      } catch (_) {}
    }

    final normalized = cleaned.toLowerCase();
    final matches = demoListings.where((product) {
      final haystack =
          "${product.name} ${product.category} ${product.brand} ${product.tags.join(" ")}".toLowerCase();
      return haystack.contains(normalized) ||
          (normalized == "tenis" && haystack.contains("tênis"));
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
      title: "O Mais Barato",
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
  Product(
    id: "nike-a",
    name: "Tênis Nike Revolution 7",
    category: "Roupas",
    brand: "Nike",
    marketplace: "Mercado Livre",
    seller: "Loja A",
    price: 209,
    originalPrice: 299,
    tags: ["tênis", "corrida"],
    catalogProductId: "nike-revolution-7",
    popularityPosition: 1,
  ),
  Product(
    id: "nike-b",
    name: "Tênis Nike Revolution 7",
    category: "Roupas",
    brand: "Nike",
    marketplace: "Mercado Livre",
    seller: "Loja B",
    price: 279,
    originalPrice: 299,
    tags: ["tênis", "corrida"],
    catalogProductId: "nike-revolution-7",
    popularityPosition: 1,
  ),
  Product(
    id: "nike-c",
    name: "Tênis Nike Revolution 7",
    category: "Roupas",
    brand: "Nike",
    marketplace: "Mercado Livre",
    seller: "Loja C",
    price: 289,
    originalPrice: 319,
    tags: ["tênis", "corrida"],
    catalogProductId: "nike-revolution-7",
    popularityPosition: 1,
  ),
  Product(
    id: "adidas-a",
    name: "Tênis Adidas Duramo SL",
    category: "Roupas",
    brand: "Adidas",
    marketplace: "Mercado Livre",
    seller: "Loja D",
    price: 239,
    originalPrice: 349,
    tags: ["tênis", "corrida"],
    catalogProductId: "adidas-duramo-sl",
    popularityPosition: 2,
  ),
  Product(
    id: "adidas-b",
    name: "Tênis Adidas Duramo SL",
    category: "Roupas",
    brand: "Adidas",
    marketplace: "Mercado Livre",
    seller: "Loja E",
    price: 329,
    originalPrice: 349,
    tags: ["tênis", "corrida"],
    catalogProductId: "adidas-duramo-sl",
    popularityPosition: 2,
  ),
  Product(
    id: "puma-a",
    name: "Tênis Puma Flyer Runner",
    category: "Roupas",
    brand: "Puma",
    marketplace: "Mercado Livre",
    seller: "Loja F",
    price: 189,
    originalPrice: 299,
    tags: ["tênis", "corrida"],
    catalogProductId: "puma-flyer-runner",
    popularityPosition: 3,
  ),
  Product(
    id: "puma-b",
    name: "Tênis Puma Flyer Runner",
    category: "Roupas",
    brand: "Puma",
    marketplace: "Mercado Livre",
    seller: "Loja G",
    price: 259,
    originalPrice: 299,
    tags: ["tênis", "corrida"],
    catalogProductId: "puma-flyer-runner",
    popularityPosition: 3,
  ),
  Product(
    id: "galaxy-a",
    name: "Smartphone Galaxy 256 GB",
    category: "Tecnologia",
    brand: "Samsung",
    marketplace: "Mercado Livre",
    seller: "Tech A",
    price: 2199,
    originalPrice: 2699,
    tags: ["celular", "android"],
    catalogProductId: "galaxy-256",
    couponCode: "TECH150",
    couponDiscount: 150,
    couponVerified: true,
    popularityPosition: 2,
  ),
  Product(
    id: "galaxy-b",
    name: "Smartphone Galaxy 256 GB",
    category: "Tecnologia",
    brand: "Samsung",
    marketplace: "Mercado Livre",
    seller: "Tech B",
    price: 2599,
    originalPrice: 2699,
    tags: ["celular", "android"],
    catalogProductId: "galaxy-256",
    popularityPosition: 2,
  ),
];

List<Product> get demoProducts =>
    MarketComparator.cheapestPerProduct(demoListings);

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
    final pages = <Widget>[
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
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department),
            label: "Ofertas",
          ),
          NavigationDestination(icon: Icon(Icons.search), label: "Buscar"),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: "Quero comprar",
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_num_outlined),
            selectedIcon: Icon(Icons.confirmation_num),
            label: "Cupons",
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: "Preferências"),
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class DealsPage extends StatelessWidget {
  const DealsPage({super.key, required this.engine});

  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) {
    final deals = engine.recommend(MarketComparator.dealFeed(demoListings));
    return ListView(
      children: [
        const PageTitle(
          "Mais baratos agora",
          "Cada cartão mostra o menor preço encontrado para aquele produto, sem corte mínimo de desconto.",
        ),
        ...deals.map((product) => ProductCard(product: product, engine: engine)),
        const SizedBox(height: 24),
      ],
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.engine});

  final PreferenceEngine engine;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final service = ProductSearchService();
  String query = "";
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
      setState(() => error = "Não foi possível atualizar os preços agora.");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageTitle(
          "Buscar o menor preço",
          "Mostramos os modelos mais populares e somente o anúncio de menor preço de cada produto.",
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            hintText: "Ex.: tênis, celular, creatina",
            leading: const Icon(Icons.search),
            onChanged: (value) => query = value,
            onSubmitted: submit,
            trailing: [
              IconButton(
                onPressed: () => submit(query),
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        if (!loading && results.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Mais populares • menor preço de cada modelo",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        Expanded(
          child: results.isEmpty && !loading
              ? const Center(
                  child: Text("Pesquise um produto. Exemplo: tênis."),
                )
              : ListView(
                  children: results
                      .map(
                        (product) =>
                            ProductCard(product: product, engine: widget.engine),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.engine});

  final Product product;
  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) {
    final sourceText = product.comparedSources.isEmpty
        ? product.marketplace
        : product.comparedSources.join(" • ");
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          engine.registerClick(product);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ProductDetailsPage(product: product, engine: engine),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(product: product),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.popularityPosition != null &&
                        product.popularityPosition! <= 20)
                      Text(
                        "#${product.popularityPosition} entre os mais vendidos",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sourceText,
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      brl(product.finalPrice),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (product.isCheapestCompared) ...[
                      const SizedBox(height: 6),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.price_check, size: 16),
                        label: Text(
                          "Menor preço entre ${product.comparedListings} anúncios",
                        ),
                      ),
                      if (product.savingsVsPeersPercent > 0)
                        Text(
                          "${product.savingsVsPeersPercent.toStringAsFixed(1)}% abaixo da referência (${brl(product.comparisonPrice!)})",
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                    if (product.couponCode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          "Cupom ${product.couponCode} • ${brl(product.couponDiscount)} OFF",
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "Quero comprar",
                onPressed: () => showWishDialog(context, product, engine),
                icon: Icon(
                  engine.isWatching(product.id)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(_iconFor(product.category), size: 32);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: product.imageUrl == null
          ? fallback
          : Image.network(
              product.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }

  static IconData _iconFor(String category) => switch (category) {
        "Roupas" => Icons.checkroom,
        "Acessórios" => Icons.watch_outlined,
        "Brinquedos" => Icons.toys_outlined,
        "Tecnologia" => Icons.devices,
        "Suplementos" => Icons.fitness_center,
        _ => Icons.shopping_bag_outlined,
      };
}

class ProductDetailsPage extends StatelessWidget {
  const ProductDetailsPage({
    super.key,
    required this.product,
    required this.engine,
  });

  final Product product;
  final PreferenceEngine engine;

  Future<void> _openOffer(BuildContext context) async {
    final url = product.outboundUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível abrir esta oferta.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Menor preço encontrado")),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            product.name,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text("${product.marketplace} • ${product.brand}"),
          const SizedBox(height: 18),
          Text(
            brl(product.finalPrice),
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (product.isCheapestCompared)
            Card(
              child: ListTile(
                leading: const Icon(Icons.price_check),
                title: Text(
                  "Menor preço entre ${product.comparedListings} anúncios equivalentes",
                ),
                subtitle: product.comparisonPrice == null
                    ? null
                    : Text(
                        "Referência dos demais: ${brl(product.comparisonPrice!)}. Economia relativa: ${product.savingsVsPeersPercent.toStringAsFixed(1)}%.",
                      ),
              ),
            ),
          if (product.comparedSources.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text("Lojas comparadas"),
              subtitle: Text(product.comparedSources.join(" • ")),
            ),
          if (product.couponCode != null)
            ListTile(
              leading: Icon(
                product.couponVerified ? Icons.verified : Icons.warning_amber,
              ),
              title: Text("Cupom ${product.couponCode}"),
            ),
          const SizedBox(height: 12),
          if (product.outboundUrl != null)
            FilledButton.icon(
              onPressed: () => _openOffer(context),
              icon: const Icon(Icons.open_in_new),
              label: Text("Comprar na ${product.marketplace}"),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showWishDialog(context, product, engine),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text("Quero comprar — monitorar"),
          ),
        ],
      ),
    );
  }
}

Future<void> showWishDialog(
  BuildContext context,
  Product product,
  PreferenceEngine engine,
) async {
  var months = 3;
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text("Quero comprar"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name),
            const SizedBox(height: 16),
            const Text("Monitorar por"),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [1, 3, 6, 12]
                  .map(
                    (month) => ChoiceChip(
                      label: Text("$month ${month == 1 ? "mês" : "meses"}"),
                      selected: months == month,
                      onSelected: (_) =>
                          setDialogState(() => months = month),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "Preço-alvo (opcional)",
                prefixText: "R$ ",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Monitorar"),
          ),
        ],
      ),
    ),
  );
  final typed = controller.text;
  controller.dispose();
  if (confirmed == true) {
    final parsed = double.tryParse(typed.replaceAll(",", "."));
    engine.addWish(product, months: months, targetPrice: parsed);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${product.name} será monitorado.")),
      );
    }
  }
}

class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key, required this.engine});

  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final items = engine.wishlist;
        return Column(
          children: [
            const PageTitle(
              "Quero comprar",
              "Acompanhe produtos e receba alertas quando aparecer um preço melhor.",
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text("Nenhum produto monitorado."))
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
                        final target = item.targetPrice;
                        return ListTile(
                          title: Text(product.name),
                          subtitle: Text(
                            target == null ? "Sem preço-alvo" : "Alvo: ${brl(target)}",
                          ),
                          trailing: IconButton(
                            onPressed: () => engine.removeWish(item.productId),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class CouponsPage extends StatelessWidget {
  const CouponsPage({super.key, required this.engine});

  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final coupons = engine.recommend(
          demoProducts.where((product) => product.couponCode != null).toList(),
        );
        return ListView(
          children: [
            const PageTitle(
              "Cupons recomendados",
              "Cupons vinculados ao menor preço encontrado para cada produto.",
            ),
            if (coupons.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text("Nenhum cupom disponível."),
              ),
            ...coupons.map(
              (product) => ProductCard(product: product, engine: engine),
            ),
          ],
        );
      },
    );
  }
}

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key, required this.engine});

  final PreferenceEngine engine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final learned = engine.weights.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return ListView(
          children: [
            const PageTitle(
              "Suas preferências",
              "O app aprende com pesquisas, cliques e produtos monitorados.",
            ),
            ...PreferenceEngine.categories.map(
              (category) => SwitchListTile(
                title: Text(category),
                value: engine.explicit.contains(category),
                onChanged: (value) => engine.setExplicit(category, value),
              ),
            ),
            const Divider(),
            if (learned.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text("Ainda não há comportamento suficiente."),
              ),
            ...learned.take(12).map(
                  (entry) => ListTile(
                    title: Text(entry.key),
                    trailing: Text("${entry.value.round()} pts"),
                    subtitle: LinearProgressIndicator(
                      value: (entry.value / 100).clamp(0, 1).toDouble(),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
