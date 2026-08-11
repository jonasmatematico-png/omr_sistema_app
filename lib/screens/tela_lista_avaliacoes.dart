import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Para formatar a data
import '../context/app_state.dart';
import 'tela_editar_gabarito.dart';

class TelaListaAvaliacoes extends StatefulWidget {
  const TelaListaAvaliacoes({super.key});

  @override
  State<TelaListaAvaliacoes> createState() => _TelaListaAvaliacoesState();
}

class _TelaListaAvaliacoesState extends State<TelaListaAvaliacoes> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).carregarAvaliacoes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final avaliacoes = appState.avaliacoes;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Minhas Avaliações',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => appState.carregarAvaliacoes(),
          ),
        ],
      ),
      body: avaliacoes.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Nenhuma avaliação cadastrada ainda.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Use o botão "+" na tela inicial para criar uma nova!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: avaliacoes.length,
              itemBuilder: (context, index) {
                final aval = avaliacoes[index];
                final temGabarito = aval.gabaritoCompleto;

                // Formata a data para ficar bonitinha (ex: 21/07/2026)
                String dataFormatada = 'Data não informada';
                if (aval.dataProva.isNotEmpty) {
                  try {
                    final data = DateTime.parse(aval.dataProva);
                    dataFormatada = DateFormat('dd/MM/yyyy').format(data);
                  } catch (e) {
                    dataFormatada = aval.dataProva;
                  }
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: temGabarito
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                temGabarito
                                    ? Icons.check_circle
                                    : Icons.warning_amber,
                                color: temGabarito
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    aval.nome,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${aval.numeroQuestoes} questões • $dataFormatada', // 🚨 CORRIGIDO: Usando dataProva em vez de anoSerie
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: temGabarito
                                    ? Colors.green.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: temGabarito
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                              child: Text(
                                temGabarito
                                    ? '✅ Gabarito OK'
                                    : '⚠️ Sem Gabarito',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: temGabarito
                                      ? Colors.green.shade800
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              appState.setAvaliacaoSelecionada(aval);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      TelaEditarGabarito(avaliacao: aval),
                                ),
                              );
                            },
                            icon: Icon(
                              temGabarito
                                  ? Icons.edit
                                  : Icons.add_circle_outline,
                            ),
                            label: Text(
                              temGabarito
                                  ? 'EDITAR GABARITO'
                                  : 'CADASTRAR GABARITO',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: temGabarito
                                  ? Colors.indigo
                                  : Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        backgroundColor: Colors.teal,
        child: const Icon(Icons.arrow_back),
        tooltip: 'Voltar para a tela inicial',
      ),
    );
  }
}
