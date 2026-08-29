import 'dart:io';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/diary_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../widgets/glass_card.dart';
import 'auth_gate.dart';

/// Элемент модального окна выбора приложения для карт.
class _MapAppItem {
  final String name;
  final Widget icon;
  final VoidCallback onTap;
  const _MapAppItem({
    required this.name,
    required this.icon,
    required this.onTap,
  });
}

/// Результат выбора координат на карте.
class _MapResult {
  final double lat;
  final double lon;
  const _MapResult(this.lat, this.lon);
}

/// Экран Яндекс Карты для выбора/корректировки координат.
class _MapPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLon;
  const _MapPickerScreen({
    required this.initialLat,
    required this.initialLon,
  });

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _controllerInitialized = false;
  bool _webViewStarted = false;
  double _lat = 0;
  double _lon = 0;
  final String _selectedLabel = 'Выбранное место';
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lon = widget.initialLon;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_webViewStarted) {
      // Строим WebView сразу в актуальной теме — без светлой вспышки.
      _isDark = isDark;
      _webViewStarted = true;
      _initWebView(isDark);
    } else if (isDark != _isDark) {
      _isDark = isDark;
      // Тема приложения сменилась на открытой карте — обновляем через JS.
      _applyThemeFilter();
    }
  }

  Future<void> _applyThemeFilter() async {
    try {
      if (!_controllerInitialized) return;
      await _controller.runJavaScriptReturningResult(
        '''
          (function() {
            var map = document.getElementById('map');
            if (!map) return true;
            map.style.filter = ${_isDark.toString()} ? 'invert(1) hue-rotate(180deg)' : 'none';
            map.style.webkitFilter = map.style.filter;
            return true;
          })();
        ''',
      );
      debugPrint('MAP: applied filter $_isDark');
    } catch (e) {
      debugPrint('MAP: error applying filter: $e');
    }
  }

  Timer? _updateTimer;
  String _html = '';
  bool _disposed = false;

  /// API key для Яндекс Карт. В production должен быть передан через
  /// `--dart-define=YANDEX_MAPS_API_KEY=key`.
  static const String _yandexMapsApiKey = String.fromEnvironment(
    'YANDEX_MAPS_API_KEY',
    defaultValue: 'PLACEHOLDER_API_KEY',
  );

  Future<void> _initWebView(bool isDark) async {
    _html = '''
      <!DOCTYPE html>
      <html>
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <title>Yandex Map</title>
          <script src="https://api-maps.yandex.ru/2.1/?apikey=$_yandexMapsApiKey&lang=ru_RU"></script>
          <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              html, body { width: 100%; height: 100%; overflow: hidden; -webkit-user-select: none; user-select: none; -webkit-tap-highlight-color: transparent; background: ${isDark ? '#1e1e1e' : '#ffffff'}; }
              #map { width: 100%; height: 100%; touch-action: none; ${isDark ? '-webkit-filter: invert(1) hue-rotate(180deg); filter: invert(1) hue-rotate(180deg);' : ''} }
              #hint {
                  position: absolute;
                  top: 16px;
                  left: 50%;
                  transform: translateX(-50%);
                  background: ${isDark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.7)'};
                  color: white;
                  padding: 8px 16px;
                  border-radius: 20px;
                  font-size: 13px;
                  z-index: 10;
                  pointer-events: none;
                  white-space: nowrap;
              }
              #myLoc {
                  position: absolute;
                  bottom: 16px;
                  right: 16px;
                  width: 48px;
                  height: 48px;
                  border-radius: 50%;
                  background: ${isDark ? '#1e1e1e' : 'white'};
                  border: 2px solid #4285F4;
                  box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  font-size: 24px;
                  color: #4285F4;
                  z-index: 10;
                  cursor: pointer;
              }
              #myLoc:active { background: ${isDark ? '#333333' : '#f0f0f0'}; }
              #coords {
                  position: absolute;
                  bottom: 80px;
                  left: 50%;
                  transform: translateX(-50%);
                  background: ${isDark ? 'rgba(30,30,30,0.9)' : 'rgba(255,255,255,0.95)'};
                  color: ${isDark ? 'white' : 'black'};
                  padding: 8px 16px;
                  border-radius: 20px;
                  font-size: 13px;
                  font-weight: 500;
                  z-index: 10;
                  pointer-events: none;
                  white-space: nowrap;
                  border: 1px solid ${isDark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.1)'};
              }
          </style>
      </head>
      <body>
          <div id="map"></div>
          <div id="hint">Двойной тап или долгое нажатие — выбрать место</div>
          <div id="myLoc">📍</div>
          <div id="coords">
              <span id="lat">0.000000</span>, <span id="lon">0.000000</span>
          </div>
          <script>
              var map;
              var userPlacemark;
              var selectedPlacemark;
              var userLat = null;
              var userLon = null;
              var initLat = INIT_LAT_PLACEHOLDER;
              var initLon = INIT_LON_PLACEHOLDER;
              var longPressTimer = null;
              var isLongPress = false;

              // Hide hint after 3 seconds
              setTimeout(function() {
                  var hint = document.getElementById('hint');
                  if (hint) hint.style.display = 'none';
              }, 3000);

              // Prevent WebView from blocking touch events
              document.addEventListener('touchstart', function(e) {}, {passive: true});
              document.addEventListener('touchmove', function(e) {}, {passive: true});
              document.addEventListener('touchend', function(e) {}, {passive: true});

              ymaps.ready(init);

              function init() {
                  map = new ymaps.Map('map', {
                      center: [initLat, initLon],
                      zoom: 15,
                      controls: ['zoomControl', 'geolocationControl']
                  }, {
                      searchControlProvider: 'yandex#search'
                  });

                  // Double click to select place
                  map.events.add('dblclick', function (e) {
                      var coords = e.get('coords');
                      selectPlace(coords[0], coords[1]);
                  });

                  // Long press to select place (touch events)
                  map.events.add('mousedown', function () {
                      isLongPress = false;
                      longPressTimer = setTimeout(function () {
                          isLongPress = true;
                      }, 800);
                  });
                  map.events.add('mouseup', function (e) {
                      if (longPressTimer) {
                          clearTimeout(longPressTimer);
                          longPressTimer = null;
                      }
                      if (isLongPress) {
                          var coords = e.get('coords');
                          selectPlace(coords[0], coords[1]);
                      }
                  });
                  map.events.add('mouseleave', function () {
                      if (longPressTimer) {
                          clearTimeout(longPressTimer);
                          longPressTimer = null;
                      }
                  });

                  if (navigator.geolocation) {
                      navigator.geolocation.getCurrentPosition(function(pos) {
                          userLat = pos.coords.latitude;
                          userLon = pos.coords.longitude;
                          setUserPlacemark(userLat, userLon);
                          updateCoords(userLat, userLon);
                          map.panTo([userLat, userLon], {duration: 500});
                      }, function() {
                          setUserPlacemark(initLat, initLon);
                          updateCoords(initLat, initLon);
                      });
                  } else {
                      setUserPlacemark(initLat, initLon);
                      updateCoords(initLat, initLon);
                  }
              }

              function setUserPlacemark(lat, lon) {
                  if (userPlacemark) {
                      map.geoObjects.remove(userPlacemark);
                  }
                  userPlacemark = new ymaps.Placemark([lat, lon], {
                      balloonContent: 'Моё местоположение',
                      hintContent: 'Моё местоположение'
                  }, {
                      preset: 'islands#blueCircleDotIcon',
                      draggable: false
                  });
                  map.geoObjects.add(userPlacemark);
              }

              function selectPlace(lat, lon) {
                  if (selectedPlacemark) {
                      map.geoObjects.remove(selectedPlacemark);
                  }
                  selectedPlacemark = new ymaps.Placemark([lat, lon], {
                      balloonContent: 'Выбранное место',
                      hintContent: 'Выбранное место'
                  }, {
                      preset: 'islands#redDotIcon',
                      draggable: true
                  });
                  selectedPlacemark.events.add('dragend', function() {
                      var coords = selectedPlacemark.geometry.getCoordinates();
                      updateCoords(coords[0], coords[1]);
                  });
                  map.geoObjects.add(selectedPlacemark);
                  updateCoords(lat, lon);
              }

              function updateCoords(lat, lon) {
                  document.getElementById('lat').textContent = lat.toFixed(6);
                  document.getElementById('lon').textContent = lon.toFixed(6);
                  window.ReactNativeWebView.postMessage(JSON.stringify({lat: lat, lon: lon}));
              }

              // Кнопка локации получает координаты из Flutter (канал geoChannel)
              var myLocBtnEl = document.getElementById('myLoc');
              function requestUserLocation() {
                  if (myLocBtnEl) myLocBtnEl.style.opacity = '0.5';
                  try {
                      window.geoChannel.postMessage('locate');
                  } catch (e) {
                      if (myLocBtnEl) myLocBtnEl.style.opacity = '1';
                  }
              }
              document.getElementById('myLoc').onclick = requestUserLocation;

              // Вызывается из Flutter после получения координат геолокации
              function moveToUser(lat, lon) {
                  userLat = lat;
                  userLon = lon;
                  if (selectedPlacemark) {
                      map.geoObjects.remove(selectedPlacemark);
                  }
                  selectedPlacemark = new ymaps.Placemark([lat, lon], {
                      balloonContent: 'Моё местоположение',
                      hintContent: 'Моё местоположение'
                  }, {
                      preset: 'islands#blueCircleDotIcon',
                      draggable: true
                  });
                  selectedPlacemark.events.add('dragend', function() {
                      var coords = selectedPlacemark.geometry.getCoordinates();
                      updateCoords(coords[0], coords[1]);
                  });
                  map.geoObjects.add(selectedPlacemark);
                  updateCoords(lat, lon);
                  if (map.getZoom() < 15) {
                      map.setZoom(15, {duration: 300});
                  }
                  map.panTo([lat, lon], {duration: 1000}).then(function() {
                      if (myLocBtnEl) myLocBtnEl.style.opacity = '1';
                  });
              }

              function locateError() {
                  if (myLocBtnEl) myLocBtnEl.style.opacity = '1';
              }
          </script>
      </body>
      </html>
    '''.replaceAll('INIT_LAT_PLACEHOLDER', widget.initialLat.toString())
       .replaceAll('INIT_LON_PLACEHOLDER', widget.initialLon.toString());

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('HunterApp/1.0')
      ..enableZoom(false)
      ..setBackgroundColor(isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(
        'geoChannel',
        onMessageReceived: (message) => _handleGeoChannel(message.message),
      )
      ..loadHtmlString(_html);
    _controllerInitialized = true;

    // Для Android - включаем touch-взаимодействие
    if (defaultTargetPlatform == TargetPlatform.android) {
      // WebView уже поддерживает touch по умолчанию
    }

    // Периодически запрашиваем координаты выбранного места
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_disposed) return; // Предотвращаем setState после dispose
      try {
        final result = await _controller.runJavaScriptReturningResult(
          '''
            (function() {
              if (window.selectedPlacemark) {
                var coords = window.selectedPlacemark.geometry.getCoordinates();
                return coords[0] + "," + coords[1];
              }
              return null;
            })();
          ''',
        );
        if (result.toString().contains(',')) {
          final coords = result.toString().replaceAll('"', '').split(',');
          if (coords.length == 2) {
            final newLat = double.tryParse(coords[0]);
            final newLon = double.tryParse(coords[1]);
            if (newLat != null && newLon != null) {
              if (_disposed) return;
              setState(() {
                _lat = newLat;
                _lon = newLon;
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _handleGeoChannel(String _) async {
    debugPrint('MAP: geoChannel received');
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      debugPrint(
          'MAP: got position lat=${pos.latitude} lon=${pos.longitude}');
      if (!_controllerInitialized || !mounted) return;
      await _controller.runJavaScript(
        'moveToUser(${pos.latitude}, ${pos.longitude}); true;',
      );
    } catch (e) {
      debugPrint('MAP: geolocation error: $e');
      if (_controllerInitialized && mounted) {
        await _controller.runJavaScript('locateError(); true;');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Тема карты задаётся при построении WebView; на resumed ничего
    // инвертировать заново не нужно, иначе двойная инверсия испортит вид.
    if (state == AppLifecycleState.resumed) {
      debugPrint('MAP: resumed');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор места'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 20, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Координаты: ${_lat.toStringAsFixed(6)}, ${_lon.toStringAsFixed(6)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_MapResult(_lat, _lon)),
                  icon: const Icon(Icons.check),
                  label: const Text('Сохранить'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Экран «Дневник» — учёт добычи и наблюдений.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  String _filter = 'все'; // все | добыто | наблюдение
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Следим и за тарифом, чтобы лимит записей обновлялся реактивно.
    context.watch<AuthProvider>();
    final diary = context.watch<DiaryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Дневник')),
      floatingActionButton: GestureDetector(
        onLongPress: _chooseResult,
        child: FloatingActionButton(
          onPressed: () => _openAdd(context),
          child: const Icon(Icons.add),
        ),
      ),
      body: !diary.loaded
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _DiarySummary(entries: diary.entries)),
                SliverToBoxAdapter(
                  child: _DiaryFilter(
                    selected: _filter,
                    query: _query,
                    searchController: _searchCtrl,
                    onFilterChanged: (v) => setState(() => _filter = v),
                    onQueryChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SliverToBoxAdapter(child: _buildGroupedList(diary)),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }

  Future<void> _openAdd(BuildContext context, {String? result}) async {
    final ok = await requireAuth(context);
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => _AddEntryScreen(initialResult: result)),
    );
  }

  /// Долгое нажатие на «+» — выбор Наблюдение/Добыто.
  Future<void> _chooseResult() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.remove_red_eye_outlined),
              title: const Text('Наблюдение'),
              onTap: () => Navigator.pop(ctx, 'наблюдение'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Добыто'),
              onTap: () => Navigator.pop(ctx, 'добыто'),
            ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    await _openAdd(context, result: v);
  }

  void _openDetail(BuildContext context, DiaryEntry e, VoidCallback onDelete) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EntryDetailScreen(entry: e, onDelete: onDelete),
      ),
    );
  }

  /// Список записей, сгруппированный по годам и месяцам с заголовками,
  /// с применением фильтра (все/добыто/наблюдение) и поиска.
  Widget _buildGroupedList(DiaryProvider diary) {
    var entries = diary.entries;
    if (_filter == 'добыто') {
      entries = entries.where((e) => e.result == 'добыто').toList();
    } else if (_filter == 'наблюдение') {
      entries = entries.where((e) => e.result != 'добыто').toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      entries = entries
          .where((e) =>
              e.species.toLowerCase().contains(q) ||
              (e.location?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (entries.isEmpty) {
      return _EmptyDiary(onAdd: () => _openAdd(context));
    }

    final sorted = List.of(entries)..sort((a, b) => b.date.compareTo(a.date));
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    // Группировка по дате (ГГГГ-ММ-ДД). Новые даты сверху.
    final groups = <String, List<DiaryEntry>>{};
    for (final e in sorted) {
      final key = '${e.date.year}-${e.date.month}-${e.date.day}';
      groups.putIfAbsent(key, () => []).add(e);
    }
    final items = <Widget>[];
    for (final entry in groups.entries) {
      final date = entry.value.first.date;
      items.add(_CollapsibleMonth(
        label: '${date.day} ${months[date.month]} ${date.year}',
        count: entry.value.length,
        child: Column(
          children: [
            for (final e in entry.value)
              Dismissible(
                key: ValueKey(e.id != null
                    ? 'local-${e.id}'
                    : (e.uuid ?? 'entry-${e.date.millisecondsSinceEpoch}')),
                direction: DismissDirection.horizontal,
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF43A047),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.edit_outlined, color: Colors.white),
                ),
                secondaryBackground: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Удалить запись?'),
                        content: const Text('Это действие нельзя отменить.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Отмена')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Удалить')),
                        ],
                      ),
                    );
                    if (confirmed == true) diary.deleteEntry(e.id!);
                    return confirmed ?? false;
                  }
                  _openDetail(context, e, () => diary.deleteEntry(e.id!));
                  return false;
                },
                child: _EntryCard(
                  entry: e,
                  onTap: () => _openDetail(context, e, () => diary.deleteEntry(e.id!)),
                ),
              ),
          ],
        ),
      ));
    }
    return Column(
      children: items,
    );
  }
}

