import '../models/hunting_record.dart';

/// Результат проверки законности охоты.
class LegalityVerdict {
  /// Найден ли вид в справочнике региона.
  final bool speciesFound;

  /// Допустима ли охота (с учётом запретов).
  final bool allowed;

  /// Все записи справочника, подходящие под запрос (матчинг по виду/ресурсу).
  final List<HuntingRecord> matches;

  /// Записи, в период которых попадает проверяемая дата.
  final List<HuntingRecord> active;

  /// Запись с прямым запретом в `restrictions`, если есть.
  final HuntingRecord? forbidden;

  const LegalityVerdict({
    required this.speciesFound,
    required this.allowed,
    required this.matches,
    required this.active,
    this.forbidden,
  });
}

/// Расчёт законности охоты по данным справочника `hunting_seasons`.
///
/// Логика не хардкодится: период ы берутся из записей [HuntingRecord], которые
/// приложение получает с сервера (SeasonsProvider). Если на сервере изменят
/// сроки — калькулятор автоматически начнёт считать по новым данным.
class LegalityService {
  /// Проверка законности охоты на [query] в [date] по записям региона.
  static LegalityVerdict check({
    required List<HuntingRecord> regionRecords,
    required String query,
    required DateTime date,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const LegalityVerdict(
        speciesFound: false,
        allowed: false,
        matches: [],
        active: [],
      );
    }
    final matches = regionRecords
        .where((r) => _nameMatches(r.species, q) || _nameMatches(r.resource, q))
        .toList(growable: false);
    if (matches.isEmpty) {
      return const LegalityVerdict(
        speciesFound: false,
        allowed: false,
        matches: [],
        active: [],
      );
    }

    final active =
        matches.where((r) => _insidePeriod(r, date)).toList(growable: false);
    if (active.isEmpty) {
      return LegalityVerdict(
        speciesFound: true,
        allowed: false,
        matches: matches,
        active: const [],
      );
    }

    final forbidden = _firstForbidden(active);
    return LegalityVerdict(
      speciesFound: true,
      allowed: forbidden == null,
      matches: matches,
      active: active,
      forbidden: forbidden,
    );
  }

  /// Уникальные названия видов для региона (для подсказок).
  static List<String> speciesNames(List<HuntingRecord> regionRecords) {
    final seen = <String>{};
    for (final r in regionRecords) {
      seen.add(r.species);
    }
    final list = seen.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Подсказки видов по введённому тексту.
  static List<String> suggestions(
      List<HuntingRecord> regionRecords, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return speciesNames(regionRecords)
        .where((s) => _nameMatches(s, q))
        .toList(growable: false);
  }

  /// Совпадает ли строка названия с запросом: подстрока или упрощённая
  /// словоформа («утка» ≈ «утки», «зайца» ≈ «заяц»).
  static bool _nameMatches(String raw, String query) {
    final q = _stem(query.trim().toLowerCase());
    if (q.isEmpty) return false;
    return raw.toLowerCase().split(',').any((part) {
      final n = part.trim();
      final s = _stem(n);
      return n.contains(q) || s.contains(q);
    });
  }

  /// Грубый стемминг: срезает последнюю гласную/мягкий знак, чтобы ловить
  /// склонения («утки» → «утк», «медведя» → «медвед»).
  static String _stem(String s) {
    const endings = ['а', 'и', 'ы', 'у', 'е', 'о', 'я', 'ь'];
    var out = s;
    final tail = out.isNotEmpty ? out[out.length - 1] : '';
    if (out.length > 3 && endings.contains(tail)) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  /// Попадает ли [date] в годовые периоды записи.
  ///
  /// Учитывает периоды, переходящие через границу года (01.06-28.02,
  /// 15.08-16.01): дата в январе-феврале попадает в отрезок
  /// «открытие прошлого года → закрытие этого», дата в ноябре-декабре —
  /// в отрезок «открытие этого года → закрытие следующего».
  static bool _insidePeriod(HuntingRecord r, DateTime date) {
    final y = date.year;
    final open = r.openDateForYear(y);
    final prevOpen = r.openDateForYear(y - 1);
    final close = r.closeDateInYear(y, open: open);
    if (open == null || close == null) return false;
    final start = open;
    final end = close;
    if (!start.isAfter(end)) {
      return !date.isBefore(start) && !date.isAfter(end);
    }
    final prevStart = prevOpen ?? start;
    final nextEnd =
        r.closeDateInYear(y + 1, open: r.openDateForYear(y + 1)) ?? end;
    return (!date.isBefore(prevStart) && !date.isAfter(end)) ||
        (!date.isBefore(start) && !date.isAfter(nextEnd));
  }

  /// Первая запись с прямым запретом в ограничениях.
  /// Такая запись означает «охота не разрешена» (например, весенний
  /// запрет на пернатую дичь), даже если дата попадает в её период.
  static HuntingRecord? _firstForbidden(List<HuntingRecord> records) {
    for (final r in records) {
      final res = r.restrictions?.toLowerCase() ?? '';
      if (res.contains('запрет') ||
          res.contains('запрещен') ||
          res.contains('запреща')) {
        return r;
      }
    }
    return null;
  }
}