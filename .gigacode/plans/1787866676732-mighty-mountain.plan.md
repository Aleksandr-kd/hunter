# План: Улучшение StatsScreen (пункты 1, 2, 3, 7)

## Цель
Последовательно реализовать 4 улучшения страницы статистики:
1. **Animated summary cards** — анимированные счётчики с трендами (↑↓ %)
2. **Продвинутая визуализация** — Pie chart (виды) + Line chart (динамика по месяцам)
3. **Smart insights** — блок с auto-generated текстовыми инсайтами
7. **UX/UI улучшения** — pull-to-refresh, animated counters, skeleton loading, empty state

---

## ШАГ 1: Добавить зависимости в pubspec.yaml

**Файл:** `pubspec.yaml`

Добавить пакеты:
```yaml
dependencies:
  fl_chart: ^0.69.2        # профессиональные графики
  animated_numbers: ^0.0.5 # анимация счётчиков
  intl: ^0.19.0            # форматирование дат/чисел (уже может быть)
```

---

## ШАГ 2: Создать утилиты для аналитики

**Файл:** `lib/services/analytics_service.dart` (НОВЫЙ)

Статический сервис для расчёта метрик из `List<DiaryEntry>`:

```dart
class AnalyticsService {
  // --- Summary metrics ---
  static int totalEntries(List<DiaryEntry> entries);
  static int speciesCount(List<DiaryEntry> entries);
  static int entriesWithLocation(List<DiaryEntry> entries);
  static int entriesWithPhoto(List<DiaryEntry> entries);

  // --- Trend calculation (compare last 3 months vs previous 3 months) ---
  static TrendInfo calculateTrend(List<DiaryEntry> entries);
  // TrendInfo: { int currentCount, int previousCount, double percentChange }

  // --- Month distribution (for line chart) ---
  static Map<String, int> monthDistribution(List<DiaryEntry> entries);
  // Returns ordered map: ['Сен': 5, 'Окт': 12, ...]

  // --- Species distribution (for pie chart) ---
  static Map<String, int> speciesDistribution(List<DiaryEntry> entries);
  // Returns: {'Кабан': 15, 'Заяц': 8, ...}

  // --- Weight stats ---
  static WeightStats calculateWeightStats(List<DiaryEntry> entries);
  // WeightStats: { double total, double average, double? max, int entriesWithWeight }

  // --- Top species leaderboard ---
  static List<TopSpecies> getTopSpecies(List<DiaryEntry> entries, {int limit = 5});
  // TopSpecies: { String species, int count, double percentage }

  // --- Season comparison ---
  static Map<String, int> seasonDistribution(List<DiaryEntry> entries);
  // Returns: {'Осень': 25, 'Весна': 10, ...}

  // --- Top locations ---
  static List<TopLocation> getTopLocations(List<DiaryEntry> entries, {int limit = 5});
  // TopLocation: { String location, int count }

  // --- Smart insights generation ---
  static List<Insight> generateInsights(List<DiaryEntry> entries);
  // Insight: { String title, String description, IconData icon, InsightType type }
  // Types: info, achievement, tip, warning

  // --- Achievements ---
  static List<Achievement> checkAchievements(List<DiaryEntry> entries);
  // Achievement: { String title, String description, IconData icon, bool unlocked }
}
```

**Логика генерации insights:**
- «Вы чаще всего охотитесь на [вид]» — top species
- «Ваш средний вес добычи — [X] кг» — если есть вес
- «Больше всего записей в сезоне [осень/весна…]» — season comparison
- «Вы посетили [X] уникальных мест» — location count
- «[X] записей с фото — [Y]% от всех» — photo stats
- «Вы не охотили [N] дней» — inactivity warning (если последняя запись > 30 дней назад)
- Достижения: первая запись (1), 10 записей, 50 записей, 100 записей, первый вес, 5 видов, 10 видов, 5 мест, 10 мест

**Логика трендов:**
- Разделить entries на два периода: «текущие 3 месяца» vs «предыдущие 3 месяца»
- Сравнить количество записей → percentChange
- Показать: ↑ 25% (зелёный) / ↓ 10% (красный) / — 0% (серый)

---

## ШАГ 3: Создать виджеты для улучшенной статистики

**Файл:** `lib/widgets/stats_widgets.dart` (НОВЫЙ)

### 3a. AnimatedStatCard — анимированная карточка статистики
```dart
class AnimatedStatCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final int startValue;
  final int endValue;
  final Color? color;
  final TrendInfo? trend; // optional trend indicator
}
```
- Анимация числа от `startValue` → `endValue` через `AnimatedCrossFade` + `TickerProviderStateMixin`
- Иконка + label как сейчас
- Если есть `trend` — показать маленькую стрелку ↑↓ с % под числом

