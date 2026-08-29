import 'package:flutter/material.dart';

import '../widgets/glass_card.dart';

/// Экран «Информация»: как приложение хранит, загружает и
/// синхронизирует фотографии и другие данные пользователя.
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Информация')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _H(text: 'Фотографии в дневнике'),
                  const SizedBox(height: 4),
                  const _Sub(text: 'Формат и размер'),
                  const SizedBox(height: 8),
                  const _P(text:
                      'При добавлении фотографии приложение приводит её к '
                      'ширине до 1200 пикселей (высота меняется пропорционально, '
                      'без обрезки). Итоговый файл сохраняется в формате JPEG и '
                      'обычно весит от 100 до 400 КБ. Изображения с прозрачностью '
                      'сохраняются как PNG.'),
                  const _Sub(text: 'Где хранится оригинал'),
                  const SizedBox(height: 8),
                  const _P(text:
                      'Оригинальный снимок с камеры не сохраняется — и на '
                      'устройстве, и в аккаунте лежит только уменьшенная версия. '
                      'На устройстве файл находится во внутренней папке '
                      'приложения, в аккаунте — в защищённом облачном хранилище '
                      '(раздел «diary-photos»). В базе данных хранится только '
                      'ссылка на файл, а не само изображение.'),
                  const _Sub(text: 'Загрузка и выгрузка'),
                  const SizedBox(height: 8),
                  const _P(text:
                      'Фотографии передаются без перекодирования: загружается '
                      'файл в том виде, в котором он лежит на устройстве, и '
                      'скачивается обратно по байтам без изменения формата. '
                      'Чтобы просмотреть фото на другом устройстве, достаточно '
                      'войти в тот же аккаунт — приложение восстановит записи и '
                      'фотографии автоматически.'),
                  _H(text: 'Данные дневника', scheme: scheme),
                  const SizedBox(height: 8),
                  const _P(text:
                      'Записи (вид животного, дата, результат, вес, количество, '
                      'способ добычи, текстовые заметки и координаты места) '
                      'хранятся локально на устройстве в базе SQLite и '
                      'синхронизируются в аккаунт после входа. Геолокация '
                      'запрашивается только при создании записи и только с '
                      'разрешения пользователя.'),
                  _H(text: 'Документы охотника', scheme: scheme),
                  const SizedBox(height: 8),
                  const _P(text:
                      'Тип документа, его номер и срок действия синхронизируются '
                      'в аккаунт. Это нужно, чтобы сформировать напоминания об '
                      'истечении срока действия охотничьего билета и разрешений '
                      'и показать их сразу после входа.'),
                  _H(text: 'Настройки и регионы', scheme: scheme),
                  const SizedBox(height: 8),
                  const _P(text:
                      'Выбранные регионы охоты, тема оформления и параметры '
                      'уведомлений хранятся на устройстве; часть настроек '
                      'синхронизируется в аккаунт для единообразия на разных '
                      'устройствах.'),
                  _H(text: 'Безопасность', scheme: scheme),
                  const SizedBox(height: 8),
                  const _P(text:
                      'Фотографии, записи и документы видны только владельцу '
                      'аккаунта: доступ разграничивается на сервере, передача '
                      'идёт по защищённому соединению (HTTPS). Без входа в '
                      'аккаунт данные остаются только на устройстве и в облако '
                      'не передаются. Удаление записи или фотографии в '
                      'приложении синхронизируется на сервер.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заголовок секции.
class _H extends StatelessWidget {
  final String text;
  final ColorScheme? scheme;

  const _H({required this.text, this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = scheme?.primary ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          height: 1.3,
          color: color,
        ),
      ),
    );
  }
}

/// Подзаголовок.
class _Sub extends StatelessWidget {
  final String text;

  const _Sub({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
    );
  }
}

/// Абзац.
class _P extends StatelessWidget {
  final String text;

  const _P({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(height: 1.4)),
    );
  }
}