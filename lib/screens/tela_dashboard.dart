import 'package:flutter/material.dart';
// Se você usa Provider para gerenciamento de estado, descomente a linha abaixo:
// import 'package:provider/provider.dart';
// import '../context/app_state.dart';

class TelaDashboard extends StatelessWidget {
  const TelaDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Se usar Provider, descomente para acessar o AppState:
    // final appState = Provider.of<AppState>(context);

    // --- DADOS FICTÍCIOS PARA DEMONSTRAÇÃO ---
    // (Substitua estes valores pelos dados reais vindos do Supabase/AppState depois)
    final String nomeProfessor = "JONAS OLIVEIRA RIBEIRO";
    final String disciplina = "Matemática";
    final String turmaGeral = "6º ano";
    final String bimestre = "2º";
    final String dataProva = "18/06/26";
    final String conteudo = "NÚMEROS RACIONAIS";

    final double mediaGeral = 5.61;
    final int totalAlunos = 117;
    final double menorPercentual = 0.0;
    final double maiorPercentual = 0.0;

    // Lista de turmas para a tabela
    final List<Map<String, dynamic>> turmas = [
      {'nome': 'A', 'alunos': 30, 'media': 4.89, 'abaixo': 43, 'basico': 37, 'adequado': 13, 'avancado': 7, 'descritor': '9ª-M-D19'},
      {'nome': 'B', 'alunos': 28, 'media': 5.74, 'abaixo': 36, 'basico': 29, 'adequado': 32, 'avancado': 4, 'descritor': '9ª-M-D19'},
      {'nome': 'C', 'alunos': 30, 'media': 6.06, 'abaixo': 23, 'basico': 40, 'adequado': 27, 'avancado': 10, 'descritor': '1ª-Turma C'},
      {'nome': 'D', 'alunos': 29, 'media': 5.76, 'abaixo': 31, 'basico': 38, 'adequado': 14, 'avancado': 17, 'descritor': '2ª-Turma D'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard - Análise Avaliativa'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === SEÇÃO 1: CABEÇALHO E VISÃO GERAL ===
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Professor(a): $nomeProfessor',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildInfoChip('Disciplina', disciplina),
                          _buildInfoChip('Turma', turmaGeral),
                          _buildInfoChip('Bimestre', bimestre),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildInfoChip('Data', dataProva),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: _buildInfoChip('Conteúdo', conteudo),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Métricas Principais
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.5,
                        children: [
                          _buildMetricCard('Média Geral', mediaGeral.toStringAsFixed(2), Colors.blue),
                          _buildMetricCard('Total Alunos', totalAlunos.toString(), Colors.green),
                          _buildMetricCard('Menor %', '$menorPercentual%', Colors.red),
                          _buildMetricCard('Maior %', '$maiorPercentual%', Colors.orange),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // === SEÇÃO 2: RESULTADOS POR TURMA ===
              const Text(
                'Resultados por Turma',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.indigo.shade50),
                    columns: const [
                      DataColumn(label: Text('Turma', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Alunos', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Média', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Abaixo Básico', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Básico', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Adequado', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Avançado', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Descritor Crítico', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: turmas.map((t) {
                      return DataRow(cells: [
                        DataCell(Text(t['nome'], style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text('${t['alunos']}')),
                        DataCell(Text('${t['media'].toStringAsFixed(2)}')),
                        DataCell(_buildPercentageCell(t['abaixo'] as int, Colors.red)),
                        DataCell(_buildPercentageCell(t['basico'] as int, Colors.orange)),
                        DataCell(_buildPercentageCell(t['adequado'] as int, Colors.blue)),
                        DataCell(_buildPercentageCell(t['avancado'] as int, Colors.green)),
                        DataCell(Text(t['descritor'], style: const TextStyle(color: Colors.redAccent))),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // === SEÇÃO 3: RESUMO AUTOMÁTICO ===
              Card(
                elevation: 2,
                color: Colors.amber.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          const Text(
                            'Resumo Automático (Leitura Rápida)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'O simulado aplicado às quatro turmas registrou média geral de ${mediaGeral.toStringAsFixed(2)} pontos, com participação de $totalAlunos estudantes. '
                        'A distribuição dos resultados por nível de proficiência indica 33% dos estudantes no nível Abaixo do Básico, 36% no nível Básico, 21% no nível Adequado e 9% no nível Avançado. '
                        'Na análise por descritores, registrou-se o menor índice de acerto médio ($menorPercentual%), configurando-se como o descritor de menor desempenho no conjunto avaliado. '
                        'Os dados consolidados expressam o panorama quantitativo do desempenho das quatro turmas na avaliação aplicada.',
                        style: const TextStyle(height: 1.5, fontSize: 14),
                        textAlign: TextAlign.justify,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80), // Espaço para o botão flutuante não cobrir o texto
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Aqui você colocará a navegação para a próxima tela (ex: Análise Detalhada)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Em breve: Análise Detalhada por Aluno')),
          );
        },
        label: const Text('Análise Detalhada'),
        icon: const Icon(Icons.analytics_outlined),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildInfoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildPercentageCell(int percent, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          child: LinearProgressIndicator(
            value: percent / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(width: 8),
        Text('$percent%'),
      ],
    );
  }
}
