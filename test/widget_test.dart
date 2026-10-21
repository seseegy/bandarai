import 'package:flutter_test/flutter_test.dart';
import 'package:bandarai/main.dart';

void main() {
  testWidgets('App renders root shell', (tester) async {
    await tester.pumpWidget(const BandarAiApp());
    expect(find.text('BandarAI'), findsWidgets);
  });
}
