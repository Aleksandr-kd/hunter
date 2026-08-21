import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/app.dart';

void main() {
  testWidgets('App builds and shows main shell', (WidgetTester tester) async {
    await tester.pumpWidget(const HunterAppRoot());
    await tester.pumpAndSettle();

    // В нижней навигации присутствуют ключевые разделы.
    expect(find.text('Сезоны'), findsOneWidget);
    expect(find.text('Дневник'), findsOneWidget);
    expect(find.text('Регионы'), findsOneWidget);
  });
}