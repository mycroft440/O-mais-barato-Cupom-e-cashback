import 'dart:convert';

import 'package:flutter/material.dart';
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

  double get finalPrice => (price - couponDiscount).clamp(0, double.infinity).toDouble();
  double get discountPercent => originalPrice <= 0 ? 0 : (1 - finalPrice / originalPrice) * 100;
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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
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
        // Ignore malformed local state from older app versions.
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
      _bump(product.brand, 0.7);
      for (final tag in product.tags) {
        _bump(tag, 0.25);
      }
    }
    _persist();
    notifyListeners();
  }

  void registerClick(Product product) => _learn(product, 3);

  void registerFavorite(Product product) => _learn(product, 6);

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
    _weights[key] = ((_weights[key] ?? 0) + amount).clamp(0, 100).toDouble();
  }

  double score(Product product) {
    var score = product.discountPercent * .45;
    score += (_weights[product.category] ?? 0) * 1.8;
    score += (_weights[product.brand] ?? 0) * .9;
    for (final tag in product.tags) {
      score += (_weights[tag] ?? 0) * .22;
    }
    if (_explicit.contains(product.category)) score += 18;
    if (product.couponVerified) score += 12;
    if (product.lastCouponCheckMinutes <= 30) score += 4;
    return score;
  }

  List<Product> recommend(List<Product> products) {
    final result = [...products];
    result.sort((a, b) => score(b).compareTo(score(a)));
    return result;
  }

  List<Product> similar(Product source, List<Product> products) {
    final candidates = products.where((p) => p.id != source.id).toList();

    double similarity(Product p) {
      var value = 0.0;
      if (p.category == source.category) value += 40;
      if (p.brand == source.brand) value += 20;
      value += p.tags.toSet().intersection(source.tags.toSet()).length * 8;
      value += score(p) * .2;
      return value;
    }

    candidates.sort((a, b) => similarity(b).compareTo(similarity(a)));
    return candidates.take(4).toList();
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

const demoProducts = <Product>[
  Product(id: 'p1', name: 'Smartphone Galaxy 256 GB', category: 'Tecnologia', brand: 'Samsung', marketplace: 'Mercado Livre', price: 2199, originalPrice: 2699, tags: ['celular', 'android'], couponCode: 'TECH150', couponDiscount: 150, couponVerified: true, lastCouponCheckMinutes: 8),
  Product(id: 'p2', name: 'Fone Bluetooth Pro ANC', category: 'Tecnologia', brand: 'SoundMax', marketplace: 'Shopee', price: 249, originalPrice: 399, tags: ['fone', 'bluetooth'], couponCode: 'AUDIO40', couponDiscount: 40, couponVerified: true, lastCouponCheckMinutes: 12),
  Product(id: 'p3', name: 'Tênis Running Flex', category: 'Roupas', brand: 'Move', marketplace: 'Amazon', price: 229, originalPrice: 329, tags: ['tênis', 'esporte'], couponCode: 'CORRE20', couponDiscount: 20, couponVerified: false, lastCouponCheckMinutes: 95),
  Product(id: 'p4', name: 'Jaqueta Corta Vento', category: 'Roupas', brand: 'Urban', marketplace: 'AliExpress', price: 159, originalPrice: 249, tags: ['jaqueta', 'moda']),
  Product(id: 'p5', name: 'Relógio Smart Fit', category: 'Acessórios', brand: 'Pulse', marketplace: 'Magazine Luiza', price: 299, originalPrice: 449, tags: ['relógio', 'fitness'], couponCode: 'FIT30', couponDiscount: 30, couponVerified: true, lastCouponCheckMinutes: 18),
  Product(id: 'p6', name: 'Mochila Executiva USB', category: 'Acessórios', brand: 'Urban', marketplace: 'Shopee', price: 119, originalPrice: 179, tags: ['mochila', 'trabalho']),
  Product(id: 'p7', name: 'Blocos de Montar 800 peças', category: 'Brinquedos', brand: 'BuildUp', marketplace: 'Mercado Livre', price: 139, originalPrice: 219, tags: ['blocos', 'infantil'], couponCode: 'BRINCA25', couponDiscount: 25, couponVerified: true, lastCouponCheckMinutes: 21),
  Product(id: 'p8', name: 'Carrinho Controle Remoto 4x4', category: 'Brinquedos', brand: 'TurboKid', marketplace: 'Amazon', price: 189, originalPrice: 279, tags: ['carrinho', 'controle remoto']),
  Product(id: 'p9', name: 'Whey Protein 900 g', category: 'Suplementos', brand: 'NutriLab', marketplace: 'Magazine Luiza', price: 109, originalPrice: 149, tags: ['whey', 'proteína']),
  Product(id: 'p10', name: 'Creatina 300 g', category: 'Suplementos', brand: 'NutriLab', marketplace: 'Mercado Livre', price: 79, originalPrice: 109, tags: ['creatina', 'academia'], couponCode: 'NUTRI10', couponDiscount: 10, couponVerified: false, lastCouponCheckMinutes: 70),
];

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
          final ranked = engine.recommend(demoProducts);
          return CustomScrollView(slivers: [
            const SliverToBoxAdapter(child: PageTitle('Ofertas para você', 'Menos spam. Mais ofertas que combinam com o que você realmente procura.')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: PreferenceEngine.categories.map((category) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(category),
                      selected: engine.explicit.contains(category),
                      onSelected: (value) => engine.setExplicit(category, value),
                    ),
                  )).toList(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverList.builder(
              itemCount: ranked.length,
              itemBuilder: (context, i) => ProductCard(product: ranked[i], engine: engine),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
  String query = '';

  List<Product> get results {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return demoProducts;
    return demoProducts.where((p) => '${p.name} ${p.category} ${p.brand} ${p.tags.join(' ')}'.toLowerCase().contains(q)).toList();
  }

  void submit(String value) {
    widget.engine.registerSearch(value, results);
    setState(() => query = value);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const PageTitle('Buscar o menor preço', 'Pesquise uma vez; o app aprende seus interesses e recomenda alternativas similares.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            hintText: 'Produto, marca ou categoria',
            leading: const Icon(Icons.search),
            onChanged: (value) => setState(() => query = value),
            onSubmitted: submit,
            trailing: [IconButton(onPressed: () => submit(query), icon: const Icon(Icons.arrow_forward))],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: ListView(children: results.map((p) => ProductCard(product: p, engine: widget.engine)).toList())),
      ]);
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.engine});
  final Product product;
  final PreferenceEngine engine;

  String money(double value) => 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

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
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Icon(_iconFor(product.category), size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('-${product.discountPercent.round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
              ]),
              const SizedBox(height: 4),
              Text('${product.marketplace} • ${product.category}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Text(money(product.finalPrice), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              if (product.couponCode != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.confirmation_num_outlined, size: 17),
                  const SizedBox(width: 4),
                  Expanded(child: Text('${product.couponCode} • ${money(product.couponDiscount)} OFF')),
                  Icon(product.couponVerified ? Icons.verified : Icons.info_outline, size: 18, color: product.couponVerified ? Colors.green : Colors.orange),
                ]),
              ],
            ])),
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
    final similar = engine.similar(product, demoProducts);
    return Scaffold(
      appBar: AppBar(title: const Text('Oferta')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(product.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('${product.marketplace} • ${product.brand} • ${product.category}'),
        const SizedBox(height: 18),
        Text('R\$ ${product.finalPrice.toStringAsFixed(2).replaceAll('.', ',')}', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
        if (product.couponCode != null) Card(
          child: ListTile(
            leading: Icon(product.couponVerified ? Icons.verified : Icons.warning_amber),
            title: Text('Cupom ${product.couponCode}'),
            subtitle: Text(product.couponVerified
                ? 'Verificado na demonstração • última checagem há ${product.lastCouponCheckMinutes} min'
                : 'Cupom demonstrativo ainda não confirmado por integração oficial.'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => showWishDialog(context, product, engine), icon: const Icon(Icons.notifications_active_outlined), label: const Text('Quero comprar — monitorar')),
        const SizedBox(height: 28),
        Text('Você também pode gostar', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...similar.map((p) => ProductCard(product: p, engine: engine)),
      ]),
    );
  }
}

Future<void> showWishDialog(BuildContext context, Product product, PreferenceEngine engine) async {
  var months = 3;
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Quero comprar'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        const Text('Monitorar por'),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [1, 3, 6, 12].map((m) => ChoiceChip(label: Text('$m ${m == 1 ? 'mês' : 'meses'}'), selected: months == m, onSelected: (_) => setDialogState(() => months = m))).toList()),
        const SizedBox(height: 14),
        TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Preço-alvo (opcional)', prefixText: 'R\$ ')),
        const SizedBox(height: 10),
        const Text('Você receberá alertas de preço menor e novos cupons durante esse período.', style: TextStyle(fontSize: 13)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Monitorar'))],
    )),
  );
  controller.dispose();
  if (confirmed == true) {
    final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
    engine.addWish(product, months: months, targetPrice: parsed);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} será acompanhado por $months ${months == 1 ? 'mês' : 'meses'}')));
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
            const PageTitle('Quero comprar', 'Acompanhe por meses e seja avisado quando surgir preço melhor ou novo cupom.'),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Salve produtos no botão de marcador para começar o monitoramento.')))
                  : ListView(children: items.map((item) {
                      final product = demoProducts.firstWhere((p) => p.id == item.productId);
                      final expires = DateTime(item.createdAt.year, item.createdAt.month + item.months, item.createdAt.day);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Monitorar até ${expires.day.toString().padLeft(2, '0')}/${expires.month.toString().padLeft(2, '0')}/${expires.year}${item.targetPrice != null ? ' • alvo R\$ ${item.targetPrice!.toStringAsFixed(2).replaceAll('.', ',')}' : ''}'),
                          trailing: IconButton(onPressed: () => engine.removeWish(product.id), icon: const Icon(Icons.delete_outline)),
                        ),
                      );
                    }).toList()),
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
            const PageTitle('Cupons recomendados', 'Priorizados por seus interesses e pela qualidade da oferta. Integrações reais serão validadas por marketplace.'),
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
            const PageTitle('Suas preferências', 'Você escolhe interesses e o app aprende com pesquisas, cliques, favoritos e produtos que pretende comprar.'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('Interesses escolhidos', style: TextStyle(fontWeight: FontWeight.w800))),
            ...PreferenceEngine.categories.map((category) => SwitchListTile(
              title: Text(category),
              value: engine.explicit.contains(category),
              onChanged: (value) => engine.setExplicit(category, value),
            )),
            const Divider(height: 30),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('O que o app aprendeu', style: TextStyle(fontWeight: FontWeight.w800))),
            if (learned.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('Ainda não há comportamento suficiente. Pesquise ou abra produtos para personalizar seu feed.')),
            ...learned.take(12).map((entry) => ListTile(
              title: Text(entry.key),
              trailing: Text('${entry.value.round()} pts'),
              subtitle: LinearProgressIndicator(value: (entry.value / 100).clamp(0, 1).toDouble()),
            )),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Privacidade: nesta versão, as preferências ficam armazenadas localmente no aparelho. O usuário continuará podendo controlar seus interesses.', style: TextStyle(color: Colors.black54)),
            ),
          ]);
        },
      );
}
