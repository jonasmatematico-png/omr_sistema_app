import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tela_analise_detalhada.dart';
import 'tela_analise_questao.dart';

class TelaDashboard extends StatefulWidget {
  const TelaDashboard({super.key});

  @override
  State<TelaDashboard> createState() => _TelaDashboardState();
}

class _TelaDashboardState extends State<TelaDashboard> {
  bool carregando = true;
  String? erro;

  double mediaGeral = 0;
  int totalAlunos = 0;
  int pctAbaixo = 0;
  int pctBasico = 0;
  int pctAdequado = 0;
  int pctAvancado = 0;
  String descritorMin = '-';
  double pctMin = 0;
  String descritorMax = '-';
  double pctMax = 0;

  final List<Map<String, dynamic>> turmas = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  String _nivelPorNota(double nota) {
    if (nota >= 8.67) return 'Avançado';
    if (nota >= 6.51) return 'Adequado';
    if (nota >= 5) return 'Básico';
    return 'Abaixo do Básico';
  }

  String _categoriaNivel(dynamic nivelBruto, double nota) {
    final n = (nivelBruto ?? '').toString().toLowerCase();
    if (n.isEmpty) return _nivelPorNota(nota);
    if (n.contains('abaixo')) return 'Abaixo';
    if (n.contains('avanç')) return 'Avançado';
    if (n.contains('adequ')) return 'Adequado';
    if (n.contains('básic')) return 'Básico';
    return 'Abaixo';
  }

  double _notaDe(dynamic r) {
    final notaBruta = r['nota_bruta'] ?? r['nota_final'];
    if (notaBruta is num) return notaBruta.toDouble();
    return double.tryParse('$notaBruta') ?? 0.0;
  }

  // 🚨 Busca TODAS as linhas em páginas de 1000 (o Supabase corta em 1000 por vez)
  Future<List<Map<String, dynamic>>> _buscarTudo(
    SupabaseClient supabase,
    String tabela,
  ) async {
    final List<Map<String, dynamic>> tudo = [];
    int offset = 0;
    while (true) {
      final parte = await supabase
          .from(tabela)
          .select('*')
          .range(offset, offset + 999);
      tudo.addAll(parte);
      if (parte.length < 1000) break;
      offset += 1000;
    }
    return tudo;
  }

