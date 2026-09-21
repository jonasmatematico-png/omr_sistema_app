import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../context/app_state.dart';

class TelaConfiguracoes extends StatefulWidget {
  const TelaConfiguracoes({super.key});

  @override
  State<TelaConfiguracoes> createState() => _TelaConfiguracoesState();
}

class _TelaConfiguracoesState extends State<TelaConfiguracoes> {
  final _nomeController = TextEditingController();
  final _escolaController = TextEditingController();
  final _ipController =
      TextEditingController(); // 🚨 NOVO: Controller para o IP

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      _nomeController.text = appState.nomeProfessor;
      _escolaController.text = appState.nomeEscola;
      _ipController.text = appState.ipServidor; // 🚨 NOVO: Carrega o IP atual
    });
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _escolaController.dispose();
    _ipController.dispose(); // 🚨 NOVO: Limpa a memória do controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Configurações',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        // 🚨 Adicionado para não estourar a tela em celulares pequenos
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // CARD 1: DADOS PESSOAIS
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'Dados do Professor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    TextField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Professor',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _escolaController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Escola',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.school),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // CARD 2: CONEXÃO COM O SERVIDOR (NOVO!)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wifi_tethering, color: Colors.teal),
                        SizedBox(width: 8),
                        Text(
                          'Conexão com o Servidor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Endereço IP do computador onde o Python (app.py) está rodando. Altere aqui se mudar de rede Wi-Fi.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'IP do Servidor',
                        hintText: 'Ex: 192.168.3.20',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.computer),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // BOTÃO DE SALVAR TUDO
            ElevatedButton.icon(
              onPressed: () async {
                // 1. Salva Nome e Escola
                await appState.salvarConfiguracoes(
                  nomeProfessor: _nomeController.text,
                  nomeEscola: _escolaController.text,
                );

                // 2. Salva o IP (que já atualiza o SupabaseService automaticamente)
                await appState.salvarIpServidor(_ipController.text);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '✅ Todas as configurações foram salvas com sucesso!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.save, size: 24),
              label: const Text(
                'SALVAR TODAS AS CONFIGURAÇÕES',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