### 3b. SpeciesPieChart — круговая диаграмма
```dart
class SpeciesPieChart extends StatelessWidget {
  final Map<String, int> data;
}
```
- Использовать `fl_chart` — `PieChart` с `PieChartSectionData`
- Цвета из `Theme.of(context).colorScheme`
- Легенда справа с названиями видов и процентами
- Пустое состояние: «Нет данных для отображения»

### 3c. ActivityLineChart — линейный график активности
```dart
class ActivityLineChart extends StatelessWidget {
  final Map<String, int> data;
}
```
- Использовать `fl_chart` — `LineChart` с `LineChartData`
- Smooth curves (`CurveType.smooth`)
- Точки на каждом месяце с тултипами (`LineTouchData`)
- Градиент под линией (`gradient: LinearGradient(...)`)
- Ось X — месяцы, ось Y — количество записей

### 3d. TopSpeciesList — рейтинг видов
```dart
class TopSpeciesList extends StatelessWidget {
  final List<TopSpecies> species;
}
```
- Список с иконками (`Icons.pets`)
- Прогресс-бар под каждым видом (процент от общего)
- Название + количество + %

### 3e. SeasonComparisonCard — сравнение сезонов
```dart
class SeasonComparisonCard extends StatelessWidget {
  final Map<String, int> seasons;
}
```
- 4 карточки (или иконки): Весна / Лето / Осень / Зима
- Количество записей + мини-бар
- Выделить самый продуктивный сезон

### 3f. SmartInsightsCard — блок умных инсайтов
```dart
class SmartInsightsCard extends StatelessWidget {
  final List<Insight> insights;
}
```
- Каждый insight — GlassCard с иконкой и текстом
- Тип insight определяет цвет иконки (info=blue, achievement=amber, tip=green, warning=red)
- Максимум 5 инсайтов, если пусто — не показывать

### 3g. SkeletonStatsCard — skeleton loading
```dart
class SkeletonStatsCard extends StatelessWidget {
  // Shimmer-эффект для placeholder при загрузке
}
```

---

## ШАГ 4: Обновить StatsScreen

**Файл:** `lib/screens/stats_screen.dart`

### 4a. Перейти на StatefulWidget
- Добавить `SingleTickerProviderStateMixin` для анимаций
- `_controller` для анимации счётчиков

### 4b. Обновить `_summaryCards()`
Было: 4 статичных `_stat()` колонки
Станет: 4 `AnimatedStatCard` с анимацией чисел + тренд-индикатор