  Future<void> _carregarDados() async {
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      final supabase = Supabase.instance.client;

      final turmasResp = await _buscarTudo(supabase, 'turmas');
      final alunosResp = await _buscarTudo(supabase, 'alunos');
      final resultadosResp = await _buscarTudo(supabase, 'resultados');
      final respostasResp = await _buscarTudo(supabase, 'respostas');
      final questoesResp = await _buscarTudo(supabase, 'questoes');

      // aluno id -> turma
      final Map<String, String> turmaDoAluno = {};
      for (final a in alunosResp) {
        turmaDoAluno['${a['id']}'] = '${a['id_turma']}';
      }

      // só considera alunos com respostas REAIS (não vazias)
      final Set<String> alunosValidos = {};
      for (final resp in respostasResp) {
        final respostaLida = (resp['resposta_aluno'] ?? '').toString().trim();
        if (respostaLida.isNotEmpty) {
          alunosValidos.add('${resp['id_aluno']}');
        }
      }

      // aluno id -> resultado (vale o último)
      final Map<String, Map<String, dynamic>> resultadoDoAluno = {};
      for (final r in resultadosResp) {
        resultadoDoAluno['${r['id_aluno']}'] = r;
      }

      // se o descritor estiver vazio, usa "Q1, Q2..." como rótulo
      final Map<String, String> descritorQuestao = {};
      for (final q in questoesResp) {
        final descTexto = (q['descritor'] ?? '').toString().trim();
        final rotulo = descTexto.isNotEmpty ? descTexto : 'Q${q['numero']}';
        descritorQuestao['${q['id_avaliacao']}-${q['numero']}'] = rotulo;
      }

      // ---------- ESTATÍSTICAS GERAIS ----------
      double somaNotas = 0;
      int cAbaixo = 0, cBasico = 0, cAdequado = 0, cAvancado = 0;

      resultadoDoAluno.forEach((idAluno, r) {
        if (!alunosValidos.contains(idAluno)) return;
        totalAlunos++; // conta só quem tem resposta REAL + resultado
        final nota = _notaDe(r);
        somaNotas += nota;
        final cat = _categoriaNivel(r['nivel_saeb'], nota);
        if (cat == 'Avançado') cAvancado++;
        else if (cat == 'Adequado') cAdequado++;
        else if (cat == 'Básico') cBasico++;
        else cAbaixo++;
      });

      if (totalAlunos > 0) {
        // 🚨 Arredonda como a escola (36,67% vira 37%)
      pctAbaixo = (cAbaixo * 100 / totalAlunos).round();
        pctBasico = (cBasico * 100 / totalAlunos).round();
        pctAdequado = (cAdequado * 100 / totalAlunos).round();
        pctAvancado = (cAvancado * 100 / totalAlunos).round();

      // ---------- % DE ACERTO POR DESCRITOR ----------
      final Map<String, List<int>> acertosDescritor = {};
      for (final resp in respostasResp) {
        final respostaLida = (resp['resposta_aluno'] ?? '').toString().trim();
        if (respostaLida.isEmpty) continue;
        final desc =
            descritorQuestao['${resp['id_avaliacao']}-${resp['id_questao']}'] ?? '';
        if (desc.isEmpty) continue;
        final v = acertosDescritor.putIfAbsent(desc, () => [0, 0]);
        v[1] = v[1] + 1;
        if (resp['correta'] == true) v[0] = v[0] + 1;
      }

      double minP = 101;
      double maxP = -1;
      acertosDescritor.forEach((desc, v) {
        final pct = v[1] > 0 ? (v[0] * 100) / v[1] : 0.0;
        if (pct < minP) {
          minP = pct;
          descritorMin = desc;
        }
        if (pct > maxP) {
          maxP = pct;
          descritorMax = desc;
        }
      });
      pctMin = minP == 101 ? 0 : minP;
      pctMax = maxP == -1 ? 0 : maxP;
      if (minP == 101) descritorMin = '-';
      if (maxP == -1) descritorMax = '-';

      // ---------- RESULTADOS POR TURMA ----------
      turmas.clear();
      turmasResp.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

      for (final t in turmasResp) {
        final idTurma = '${t['id']}';

        double soma = 0;
        int n = 0;
        int tAbaixo = 0, tBasico = 0, tAdequado = 0, tAvancado = 0;

        resultadoDoAluno.forEach((idAluno, r) {
          if (!alunosValidos.contains(idAluno)) return;
          if (turmaDoAluno[idAluno] != idTurma) return;
          final nota = _notaDe(r);
          soma += nota;
          n++;
          final cat = _categoriaNivel(r['nivel_saeb'], nota);
          if (cat == 'Avançado') tAvancado++;
          else if (cat == 'Adequado') tAdequado++;
          else if (cat == 'Básico') tBasico++;
          else tAbaixo++;
        });

        // descritor crítico da turma (o com mais erros)
        final Map<String, int> errosDesc = {};
        for (final resp in respostasResp) {
          final respostaLida = (resp['resposta_aluno'] ?? '').toString().trim();
          if (respostaLida.isEmpty) continue;
          if (resp['correta'] == true) continue;
          final idAluno = '${resp['id_aluno']}';
          if (turmaDoAluno[idAluno] != idTurma) continue;
          final desc =
              descritorQuestao['${resp['id_avaliacao']}-${resp['id_questao']}'] ?? '';
          if (desc.isEmpty) continue;
          errosDesc[desc] = (errosDesc[desc] ?? 0) + 1;
        }
        String descCritico = '-';
        int maxErros = 0;
        errosDesc.forEach((d, c) {
          if (c > maxErros) {
            maxErros = c;
            descCritico = d;
          }
        });

        turmas.add({
          'nome': (t['nome'] ?? 'Turma').toString(),
          'alunos': n,
          'media': n > 0 ? soma / n : 0.0,
          'abaixo': n > 0 ? (tAbaixo * 100 / n).round() : 0,
          'basico': n > 0 ? (tBasico * 100 / n).round() : 0,
          'adequado': n > 0 ? (tAdequado * 100 / n).round() : 0,
          'avancado': n > 0 ? (tAvancado * 100 / n).round() : 0,
          'descritor': descCritico,
        });
      }

      setState(() => carregando = false);
    } catch (e) {
      setState(() {
        carregando = false;
        erro = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard - Análise Avaliativa'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 28),
            tooltip: 'Análise por Questão',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TelaAnaliseQuestao()),
            ),
          ),
        ],
      ),
      body: carregando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.indigo),
                  SizedBox(height: 16),
                  Text(
                    '📊 Calculando indicadores no Supabase...',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
            )
          : erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          'Erro ao carregar o dashboard:\n$erro',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _carregarDados,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Professor(a): JONAS OLIVEIRA RIBEIRO',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildInfoChip('Disciplina', 'Matemática'),
                                    _buildInfoChip('Turma', '6º ano'),
                                    _buildInfoChip('Bimestre', '2º'),
                                  ],
                                ),
                                const Divider(height: 24),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: _buildMetricCard('Média Geral', mediaGeral.toStringAsFixed(2), '', Colors.blue)),
                                        const SizedBox(width: 10),
                                        Expanded(child: _buildMetricCard('Total Alunos', '$totalAlunos', 'corrigidos', Colors.green)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(child: _buildMetricCard('Menor % (descritor)', '${pctMin.toStringAsFixed(0)}%', descritorMin, Colors.red)),
                                        const SizedBox(width: 10),
                                        Expanded(child: _buildMetricCard('Maior % (descritor)', '${pctMax.toStringAsFixed(0)}%', descritorMax, Colors.orange)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

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
                                DataColumn(label: Text('Abaixo', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Básico', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Adequado', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Avançado', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Descritor', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: turmas.map((t) {
                                return DataRow(cells: [
                                  DataCell(Text(t['nome'], style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text('${t['alunos']}')),
                                  DataCell(Text((t['media'] as double).toStringAsFixed(2))),
                                  DataCell(_buildPercentageCell(t['abaixo'] as int, Colors.red)),
                                  DataCell(_buildPercentageCell(t['basico'] as int, Colors.orange)),
                                  DataCell(_buildPercentageCell(t['adequado'] as int, Colors.blue)),
                                  DataCell(_buildPercentageCell(t['avancado'] as int, Colors.green)),
                                  DataCell(Text(t['descritor'], style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

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
                                      'Resumo Automático',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'A avaliação aplicada registrou média geral de ${mediaGeral.toStringAsFixed(2)} pontos, com participação de $totalAlunos estudantes. '
                                  'A distribuição por nível de proficiência indica $pctAbaixo% no nível Abaixo do Básico, $pctBasico% no nível Básico, $pctAdequado% no nível Adequado e $pctAvancado% no nível Avançado. '
                                  'Na análise por descritores, o menor índice de acerto foi "$descritorMin" (${pctMin.toStringAsFixed(0)}%), configurando-se como o descritor de menor desempenho, '
                                  'enquanto o melhor desempenho foi "$descritorMax" (${pctMax.toStringAsFixed(0)}%). '
                                  'Os dados consolidados expressam o panorama quantitativo do desempenho das turmas na avaliação aplicada.',
                                  style: const TextStyle(height: 1.5, fontSize: 14),
                                  textAlign: TextAlign.justify,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TelaAnaliseDetalhada(),
            ),
          );
        },
        label: const Text('Análise Detalhada'),
        icon: const Icon(Icons.analytics_outlined),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8))),
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
