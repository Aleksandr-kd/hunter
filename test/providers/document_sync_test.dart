import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/document.dart';
import 'package:pomoshchnik_okhotnika/providers/document_provider.dart';

void main() {
  group('DocumentProvider.remoteIdsToDelete (P1-2 tombstone)', () {
    Document doc(String title, {String? supabaseId}) =>
        Document(title: title, supabaseId: supabaseId);

    Map<String, dynamic> remote(String id, String title) =>
        {'id': id, 'title': title};

    test('не удаляет документ, всё ещё существующий локально', () {
      final local = [doc('Охотничий билет', supabaseId: 's1')];
      final remoteDocs = [remote('s1', 'Охотничий билет')];
      // Даже если s1 в tombstone, но локально запись ещё есть — не удаляем.
      expect(
        DocumentProvider.remoteIdsToDelete(local, remoteDocs, {'s1'}),
        isEmpty,
      );
    });

    test('удаляет серверную запись, помеченную tombstone и отсутствующую '
        'локально (явное удаление пользователем)', () {
      // Пользователь удалил документ 'Охотничий билет' (id s1) на этом
      // устройстве: tombstone содержит s1, локально его нет.
      final local = [doc('Договор / путёвка охотхозяйства', supabaseId: 's2')];
      final remoteDocs = [
        remote('s1', 'Охотничий билет'),
        remote('s2', 'Договор / путёвка охотхозяйства'),
      ];
      expect(DocumentProvider.remoteIdsToDelete(local, remoteDocs, {'s1'}),
          ['s1']);
    });

    test('НЕ удаляет документ, добавленный на другом устройстве с тем же '
        'title, если он НЕ помечен tombstone этим устройством (регрессия '
        'P1-2)', () {
      // На другом устройстве добавлен документ 'Разрешение на добычу' (id s9).
      // Локально его title отсутствует и tombstone его НЕ содержит — значит
      // это чужой/новый документ, удалять НЕЛЬЗЯ.
      final local = [doc('Охотничий билет', supabaseId: 's1')];
      final remoteDocs = [
        remote('s1', 'Охотничий билет'),
        remote('s9', 'Разрешение на добычу (текущий сезон)'),
      ];
      // tombstone пуст — ничего на удаление из этого набора.
      expect(DocumentProvider.remoteIdsToDelete(local, remoteDocs, {}), isEmpty);
      // даже если tombstone содержит ДРУГОЙ id (s3), s9 не трогаем.
      expect(DocumentProvider.remoteIdsToDelete(local, remoteDocs, {'s3'}),
          isEmpty);
    });

    test('без tombstone не удаляет даже отсутствующий локально документ '
        '(страховка от авто-удаления чужих записей)', () {
      final local = [doc('Охотничий билет', supabaseId: 's1')];
      final remoteDocs = [
        remote('s1', 'Охотничий билет'),
        remote('s2', 'Разрешение на оружие (РСОА)'),
      ];
      expect(DocumentProvider.remoteIdsToDelete(local, remoteDocs, {}), isEmpty);
    });

    test('пропускает серверные записи с null id', () {
      final local = <Document>[];
      final remoteDocs = [
        {'id': null, 'title': 'X'},
      ];
      expect(DocumentProvider.remoteIdsToDelete(local, remoteDocs, {'s1'}),
          isEmpty);
    });

    test('пустой серверный список — нечего удалять', () {
      final local = [doc('Охотничий билет', supabaseId: 's1')];
      expect(DocumentProvider.remoteIdsToDelete(local, [], {'s1'}), isEmpty);
    });

    test('tombstone id, которого нет на сервере — не влияет на результат '
        '(запись уже удалена)', () {
      final local = [doc('Охотничий билет', supabaseId: 's1')];
      final remoteDocs = [remote('s1', 'Охотничий билет')];
      // s99 в tombstone, но на сервере его нет.
      expect(
        DocumentProvider.remoteIdsToDelete(local, remoteDocs, {'s99'}),
        isEmpty,
      );
    });
  });
}
