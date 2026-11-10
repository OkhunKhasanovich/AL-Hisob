import '../../../../core/utils/phone.dart';
import '../debt_summary.dart';
import 'phone_matcher.dart';
import 'text_normalizer.dart';
import 'token_matcher.dart';

/// Вес названия магазина относительно имени должника.
const _shopWeight = 0.85;

class SearchHit {
  const SearchHit({required this.summary, required this.score, this.matchedPhone});

  final DebtorSummary summary;

  /// Релевантность 0…~1 (выше — лучше).
  final double score;

  /// Нормализованный телефон, по которому нашли (если в запросе были цифры).
  final String? matchedPhone;
}

class _Entry {
  _Entry(this.summary)
      : nameTokens = searchTokens(summary.debtor.name),
        shopTokens = searchTokens(summary.debtor.shopName ?? ''),
        nameKey = toSearchKey(summary.debtor.name),
        localPhones = [for (final p in summary.phones) (p, localPart(p))];

  final DebtorSummary summary;
  final List<String> nameTokens;
  final List<String> shopTokens;
  final String nameKey;
  final List<(String phone, String local)> localPhones;
}

/// Индекс для поиска по имени, магазину и телефону. Ключи считаются один раз
/// при создании, поэтому поиск по мере набора остаётся быстрым.
///
/// Запрос разбирается так:
/// * все цифры запроса склеиваются в один «телефонный» фрагмент
///   (`+998 (90) 123` → `90123`);
/// * буквы разбиваются на слова; порядок слов не важен;
/// * каждое слово и фрагмент номера обязаны найтись — иначе должник
///   не попадает в выдачу (логическое «И»).
class DebtorSearchIndex {
  DebtorSearchIndex(Iterable<DebtorSummary> summaries)
      : _entries = [for (final s in summaries) _Entry(s)];

  final List<_Entry> _entries;

  int get length => _entries.length;

  /// Пустой (после разбора) запрос возвращает всех, порядок сохраняется.
  List<SearchHit> search(String query) {
    final words = searchTokens(query.replaceAll(RegExp(r'\d'), ' '));
    final digits = queryDigits(query);

    if (words.isEmpty && digits.isEmpty) {
      return [for (final e in _entries) SearchHit(summary: e.summary, score: 0)];
    }

    final fullKey = toSearchKey(query);
    final hits = <SearchHit>[];
    for (final e in _entries) {
      var total = 0.0;
      var parts = 0;
      var ok = true;

      for (final w in words) {
        final s = _scoreWord(w, e);
        if (s == 0) {
          ok = false;
          break;
        }
        total += s;
        parts++;
      }
      if (!ok) continue;

      String? matchedPhone;
      if (digits.isNotEmpty) {
        var best = 0.0;
        for (final (phone, local) in e.localPhones) {
          final s = scorePhone(digits, local);
          if (s > best) {
            best = s;
            matchedPhone = phone;
          }
        }
        if (best == 0) continue;
        total += best;
        parts++;
      }

      var score = total / parts;
      if (words.isNotEmpty && digits.isEmpty && fullKey == e.nameKey) score += 0.05;
      hits.add(SearchHit(summary: e.summary, score: score, matchedPhone: matchedPhone));
    }

    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      final byDebt = b.summary.balance.compareTo(a.summary.balance);
      if (byDebt != 0) return byDebt;
      return a.summary.debtor.name
          .toLowerCase()
          .compareTo(b.summary.debtor.name.toLowerCase());
    });
    return hits;
  }

  double _scoreWord(String word, _Entry e) {
    var best = 0.0;
    for (final t in e.nameTokens) {
      final s = scoreToken(word, t);
      if (s > best) best = s;
    }
    for (final t in e.shopTokens) {
      final s = scoreToken(word, t) * _shopWeight;
      if (s > best) best = s;
    }
    return best;
  }
}

/// Удобная обёртка для разового поиска и тестов.
List<SearchHit> searchDebtors(Iterable<DebtorSummary> all, String query) =>
    DebtorSearchIndex(all).search(query);

/// Подсказка для отображения: `+998 90 123 45 67` для найденного номера.
String? formatMatchedPhone(SearchHit hit) {
  final p = hit.matchedPhone;
  return p == null ? null : formatPhone(p);
}
