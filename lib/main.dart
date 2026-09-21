import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'context/app_state.dart';
import 'screens/tela_inicio.dart'; // ⚠️ Se sua tela inicial tiver outro nome, troque aqui
import 'screens/tela_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print("⏳ [Main] Inicializando Supabase...");
    await Supabase.initialize(
      url: 'https://mkqnaiuplkqiitwxltli.supabase.co',
      anonKey: 'sb_publishable_r-Tqilnqa8Q6iDURFV14rQ_W2wFuZoK',
    );

    print("⏳ [Main] Criando AppState e carregando IP...");
    final appState = AppState();
    await appState.carregarConfiguracoes();

    print("✅ [Main] Tudo pronto! Iniciando o App...");

    runApp(ChangeNotifierProvider.value(value: appState, child: const MyApp()));
  } catch (e, stackTrace) {
    print("🚨🚨🚨 [Main] ERRO CRÍTICO AO INICIAR: $e");
    print(stackTrace);

    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red.shade50,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                "Erro ao iniciar:\n\n$e",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign
                    .center, // 🚨 CORRIGIDO: Agora está DENTRO do widget Text
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMR Sistema 2.0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home:
          const TelaInicio(), // ⚠️ Confirme se este é o nome da sua tela inicial
    );
  }
}
