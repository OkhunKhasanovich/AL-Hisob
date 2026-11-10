import 'edit_distance.dart';

/// Допустимое число опечаток для слова запроса длиной [length].
///
/// Короткие слова не «исправляем» (иначе «Ali» совпадёт с «Ola» и «Ila»).
/// Две опечатки допускаются только с 8 букв: иначе похожие фамилии разных
/// людей (Karimov и Rahimov отличаются двумя буквами) считались бы одним.
int maxTypos(int length) {
  if (length <= 3) return 0;
  if (length <= 7) return 1;
  return 2;
}

/// Расстояние с учётом того, что `S`/`C` в ключе — это «sh»/«ch»: опечатка
/// внутри диграфа («alisehr» вместо «alisher») в схлопнутой форме стоила бы
/// две правки, а в развёрнутой — одну. Берём лучшее из двух.
int _distance(String q, String c, int limit) {
  final collapsed = damerauLevenshtein(q, c, limit: limit);
  if (collapsed <= 1 || !(_hasDigraph(q) || _hasDigraph(c))) return collapsed;
  final expanded = damerauLevenshtein(_expand(q), _expand(c), limit: limit);
  return expanded < collapsed ? expanded : collapsed;
}

bool _hasDigraph(String s) => s.contains('S') || s.contains('C');

String _expand(String s) => s.replaceAll('S', 'sh').replaceAll('C', 'ch');

/// Оценка совпадения слова запроса [q] со словом [c] (оба — уже ключи
/// поиска) в диапазоне 0…1; 0 — не совпало.
///
/// Лестница оценок (по убыванию):
/// * 1.0 — слова равны;
/// * 0.85–0.95 — [c] начинается с [q] (поиск «по мере набора»), чем больше
///   слово набрано, тем выше;
/// * 0.7–0.8 — слово целиком с опечатками;
/// * 0.5–0.6 — [q] внутри [c] (не в начале) либо опечатки в начале слова.
double scoreToken(String q, String c) {
  if (q.isEmpty || c.isEmpty) return 0;
  if (q == c) return 1.0;

  if (c.startsWith(q)) return 0.85 + 0.1 * (q.length / c.length);

  final typos = maxTypos(q.length);

  if (typos > 0) {
    final d = _distance(q, c, typos);
    if (d <= typos) return 0.8 - 0.05 * d;

    // Опечатка в уже набранной части длинного слова: сравниваем с началом.
    if (c.length > q.length) {
      var best = typos + 1;
      for (var k = q.length - 1; k <= q.length + 1; k++) {
        if (k < 1 || k > c.length) continue;
        final dp = damerauLevenshtein(q, c.substring(0, k), limit: typos);
        if (dp < best) best = dp;
      }
      if (best <= typos) return 0.6 - 0.05 * best;
    }
  }

  if (q.length >= 3 && c.contains(q)) return 0.55;
  return 0;
}
