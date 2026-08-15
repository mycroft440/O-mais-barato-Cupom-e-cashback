import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_mais_barato/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('abre a tela de ofertas personalizada', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaisBaratoApp());
    await tester.pumpAndSettle();

    expect(find.text('Ofertas para você'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsWidgets);
    expect(find.text('Quero comprar'), findsOneWidget);
  });
}