/// Заголовок месяца в списке дневника.
class _CollapsibleMonth extends StatefulWidget {
  final String label;
  final int count;
  final Widget child;
  const _CollapsibleMonth({required this.label, required this.count, required this.child});

  @override
  State<_CollapsibleMonth> createState() => _CollapsibleMonthState();
}

class _CollapsibleMonthState extends State<_CollapsibleMonth> {
  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return '$n запись';
    if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return '$n записи';
    return '$n записей';
  }

  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _plural(widget.count),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _open ? widget.child : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Компактная сводка-статистика дневника.
class _DiarySummary extends StatelessWidget {
  final List<DiaryEntry> entries;
  const _DiarySummary({required this.entries});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = entries.length;
    final species = entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet().length;
    final hunted = entries.where((e) => e.result == 'добыто').length;

    return GlassCard(
      tint: scheme.primaryContainer.withValues(alpha: 0.4),
      radius: 16,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            _Stat(label: 'записей', value: '$total'),
            _Stat(label: 'видов', value: '$species'),
            _Stat(label: 'добыто', value: '$hunted'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary)),
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Панель фильтра дневника: сегмент «все/добыто/наблюдение» + поиск.
class _DiaryFilter extends StatelessWidget {
  final String selected;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  const _DiaryFilter({
    required this.selected,
    required this.query,
    required this.searchController,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'все', label: Text('Все')),
              ButtonSegment(value: 'добыто', label: Text('Добыто')),
              ButtonSegment(value: 'наблюдение', label: Text('Наблюдения')),
            ],
            selected: {selected},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            onSelectionChanged: (s) => onFilterChanged(s.first),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: searchController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Поиск по виду или месту…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onQueryChanged,
          ),
        ],
      ),
    );
  }
}