```dart
Widget _summaryCards(BuildContext context, DiaryProvider diary) {
  final trend = AnalyticsService.calculateTrend(entries);
  return GlassCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Ваша статистика', ...),
          const SizedBox(height: 12),
          Row(
            children: [
              AnimatedStatCard(
                icon: Icons.menu_book,
                label: 'записей',
                endValue: entries.length,
                trend: trend,
              ),
              AnimatedStatCard(
                icon: Icons.pets,
                label: 'видов',
                endValue: speciesCount,
              ),
              AnimatedStatCard(
                icon: Icons.place,
                label: 'с гео',
                endValue: withLocation,
              ),
              AnimatedStatCard(
                icon: Icons.photo,
                label: 'с фото',
                endValue: withPhoto,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

### 4c. Обновить `_maxFeatures()` — заменить AnalyticsScreen
Было: навигация на `AnalyticsScreen` с простыми барами
Ст��нет: встроенная секция с:
- `ActivityLineChart` — динамика по месяцам
- `SpeciesPieChart` — распределение по видам
- `TopSpeciesList` — топ-5 видов
- `SeasonComparisonCard` — сравнение сезонов

```dart
List<Widget> _maxFeatures(BuildContext context, DiaryProvider diary) {
  return [
    const Text('Аналитика', style: TextStyle(fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    ActivityLineChart(data: AnalyticsService.monthDistribution(entries)),
    const SizedBox(height: 16),
    SpeciesPieChart(data: AnalyticsService.speciesDistribution(entries)),
    const SizedBox(height: 16),
    TopSpeciesList(species: AnalyticsService.getTopSpecies(entries)),
    const SizedBox(height: 16),
    SeasonComparisonCard(seasons: AnalyticsService.seasonDistribution(entries)),
  ];
}
```

### 4d. Добавить SmartInsightsCard
После `_maxFeatures`, перед `_exportCard`:
```dart
SmartInsightsCard(insights: AnalyticsService.generateInsights(entries)),
```

### 4e. Добавить Achievements
Внутри `_summaryCards` или отдельной секцией после insights:
```dart
List<Achievement> achievements = AnalyticsService.checkAchievements(entries);
// Показать разблокированные достижения с иконками
```

### 4f. Skeleton loading
Если `!diary.loaded` — показывать `SkeletonStatsCard` вместо `CircularProgressIndicator`:
```dart
body: !diary.loaded
    ? const SkeletonStatsScreen()
    : RefreshIndicator(
        onRefresh: () => diary.load(),
        child: ListView(...),
      ),
```

### 4g. Pull-to-refresh
Обернуть `ListView` в `RefreshIndicator` с `onRefresh: diary.load`

### 4h. Убрать AnalyticsScreen и LegalityScreen из StatsScreen
- `AnalyticsScreen` больше не нужен (всё встроено)
- `LegalityScreen` оставить, но переместить в отдельную секцию «Инструменты»

### 4i. Новая структура экрана
```
Scaffold
  └── RefreshIndicator
        └── ListView
              ├── Skeleton (если !loaded)
              ├── Animated summary cards (4 шт)
              ├── Smart insights (0-5 шт)
              ├── Achievements (если есть разблокированные)
              ├── Activity line chart
              ├── Species pie chart
              ├── Top species list
              ├── Season comparison
              ├── Legality calculator (Tools section)
              └── Export card (Premium+)
```

---

## ШАГ 5: Обновить DiaryProvider (опционально)

**Файл:** `lib/providers/diary_provider.dart`

Добавить computed property для быстрой валидации:
```dart
// В DiaryProvider — не нужно, аналитика считается в AnalyticsService
// DiaryProvider остаётся как есть — только CRUD + sync
```

**Решение:** Не менять `DiaryProvider`. Вся аналитика — в `AnalyticsService` (stateless, pure functions).

---

## ШАГ 6: Обновить тесты

**Файл:** `test/services/analytics_service_test.dart` (НОВЫЙ)

Тесты для `AnalyticsService`:
- `calculateTrend` — корректный расчёт % изменения
- `monthDistribution` — правильный порядок месяцев
- `speciesDistribution` — правильный подсчёт
- `generateInsights` — инсайты генерируются для разных сценариев
- `checkAchievements` — достижения разблокируются при достижении порогов
- `getTopSpecies` — правильный рейтинг с limit

**Файл:** `test/screens/stats_screen_test.dart` (НОВЫЙ)

Widget-тесты:
- StatsScreen показывает skeleton при загрузке
- StatsScreen показывает summary cards после загрузки
- Pull-to-refresh вызывает diary.load()

---

## ШАГ 7: Верификация

### 7a. Команды проверки
```bash
flutter pub get                    # установить новые пакеты
flutter analyze                    # 0 issues
flutter test                       # все тесты зелёные
flutter build apk --debug          # сборка успешна
```

### 7b. Ручная проверка
1. Открыть StatsScreen — skeleton loading появляется при первом старте
2. После загрузки — числа анимируются (0 → реальное значение)
3. Тренд показывает ↑↓ с % — проверить с данными за разные периоды
4. Line chart — smooth curves, точки с тултипами, градиент
5. Pie chart — все виды, легенда с процентами
6. Top species — сортировка по убыванию, прогресс-бары
7. Season comparison — 4 сезона, выделен максимум
8. Smart insights — тексты генерируются корректно
9. Achievements — бейджи появляются при достижении порогов
10. Pull-to-refresh — свайп вниз обновляет данные
11. Empty state — если нет записей, показывать «Добавьте первую запись»
12. Тёмная тема — всё корректно отображается

### 7c. Edge cases
- 0 записей — все графики показывают empty state
- 1 запись — графики не падают, показывают корректно
- Все записи за один месяц — line chart показывает одну точку
- Все записи одного вида — pie chart показывает один сектор
- Нет весов — weight stats не показывать
- Нет координат — location stats не показывать

---

## Список файлов для изменения

| Файл | Действие |
|------|----------|
| `pubspec.yaml` | Добавить зависимости |
| `lib/services/analytics_service.dart` | **НОВЫЙ** — расчёт метрик |
| `lib/widgets/stats_widgets.dart` | **НОВЫЙ** — виджеты графиков |
| `lib/screens/stats_screen.dart` | **МОДИФИЦИРОВАТЬ** — полная переработка |
| `test/services/analytics_service_test.dart` | **НОВЫЙ** — unit тесты |
| `test/screens/stats_screen_test.dart` | **НОВЫЙ** — widget тесты |

## Порядок реализации
1. `pubspec.yaml` + `flutter pub get`
2. `analytics_service.dart` — сервис расчётов
3. `stats_widgets.dart` — все виджеты
4. `stats_screen.dart` — интеграция
5. Тесты
6. Верификация (`analyze` + `test` + `build`)
