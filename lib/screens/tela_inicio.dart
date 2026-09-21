import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../context/app_state.dart';
import 'tela_turmas.dart';
import 'tela_configuracoes.dart';
import 'cadastro_avaliacao_screen.dart';
import 'tela_lista_avaliacoes.dart'; // <-- Import da nova tela

class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key});

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.carregarTurmas();
      appState.carregarTiposAvaliacao();
      appState.carregarAvaliacoes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'OMR Sistema 2.0',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 26),
            tooltip: "Configurações",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TelaConfiguracoes(),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card de Boas-vindas
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.indigo.shade100,
                      child: const Icon(
                        Icons.school,
                        size: 40,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Olá, ${appState.nomeProfessor}!',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appState.nomeEscola,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Card de Contexto Pedagógico
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
                        Icon(Icons.filter_list, color: Colors.indigo, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Contexto Pedagógico',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    const Text(
                      'Disciplina:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: appState.disciplinaAtual,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: appState.listaDisciplinas.map((disc) {
                        return DropdownMenuItem(value: disc, child: Text(disc));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) appState.setDisciplina(value);
                      },
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Ano / Série:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: appState.anoSerieAtual,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '6º Ano',
                          child: Text('6º Ano'),
                        ),
                        DropdownMenuItem(
                          value: '7º Ano',
                          child: Text('7º Ano'),
                        ),
                        DropdownMenuItem(
                          value: '8º Ano',
                          child: Text('8º Ano'),
                        ),
                        DropdownMenuItem(
                          value: '9º Ano',
                          child: Text('9º Ano'),
                        ),
                        DropdownMenuItem(
                          value: '1º Ano EM',
                          child: Text('1º Ano EM'),
                        ),
                        DropdownMenuItem(
                          value: '2º Ano EM',
                          child: Text('2º Ano EM'),
                        ),
                        DropdownMenuItem(
                          value: '3º Ano EM',
                          child: Text('3º Ano EM'),
                        ),
                      ].toList(),
                      onChanged: (value) {
                        if (value != null) appState.setAnoSerie(value);
                      },
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Bimestre:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: appState.bimestreAtual,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '1º Bimestre',
                          child: Text('1º Bimestre'),
                        ),
                        DropdownMenuItem(
                          value: '2º Bimestre',
                          child: Text('2º Bimestre'),
                        ),
                        DropdownMenuItem(
                          value: '3º Bimestre',
                          child: Text('3º Bimestre'),
                        ),
                        DropdownMenuItem(
                          value: '4º Bimestre',
                          child: Text('4º Bimestre'),
                        ),
                      ].toList(),
                      onChanged: (value) {
                        if (value != null) appState.setBimestre(value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Botões de Ação Principal
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TelaTurmas()),
              ),
              icon: const Icon(Icons.class_, size: 24),
              label: const Text(
                'ABRIR DIÁRIO DE CLASSE (TURMAS)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),

            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CadastroAvaliacaoScreen(),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline, size: 24),
              label: const Text(
                'CADASTRAR NOVA AVALIAÇÃO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 🚨 NOVO BOTÃO: GERENCIAR GABARITOS
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TelaListaAvaliacoes(),
                ),
              ),
              icon: const Icon(Icons.assignment_turned_in, size: 24),
              label: const Text(
                'GERENCIAR GABARITOS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo,
                side: const BorderSide(color: Colors.indigo, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
