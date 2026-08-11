import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../context/app_state.dart';
import '../models/turma_model.dart';
import 'tela_alunos.dart';

class TelaTurmas extends StatefulWidget {
  const TelaTurmas({super.key});

  @override
  State<TelaTurmas> createState() => _TelaTurmasState();
}

class _TelaTurmasState extends State<TelaTurmas> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).carregarTurmas();
    });
  }

  List<Turma> _filtrarTurmasPorAno(
    List<Turma> todasTurmas,
    String anoSerieAtual,
  ) {
    if (todasTurmas.isEmpty) return [];

    String digitoAno = "";
    if (anoSerieAtual.contains("6"))
      digitoAno = "6";
    else if (anoSerieAtual.contains("7"))
      digitoAno = "7";
    else if (anoSerieAtual.contains("8"))
      digitoAno = "8";
    else if (anoSerieAtual.contains("9"))
      digitoAno = "9";
    else if (anoSerieAtual.contains("1º") || anoSerieAtual.contains("1°"))
      digitoAno = "1";
    else if (anoSerieAtual.contains("2º") || anoSerieAtual.contains("2°"))
      digitoAno = "2";
    else if (anoSerieAtual.contains("3º") || anoSerieAtual.contains("3°"))
      digitoAno = "3";

    return todasTurmas
        .where((turma) => turma.anoSerie.contains(digitoAno))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final turmasFiltradas = _filtrarTurmasPorAno(
      appState.turmas,
      appState.anoSerieAtual,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Turmas - ${appState.anoSerieAtual}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 26),
            tooltip: "Recarregar",
            onPressed: () => appState.carregarTurmas(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: appState.servidorOnline
                  ? Colors.indigo.shade50
                  : Colors.orange.shade50,
              border: Border(
                bottom: BorderSide(
                  color: appState.servidorOnline
                      ? Colors.indigo.shade200
                      : Colors.orange.shade300,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  appState.servidorOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: appState.servidorOnline
                      ? Colors.indigo
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appState.servidorOnline
                        ? "Conectado ao Supabase • ${appState.anoSerieAtual}"
                        : "⚠️ Modo Offline",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: appState.servidorOnline
                          ? Colors.indigo
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: appState.carregandoDados
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.indigo),
                        SizedBox(height: 16),
                        Text(
                          "Carregando turmas...",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  )
                : turmasFiltradas.isEmpty
                ? const Center(
                    child: Text(
                      "Nenhuma turma encontrada.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: turmasFiltradas.length,
                    itemBuilder: (context, index) {
                      final turma = turmasFiltradas[index];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.indigo.shade100,
                                    child: const Icon(
                                      Icons.school,
                                      color: Colors.indigo,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          turma.nome,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${appState.disciplinaAtual} • Dados da Nuvem",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  // 🚨 NAVEGAÇÃO IMEDIATA (sem await)
                                  onPressed: () {
                                    appState.setTurmaSelecionada(turma);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const TelaAlunos(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.fact_check_outlined),
                                  label: const Text(
                                    "ABRIR TURMA E DIÁRIO DE CLASSE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
