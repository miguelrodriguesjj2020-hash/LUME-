import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lume/main.dart';

Future<void> waitFor(WidgetTester tester,Finder finder,{int seconds=20}) async{
  for(var i=0;i<seconds*4;i++){
    await tester.pump(const Duration(milliseconds:250));
    if(finder.evaluate().isNotEmpty)return;
  }
  throw TestFailure('Timed out waiting for ${finder.description}');
}

void main(){
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('student can login, discover catalog and read CBZ',(tester) async{
    await tester.pumpWidget(LumeBootstrap(apiBase:Uri.parse('http://10.0.2.2:18787')));
    await waitFor(tester,find.text('Entrar'));
    expect(find.text('LUME'),findsOneWidget);

    final fields=find.byType(TextField);
    expect(fields,findsNWidgets(2));
    await tester.enterText(fields.at(0),'aluno');
    await tester.enterText(fields.at(1),'senha-errada');
    await tester.tap(find.text('Entrar'));
    await waitFor(tester,find.text('Não foi possível entrar. Verifique suas credenciais.'));

    await tester.enterText(fields.at(1),'lume2026');
    await tester.tap(find.text('Entrar'));
    await waitFor(tester,find.text('Livros'));
    await waitFor(tester,find.text('Clássico da Jornada'));
    expect(find.text('HQs'),findsOneWidget);
    expect(find.text('Mangás'),findsOneWidget);
    expect(find.text('Grandes Clássicos'),findsWidgets);
    expect(find.text('Essenciais'),findsWidgets);

    await tester.tap(find.text('HQs'));
    await waitFor(tester,find.text('HQ Jornada'));
    expect(find.text('Recomendações'),findsWidgets);
    expect(find.text('Melhores escritos'),findsWidgets);

    await tester.tap(find.text('HQ Jornada').first);
    await waitFor(tester,find.text('hq-jornada.cbz'));
    expect(find.text('CBZ · pt-BR'),findsOneWidget);
    await tester.tap(find.text('hq-jornada.cbz'));
    await waitFor(tester,find.text('Página 1 de 3'),seconds:30);

    final pageView=find.byType(PageView);
    expect(pageView,findsOneWidget);
    await tester.drag(pageView,const Offset(-500,0));
    await waitFor(tester,find.text('Página 2 de 3'));
    await tester.pump(const Duration(seconds:2));
    await tester.pageBack();
    await waitFor(tester,find.text('HQ Jornada'));
  });
}
