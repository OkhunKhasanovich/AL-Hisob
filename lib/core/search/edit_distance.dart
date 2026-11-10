import 'dart:math' as math;

/// Расстояние Дамерау–Левенштейна (вариант OSA): вставка, удаление,
/// замена и перестановка двух соседних символов стоят по 1.
///
/// Если расстояние заведомо больше [limit], возвращает `limit + 1`
/// (досрочный выход ускоряет поиск по длинным спискам).
int damerauLevenshtein(String a, String b, {int? limit}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if (limit != null && (a.length - b.length).abs() > limit) return limit + 1;

  final n = a.length, m = b.length;
  var prevPrev = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var curr = List<int>.filled(m + 1, 0);

  for (var i = 1; i <= n; i++) {
    curr[0] = i;
    var rowMin = curr[0];
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = math.min(
        math.min(prev[j] + 1, curr[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        v = math.min(v, prevPrev[j - 2] + 1);
      }
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (limit != null && rowMin > limit) return limit + 1;
    final tmp = prevPrev;
    prevPrev = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[m];
}