class _EmptyDiary extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyDiary({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Пока нет записей',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Заведите первую запись о добыче или наблюдении'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Добавить запись'),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = entry.photoPath != null && File(entry.photoPath!).existsSync();
    final isResult = entry.result == 'добыто';
    final accent = isResult ? scheme.primary : scheme.secondary;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Icon(isResult ? Icons.check_circle : Icons.remove_red_eye_outlined,
                    color: accent),
                const SizedBox(width: 8),
                Expanded(child: Text(_title(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                if (hasPhoto) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.photo_camera, size: 18, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Chip(icon: Icons.event, text: _dateLabel(), color: scheme.onSurfaceVariant),
                if (entry.location != null && entry.location!.isNotEmpty)
                  _Chip(icon: Icons.place_outlined, text: entry.location!, color: scheme.onSurfaceVariant),
                if (entry.weather != null && entry.weather!.isNotEmpty)
                  _Chip(icon: Icons.cloud_outlined, text: entry.weather!, color: scheme.onSurfaceVariant),
                if (entry.weight != null && entry.result == 'добыто')
                  _Chip(icon: Icons.monitor_weight_outlined, text: '${_fmtNum(entry.weight)} кг', color: scheme.onSurfaceVariant),
                if (entry.count != null && entry.count! > 1)
                  _Chip(icon: Icons.numbers, text: '×${entry.count}', color: scheme.onSurfaceVariant),
                if (entry.method != null && entry.method!.isNotEmpty)
                  _Chip(icon: Icons.gps_fixed_outlined, text: entry.method!, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          if (entry.notes != null && entry.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Text(
                entry.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }

  String _title() {
    final s = entry.species.isNotEmpty ? entry.species : 'Наблюдение';
    return s;
  }

  String _dateLabel() {
    const months = ['', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    final d = entry.date;
    return '${d.day} ${months[d.month]} ${d.year} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtNum(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Chip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

/// Экран добавления записи в дневник.
/// Детальный экран записи дневника: крупное фото, все поля, действия.
class _EntryDetailScreen extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onDelete;
  const _EntryDetailScreen({required this.entry, required this.onDelete});

  Future<void> _openMap(BuildContext context, double lat, double lon) async {
    if (!context.mounted) return;
    debugPrint('MAP: opening with lat=$lat lon=$lon');

    final items = <_MapAppItem>[];

    // Проверяем доступность приложений
    if (await _canOpenScheme('yandexnavi://')) {
      items.add(_MapAppItem(
        name: 'Яндекс Навигатор',
        icon: const Icon(Icons.directions_car, color: Color(0xFFFFCC00)),
        onTap: () => _launchScheme(
          'yandexnavi://?directions_mode=routes&to_name=Цель&to_lat=$lat&to_lon=$lon',
        ),
      ));
    }
    if (await _canOpenScheme('yandexmaps://')) {
      items.add(_MapAppItem(
        name: 'Яндекс Карты',
        icon: const Icon(Icons.map, color: Color(0xFFFFCC00)),
        onTap: () => _launchScheme(
          'yandexmaps://maps/?pt=${Uri.encodeComponent('$lon,$lat')}',
        ),
      ));
    }
    if (await _canOpenScheme('comgooglemaps://')) {
      items.add(_MapAppItem(
        name: 'Google Maps',
        icon: const Icon(Icons.map, color: Color(0xFF4285F4)),
        onTap: () => _launchScheme('comgooglemaps://?q=$lat,$lon'),
      ));
    }
    // Apple Maps / универсальные карты — всегда добавляем.
    // На iOS используем Apple Maps (maps://), на Android — Google Maps.
    final fallbackScheme = defaultTargetPlatform == TargetPlatform.iOS
        ? 'maps://?q=$lat,$lon'
        : 'https://www.google.com/maps?q=$lat,$lon';
    items.add(_MapAppItem(
      name: 'Карты',
      icon: const Icon(Icons.map_outlined, color: Color(0xFF34C759)),
      onTap: () => _launchScheme(fallbackScheme),
    ));

    if (!context.mounted) return;

    if (items.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Приложения для карт не найдены')),
        );
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: items.map((item) => ListTile(
            leading: item.icon,
            title: Text(item.name),
            onTap: () {
              if (ctx.mounted) Navigator.pop(ctx);
              item.onTap();
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<bool> _canOpenScheme(String scheme) async {
    try {
      final result = await canLaunchUrl(Uri.parse(scheme));
      debugPrint('MAP: canLaunchUrl($scheme) = $result');
      return result;
    } catch (_) {
      debugPrint('MAP: canLaunchUrl($scheme) = error');
      return false;
    }
  }

  Future<void> _launchScheme(String scheme) async {
    final uri = Uri.parse(scheme);
    debugPrint('MAP: launching $uri');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      debugPrint('MAP: launched=$launched');
      if (!launched) {
        debugPrint('MAP: failed to launch $scheme');
      }
    } catch (e) {
      debugPrint('MAP: error launching $scheme: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = entry.photoPath != null && File(entry.photoPath!).existsSync();
    final isResult = entry.result == 'добыто';
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final dateStr = '${entry.date.day} ${months[entry.date.month]} ${entry.date.year} • ${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Запись')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Детали всегда в maxWidth-обёртке (управляется ResponsivePage),
              // здесь просто широкий ListView.
              GlassCard(
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.species.isEmpty ? 'Наблюдение' : entry.species,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(icon: Icons.check_circle,
                          value: isResult ? 'добыто' : 'наблюдение',
                          color: isResult ? scheme.primary : scheme.secondary),
                      _DetailRow(icon: Icons.event, value: dateStr),
                      if (entry.location != null && entry.location!.isNotEmpty)
                        _DetailRow(icon: Icons.place_outlined, value: entry.location!),
                      if (entry.latitude != null && entry.longitude != null) ...[
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: () {
                            debugPrint('MAP INLINE: lat=${entry.latitude} lon=${entry.longitude}');
                            _openMap(context, entry.latitude!, entry.longitude!);
                          },
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Открыть карту'),
                        ),
                      ],
                      if (entry.weather != null && entry.weather!.isNotEmpty)
                        _DetailRow(icon: Icons.cloud_outlined, value: entry.weather!),
                      if (entry.weight != null && entry.result == 'добыто')
                        _DetailRow(icon: Icons.monitor_weight_outlined,
                            value: '${_EntryCard._fmtNum(entry.weight)} кг'),
                      if (entry.count != null && entry.count! > 1)
                        _DetailRow(icon: Icons.numbers, value: '×${entry.count}'),
                      if (entry.method != null && entry.method!.isNotEmpty)
                        _DetailRow(icon: Icons.gps_fixed_outlined, value: entry.method!),
                    ],
                  ),
                ),
              ),
              if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                GlassCard(
                  radius: 16,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Заметки',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(entry.notes!, style: const TextStyle(height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ],
              if (hasPhoto) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(File(entry.photoPath!),
                      height: wide ? 320 : 260, width: double.infinity, fit: BoxFit.cover),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _AddEntryScreen(initial: entry),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Изменить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Удалить запись?'),
                            content: const Text('Это действие нельзя отменить.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Отмена')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Удалить')),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          onDelete();
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Строка с иконкой и значением в деталях записи.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _DetailRow({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _AddEntryScreen extends StatefulWidget {
  final DiaryEntry? initial;
  final String? initialResult;
  const _AddEntryScreen({this.initial, this.initialResult});

  @override
  State<_AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<_AddEntryScreen> {
  final _form = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _speciesCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _weatherCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _result = 'наблюдение'; // добыто / увидено
  final _weightCtrl = TextEditingController();
  final _countCtrl = TextEditingController();
  final _methodCtrl = TextEditingController();
  String? _photoPath;
  double? _latitude;
  double? _longitude;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialResult != null) _result = widget.initialResult!;
    final i = widget.initial;
    if (i != null) {
      _date = i.date;
      _speciesCtrl.text = i.species;
      _locationCtrl.text = i.location ?? '';
      _weatherCtrl.text = i.weather ?? '';
      _notesCtrl.text = i.notes ?? '';
      _result = i.result.isEmpty ? 'наблюдение' : i.result;
      _photoPath = i.photoPath;
      _latitude = i.latitude;
      _longitude = i.longitude;
      _weightCtrl.text = i.weight?.toString() ?? '';
      _countCtrl.text = i.count?.toString() ?? '';
      _methodCtrl.text = i.method ?? '';
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _countCtrl.dispose();
    _methodCtrl.dispose();
    _speciesCtrl.dispose();
    _locationCtrl.dispose();
    _weatherCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _date.hour,
            _date.minute,
          ));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
            _date.year,
            _date.month,
            _date.day,
            picked.hour,
            picked.minute,
          ));
    }
  }

  void _save() async {
    if (!_form.currentState!.validate()) return;
    final diary = context.read<DiaryProvider>();
    final entry = DiaryEntry(
      id: widget.initial?.id,
      uuid: widget.initial?.uuid,
      date: _date,
      species: _speciesCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      weather: _weatherCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      photoPath: _photoPath,
      latitude: _latitude,
      longitude: _longitude,
      result: _result,
      weight: double.tryParse(_weightCtrl.text.trim().replaceAll(',', '.')),
      count: int.tryParse(_countCtrl.text.trim()),
      method: _methodCtrl.text.trim().isEmpty ? null : _methodCtrl.text.trim(),
    );
    if (widget.initial != null) {
      await diary.updateEntry(entry);
    } else {
      await diary.addEntry(entry);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1200);
    if (picked != null) setState(() => _photoPath = picked.path);
  }

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Служба геолокации выключена')),
        );
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к геолокации')),
        );
      }
      return;
    }
    double? lat = _latitude;
    double? lon = _longitude;
    // Быстро подхватываем последнюю известную позицию (мгновенно, из кеша).
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        lat = last.latitude;
        lon = last.longitude;
      }
    } catch (_) {}

    if (mounted && lat != null && lon != null) {
      setState(() {
        _latitude = lat;
        _longitude = lon;
      });
    }
    if (!mounted) return;
    // Карта открывается сразу; точную позицию можно получить кнопкой 📍 на карте.
    await _showMapChoice(
      context,
      lat ?? _defaultLat,
      lon ?? _defaultLon,
    );
  }

  static const double _defaultLat = 55.7558;
  static const double _defaultLon = 37.6173;

  /// Открывает экран карты для выбора/корректировки координат.
  Future<void> _showMapChoice(BuildContext context, double lat, double lon) async {
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<_MapResult>(
      MaterialPageRoute(
        builder: (_) => _MapPickerScreen(
          initialLat: lat,
          initialLon: lon,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _latitude = result.lat;
        _longitude = result.lon;
      });
    }
  }

  Future<void> _showPhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Изменить запись' : 'Новая запись')),
      body: Form(
        key: _form,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: wide
                  ? _buildWideForm(context, scheme, editing)
                  : _buildNarrowForm(context, scheme, editing),
            );
          },
        ),
      ),
    );
  }

  /// Широкий (планшет/десктоп): «Что» и «Где» в две колонки, фото+кнопка внизу.
  List<Widget> _buildWideForm(BuildContext context, ColorScheme scheme, bool editing) {
    return [
      // Дата и Результат — ряд.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _resultCard(context, scheme)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _dateCard(context, scheme)),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _whatCard(context, scheme, editing)),
          const SizedBox(width: 12),
          Expanded(child: _whereCard(context, scheme)),
        ],
      ),
      const SizedBox(height: 12),
      _extrasCards(context, scheme),
      const SizedBox(height: 12),
      _photoAndSave(context, scheme),
    ];
  }

  /// Узкий (телефон): вертикальная последовательность как раньше.
  List<Widget> _buildNarrowForm(BuildContext context, ColorScheme scheme, bool editing) {
    return [
      _resultCard(context, scheme),
      _dateCard(context, scheme),
      _whatCard(context, scheme, editing),
      _whereCard(context, scheme),
      _extrasCards(context, scheme),
      _photoAndSave(context, scheme),
    ];
  }

  Widget _resultCard(BuildContext context, ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Результат',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'наблюдение', label: Text('Наблюдение')),
                ButtonSegment(value: 'добыто', label: Text('Добыто')),
              ],
              selected: {_result},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _result = s.first),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateCard(BuildContext context, ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            final dateChip = InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatDate(_date), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            );
            final timeChip = InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(_formatTime(_date), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            );
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text('Дата и время', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: dateChip),
                      Container(width: 1, height: 24, color: scheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
                      Expanded(child: timeChip),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Icon(Icons.event, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Дата и время', style: TextStyle(color: scheme.onSurfaceVariant)),
                const Spacer(),
                dateChip,
                Container(width: 1, height: 24, color: scheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
                timeChip,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _whatCard(BuildContext context, ColorScheme scheme, bool editing) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, 'Что'),
            _field(_speciesCtrl, scheme,
                label: 'Вид (лось, кабан, утка…)',
                maxLength: 50,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Укажите вид' : null),
          ],
        ),
      ),
    );
  }

  Widget _whereCard(BuildContext context, ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, 'Где'),
            _field(_locationCtrl, scheme, label: 'Место', maxLength: 50),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _getLocation,
              icon: const Icon(Icons.my_location),
              label: _latitude != null
                  ? const Text('Метка ✓')
                  : const Text('Гео'),
            ),
            if (_result == 'добыто') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _field(_weightCtrl, scheme,
                        label: 'Вес, кг',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_WeightFormatter(maxDigits: 3)]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(_countCtrl, scheme,
                        label: 'Кол-во',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(_methodCtrl, scheme, label: 'Способ охоты', maxLength: 50),
            ],
          ],
        ),
      ),
    );
  }

  Widget _extrasCards(BuildContext context, ColorScheme scheme) {
    return _CollapsibleFormSection(
      title: 'Дополнительно',
      child: GlassCard(
        radius: 16,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_weatherCtrl, scheme, label: 'Погода', maxLength: 50),
              const SizedBox(height: 8),
              _field(_notesCtrl, scheme,
                  label: 'Заметки',
                  maxLines: 3,
                  maxLength: 200),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoAndSave(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _showPhotoSource,
          icon: const Icon(Icons.photo_camera_outlined),
          label: _photoPath == null ? const Text('Добавить фото') : const Text('Фото ✓'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _save,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Сохранить'),
          ),
        ),
      ],
    );
  }

  static Widget _sectionTitle(ColorScheme scheme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style:
              TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
    );
  }

  static Widget _field(TextEditingController c, ColorScheme scheme,
      {required String label,
      int maxLines = 1,
      int? maxLength,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: scheme.onSurface),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        filled: true,
        // Как у инпута «Поиск по виду или месту» — адаптивный серый фон.
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  static String _formatTime(DateTime d) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Форматтер веса: максимум [maxDigits] целых цифр, опционально запятая/точка
/// и до 2 знаков после (например «123,45»). Принимает и запятую, и точку.
class _WeightFormatter extends TextInputFormatter {
  final int maxDigits;
  const _WeightFormatter({this.maxDigits = 3});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(',', '.');
    // Разрешаем: до maxDigits цифр целых + (опц.) разделитель + до 2 дробных.
    final allowed = RegExp('^(\\d{0,$maxDigits})(\\.\\d{0,2})?')
        .firstMatch(text)
        ?.group(0) ??
        '';
    // Если ввод был отклонён — не обнуляем поле, а оставляем предыдущее значение.
    // Это предотвращает молчаую потерю данных при вводе недопустимого символа.
    if (allowed.isEmpty && oldValue.text.isNotEmpty) {
      return oldValue;
    }
    // Возвращаем как введено, но с пониманием точки.
    final out = allowed.replaceAll('.', ',');
    if (newValue.text == out) return newValue;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// Сворачиваемый раздел формы (по умолчанию закрыт).
class _CollapsibleFormSection extends StatefulWidget {
  final String title;
  final Widget child;
  const _CollapsibleFormSection({required this.title, required this.child});

  @override
  State<_CollapsibleFormSection> createState() => _CollapsibleFormSectionState();
}

class _CollapsibleFormSectionState extends State<_CollapsibleFormSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Text(widget.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _open ? widget.child : const SizedBox.shrink(),
        ),
      ],
    );
  }
}