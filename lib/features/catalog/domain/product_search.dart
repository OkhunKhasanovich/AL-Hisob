import '../../../core/search/text_normalizer.dart';
import '../../../core/search/token_matcher.dart';
import 'product_summary.dart';

/// Вес категории относительно названия.
const _categoryWeight = 0.85;

class ProductHit {
  const ProductHit({required this.summary, required this.score});

  final ProductSummary summary;
  final double score;
}

class _Entry {
  _Entry(this.summary)
      : nameTokens = searchTokens(summary.product.name),
        categoryTokens = searchTokens(summary.product.category ?? '');

  final ProductSummary summary;
  final List<String> nameTokens;
  final List<String> categoryTokens;
}

/// Поиск по названию и категории: транслитерация (кириллица ↔ латиница),
/// опечатки, поиск по мере набора. Каждое слово запроса должно найтись.
class ProductSearchIndex {
  ProductSearchIndex(Iterable<ProductSummary> items) : _entries = [for (final s in items) _Entry(s)];

  final List<_Entry> _entries;

  /// Пустой запрос возвращает все товары в исходном порядке.
  List<ProductHit> search(String query) {
    final words = searchTokens(query);
    if (words.isEmpty) {
      return [for (final e in _entries) ProductHit(summary: e.summary, score: 0)];
    }

    final hits = <ProductHit>[];
    for (final e in _entries) {
      var total = 0.0;
      var ok = true;
      for (final w in words) {
        final s = _score(w, e);
        if (s == 0) {
          ok = false;
          break;
        }
        total += s;
      }
      if (!ok) continue;
      var score = total / words.length;
      if (toSearchKey(query) == toSearchKey(e.summary.product.name)) score += 0.05;
      hits.add(ProductHit(summary: e.summary, score: score));
    }

    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.summary.product.name.toLowerCase().compareTo(b.summary.product.name.toLowerCase());
    });
    return hits;
  }

  double _score(String word, _Entry e) {
    var best = 0.0;
    for (final t in e.nameTokens) {
      final s = scoreToken(word, t);
      if (s > best) best = s;
    }
    for (final t in e.categoryTokens) {
      final s = scoreToken(word, t) * _categoryWeight;
      if (s > best) best = s;
    }
    return best;
  }
}
