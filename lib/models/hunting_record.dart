/// Одна строка срока охоты на вид дичи в конкретном регионе, ресурсе и сезоне.
///
/// Один вид может иметь несколько записей [HuntingRecord] (например, вальдшнеп:
/// 15.08-16.01 только с собаками и 15.08-31.12 без). Все строки показываются
/// пользователю вместе — каждая со своими сроками и ограничениями.
class HuntingRecord {
  final String regionId;
  final String regionName;
  final String resource; // «Пернатая дичь», «Копытные животные» и т.д.
  final String season; // Весна / Лето / Осень / Зима
  final String species; // «вальдшнеп», «Кабан: все половозрастные группы» и т.д.
  final String? openDate; // "15.08" или null/пусто
  final String? closeDate; // "16.01" или null/пусто
  final String? restrictions; // ограничения / примечания
  final String? zone; // зона охоты ("Все" и т.п.)

  /// Машиночитаемое правило открытия сезона, например «4-sat:09» —
  /// четвёртая суббота сентября, «3-sat:08» — третья суббота августа.
  /// Если задано, дата открытия вычисляется на каждый год, иначе берётся
  /// фиксированный [openDate].
  final String? dateRule;

  /// Аналог [dateRule] для даты закрытия (например «4-sun:11» — четвёртое
  /// воскресенье ноября). Если пусто — фиксированный [closeDate].
  final String? closeRule;

  const HuntingRecord({
    required this.regionId,
    required this.regionName,
    required this.resource,
    required this.season,
    required this.species,
    this.openDate,
    this.closeDate,
    this.restrictions,
    this.zone,
    this.dateRule,
    this.closeRule,
  });

  /// Полная строка «сроки» (например "15.08-16.01"). Для записей с [dateRule] /
  /// [closeRule] соответствующие даты подставляются вычисленными на текущий
  /// календарный год.
  String get datesLabel {
    if (openDate == null || openDate!.isEmpty) return '—';
    final open =
        _ruleLabel(dateRule, openDate!, DateTime.now().year, openDateForYear);
    if (closeDate == null || closeDate!.isEmpty) return open;
    final close = _ruleLabel(
        closeRule, closeDate!, DateTime.now().year, (y) {
      final o = openDateForYear(y);
      return o == null ? null : closeDateInYear(y, open: o);
    });
    return '$open-$close';
  }

  /// Дата открытия для конкретного [year]: по [dateRule], если задан,
  /// иначе фиксированный [openDate] с этим годом. null — если данных нет.
  DateTime? openDateForYear(int year) {
    if (dateRule != null && dateRule!.isNotEmpty) {
      return _parseRule(dateRule!, year);
    }
    final open = _parseDate(openDate);
    if (open == null) return null;
    return DateTime(year, open.month, open.day);
  }

  /// Дата закрытия в том же [year] (без перехода границы года): по [closeRule],
  /// иначе фиксированный [closeDate] с этим годом. null — если данных нет.
  /// [open] обязателен только для продолжительности в [closeRule] вида «+N»
  /// (закрытие = открытие + N дней, например «10 дней охоты»).
  DateTime? closeDateInYear(int year, {DateTime? open}) {
    final cr = closeRule;
    if (cr != null && cr.isNotEmpty) {
      if (cr.startsWith('+')) {
        final n = int.tryParse(cr.substring(1));
        if (n == null || n < 0 || open == null) return null;
        return open.add(Duration(days: n));
      }
      return _parseRule(cr, year);
    }
    final close = _parseDate(closeDate);
    if (close == null) return null;
    return DateTime(year, close.month, close.day);
  }

  /// Дата закрытия для [year] относительно [open]: при переходе через границу
  /// года закрытие попадает на следующий год. null — если close отсутствует.
  DateTime? closeDateForYear(int year, DateTime open) {
    final close = closeDateInYear(year, open: open);
    if (close == null) return null;
    if (!close.isBefore(open)) return close;
    return closeDateInYear(year + 1, open: open);
  }

  /// Строка «ДД.ММ» для [year]: если задано правило — вычисленная дата,
  /// иначе фиксированная дата из [fallback].
  String _ruleLabel(
    String? rule,
    String fallback,
    int year,
    DateTime? Function(int year)? compute,
  ) {
    if (rule == null || rule.isEmpty || compute == null) return fallback;
    final d = compute(year);
    if (d == null) return fallback;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm';
  }

  static final RegExp _ruleRe =
      RegExp(r'^(\d+)-(mon|tue|wed|thu|fri|sat|sun):(\d{1,2})$');

  static const Map<String, int> _weekdays = {
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };

  /// Парсинг «N-wd:MM» (например «4-sat:09»). Возвращает дату для [year].
  static DateTime? _parseRule(String rule, int year) {
    final m = _ruleRe.firstMatch(rule.toLowerCase());
    if (m == null) return null;
    final nth = int.tryParse(m.group(1)!) ?? 0;
    if (nth < 1 || nth > 5) return null;
    final wd = _weekdays[m.group(2)];
    final month = int.tryParse(m.group(3)!) ?? 0;
    if (wd == null || month < 1 || month > 12) return null;
    return _nthWeekday(year, month, wd, nth);
  }

  /// N-й день недели месяца. Если N-й выходит за месяц (редкие «5-я»),
  /// берём последний доступный такой день.
  static DateTime _nthWeekday(int year, int month, int weekday, int nth) {
    final first = DateTime(year, month, 1);
    final diff = (weekday - first.weekday + 7) % 7;
    var date = first.add(Duration(days: diff + (nth - 1) * 7));
    if (date.month != month) {
      date = date.subtract(const Duration(days: 7));
    }
    return date;
  }

  /// Парсинг «ДД.ММ». null — если данных нет.
  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('.');
    if (parts.length != 2) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (d == null || d < 1 || d > 31 || m == null || m < 1 || m > 12) {
      return null;
    }
    return DateTime(2000, m, d);
  }

  /// Отображаемое название при поиске — единый ключ.
  String get searchKey => species.toLowerCase();

  Map<String, dynamic> toJson() => {
        'region_id': regionId,
        'region_name': regionName,
        'resource': resource,
        'season': season,
        'species': species,
        'open_date': openDate,
        'close_date': closeDate,
        'restrictions': restrictions,
        'zone': zone,
        'date_rule': dateRule,
        'close_rule': closeRule,
      };

  factory HuntingRecord.fromJson(Map<String, dynamic> json) {
    return HuntingRecord(
      regionId: json['region_id'] as String? ?? '',
      regionName: json['region_name'] as String? ?? '',
      resource: json['resource'] as String? ?? '',
      season: json['season'] as String? ?? '',
      species: json['species'] as String? ?? '',
      openDate: json['open_date'] as String?,
      closeDate: json['close_date'] as String?,
      restrictions: json['restrictions'] as String?,
      zone: json['zone'] as String?,
      dateRule: json['date_rule'] as String?,
      closeRule: json['close_rule'] as String?,
    );
  }
}