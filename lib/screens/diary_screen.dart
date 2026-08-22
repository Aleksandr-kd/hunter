import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import 'auth_gate.dart';

/// Экран «Дневник» — учёт добычи и наблюдений.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Следим и за тарифом, чтобы лимит записей обновлялся реактивно.
    context.watch<AuthProvider>();
    final diary = context.watch<DiaryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Дневник')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ok = await requireAuth(context);
          if (!ok || !context.mounted) return;
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const _AddEntryScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: !diary.loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (diary.freeRemaining >= 0) _FreeLimitBanner(diary: diary),
                Expanded(
                  child: diary.entries.isEmpty
                      ? _EmptyDiary()
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: diary.entries.length,
                          itemBuilder: (context, i) {
                            final e = diary.entries[i];
                            return _EntryCard(entry: e, onDelete: () {
                              diary.deleteEntry(e.id!);
                            });
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// Баннер с остатком записей для бесплатной версии.
class _FreeLimitBanner extends StatelessWidget {
  final DiaryProvider diary;

  const _FreeLimitBanner({required this.diary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = diary.freeRemaining;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                left <= 0
                    ? 'Лимит 10 записей исчерпан. Оформите подписку.'
                    : 'Бесплатная версия: осталось записей $left из 10.',
                style: TextStyle(
                    color: scheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDiary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Пока нет записей'),
          const SizedBox(height: 8),
          const Text('Нажмите +, чтобы добавить наблюдение'),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onDelete;

  const _EntryCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = entry.photoPath != null && File(entry.photoPath!).existsSync();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: const Icon(Icons.pets, size: 22),
            ),
            title: Text(_title()),
            subtitle: Text(_subtitle()),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ),
          if (hasPhoto)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: Image.file(
                File(entry.photoPath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }

  String _title() {
    final s = entry.species.isNotEmpty ? entry.species : 'Наблюдение';
    final place = entry.location != null ? ' · ${entry.location}' : '';
    return '$s$place';
  }

  String _subtitle() {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    final d = entry.date;
    final date = '${d.day} ${months[d.month]} ${d.year}';
    final notes = entry.notes != null && entry.notes!.isNotEmpty
        ? '\n${entry.notes}'
        : '';
    return '$date$notes';
  }
}

/// Экран добавления записи в дневник.
class _AddEntryScreen extends StatefulWidget {
  const _AddEntryScreen();

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
  String? _photoPath;
  double? _latitude;
  double? _longitude;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
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
    if (picked != null) setState(() => _date = picked);
  }

  void _save() async {
    if (!_form.currentState!.validate()) return;
    final diary = context.read<DiaryProvider>();
    final ok = await diary.addEntry(
      DiaryEntry(
        date: _date,
        species: _speciesCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        weather: _weatherCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        photoPath: _photoPath,
        latitude: _latitude,
        longitude: _longitude,
      ),
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Достигнут лимит 10 записей. Оформите подписку.'),
          ),
        );
      }
      return;
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
    final pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Новая запись')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Дата: ${_formatDate(_date)}'),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'наблюдение', label: Text('Наблюдение')),
                ButtonSegment(value: 'добыто', label: Text('Добыто')),
              ],
              selected: {_result},
              onSelectionChanged: (s) => setState(() => _result = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _speciesCtrl,
              decoration: const InputDecoration(
                labelText: 'Вид (лось, кабан, утка…)',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Укажите вид' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Место',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weatherCtrl,
              decoration: const InputDecoration(
                labelText: 'Погода',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Заметки',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showPhotoSource,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: _photoPath == null
                        ? const Text('Фото')
                        : const Text('Фото ✓'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _getLocation,
                    icon: const Icon(Icons.my_location),
                    label: _latitude != null
                        ? const Text('Метка ✓')
                        : const Text('Гео'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Сохранить'),
              ),
            ),
          ],
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
}