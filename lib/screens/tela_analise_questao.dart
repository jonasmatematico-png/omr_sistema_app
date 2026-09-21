import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TelaAnaliseQuestao extends StatefulWidget {
  const TelaAnaliseQuestao({super.key});

  @override
  State<TelaAnaliseQuestao> createState() => _TelaAnaliseQuestaoState();
}

class _TelaAnaliseQuestaoState extends State<TelaAnaliseQuestao> {
  bool carregando = true;
  String? erro;

  String nomeAvaliacao = 'Avaliação';
  final List<String> nomesTurmas = [];
  final List<Map<String, dynamic>> questoesAnalise = [];
  final Map<String, List<int>> nivelAcertos = {};
  String questaoMaisDificil = '-';
  double pctMaisDificil = 0;
  String questaoMaisFacil = '-';
  double pctMaisFacil = 0;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

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

  Color _corPct(double pct) {
    if (pct < 40) return Colors.red;
    if (pct < 60) return Colors.orange;
    if (pct < 80) return Colors.blue;
    return Colors.green;
  }

  String _rotuloCurto(String nome) {
    final partes = nome.trim().split(' ');
    return partes.isEmpty ? '-' : partes.last;
  }

  int _pctLista(List<int> v) => v[1] > 0 ? (v[0] * 100 ~/ v[1]) : 0;

  Future<void> _carregarDados() async {
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      final supabase = Supabase.instance.client;

      final turmasResp = await _buscarTudo(supabase, 'turmas');
      final alunosResp = await _buscarTudo(supabase, 'alunos');
      final respostasResp = await _buscarTudo(supabase, 'respostas');
      final questoesResp = await _buscarTudo(supabase, 'questoes');
      final avaliacoesResp = await _buscarTudo(supabase, 'avaliacoes');

      turmasResp.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

      final Map<String, String> turmaNome = {};
      for (final t in turmasResp) {
        turmaNome['${t['id']}'] = (t['nome'] ?? 'Turma').toString();
      }
      final Map<String, String> alunoTurma = {};
      for (final a in alunosResp) {
        alunoTurma['${a['id']}'] = turmaNome['${a['id_turma']}'] ?? '-';
      }

      // escolhe a avaliação com mais respostas registradas
      final Map<String, int> contagemAval = {};
      for (final r in respostasResp) {
        final id = '${r['id_avaliacao']}';
        contagemAval[id] = (contagemAval[id] ?? 0) + 1;
      }
      String avalEscolhida = '';
      int maxResp = 0;
      contagemAval.forEach((id, c) {
        if (c > maxResp) {
          maxResp = c;
          avalEscolhida = id;
        }
      });

      for (final a in avaliacoesResp) {
        if ('${a['id']}' == avalEscolhida) {
          nomeAvaliacao = (a['nome'] ?? 'Avaliação').toString();
        }
      }

      // numero da questão -> nível
      final Map<String, String> nivelQuestao = {};
      for (final q in questoesResp) {
        if ('${q['id_avaliacao']}' != avalEscolhida) continue;
        nivelQuestao['${q['numero']}'] = (q['nivel'] ?? '').toString().toLowerCase();
      }

      // acertos/totais por questão x turma e geral
      final Map<String, Map<String, List<int>>> porQuestaoTurma = {};
      final Map<String, List<int>> porQuestaoGeral = {};

      for (final r in respostasResp) {
        if ('${r['id_avaliacao']}' != avalEscolhida) continue;
        final respostaLida = (r['resposta_aluno'] ?? '').toString().trim();
        if (respostaLida.isEmpty) continue;
        final numQ = '${r['id_questao']}';
        final turma = alunoTurma['${r['id_aluno']}'] ?? '-';
        final acertou = r['correta'] == true;

        final porTurma = porQuestaoTurma.putIfAbsent(numQ, () => {});
        final vT = porTurma.putIfAbsent(turma, () => [0, 0]);
        vT[1] = vT[1] + 1;
        if (acertou) vT[0] = vT[0] + 1;

        final vG = porQuestaoGeral.putIfAbsent(numQ, () => [0, 0]);
        vG[1] = vG[1] + 1;
        if (acertou) vG[0] = vG[0] + 1;
      }

      final numeros = porQuestaoGeral.keys.toList()
        ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

      questoesAnalise.clear();
      nivelAcertos.clear();
      nomesTurmas
        ..clear()
        ..addAll(turmasResp.map((t) => turmaNome['${t['id']}'] ?? 'Turma'));

      double minP = 101;
      double maxP = -1;

      for (final numQ in numeros) {
        final geral = porQuestaoGeral[numQ]!;
        final pctGeral = geral[1] > 0 ? geral[0] * 100 / geral[1] : 0.0;

        final linha = <String, dynamic>{'numero': numQ, 'geral': pctGeral};
        for (final t in turmasResp) {
          final nomeT = turmaNome['${t['id']}'] ?? 'Turma';
          final v = porQuestaoTurma[numQ]?[nomeT];
          linha[nomeT] = (v == null || v[1] == 0) ? null : v[0] * 100 / v[1];
        }

        final nivel = nivelQuestao[numQ] ?? '';
        String chaveNivel = '';
        if (nivel.contains('básic') || nivel.contains('basic')) chaveNivel = 'Básico';
        else if (nivel.contains('inter')) chaveNivel = 'Intermediário';
        else if (nivel.contains('avanç')) chaveNivel = 'Avançado';
        if (chaveNivel.isNotEmpty) {
          final vN = nivelAcertos.putIfAbsent(chaveNivel, () => [0, 0]);
          vN[0] = vN[0] + geral[0];
          vN[1] = vN[1] + geral[1];
        }

        if (pctGeral < minP) {
          minP = pctGeral;
          questaoMaisDificil = 'Q$numQ';
          pctMaisDificil = pctGeral;
        }
        if (pctGeral > maxP) {
          maxP = pctGeral;
          questaoMaisFacil = 'Q$numQ';
          pctMaisFacil = pctGeral;
        }

        questoesAnalise.add(linha);
      }

      setState(() => carregando = false);
    } catch (e) {
      setState(() {
        carregando = false;
        erro = e.toString();
      });
    }
  }

  Widget _pctCell(double? pct) {
    if (pct == null) {
      return const Text('-', style: TextStyle(color: Colors.grey));
    }
    return Text(
      '${pct.round()}%',
      style: TextStyle(fontWeight: FontWeight.bold, color: _corPct(pct)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise por Questão'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.indigo),
                  SizedBox(height: 16),
                  Text(
                    '📊 Analisando acertos por questão...',
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
                          'Erro ao carregar a análise:\n$erro',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
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
              : questoesAnalise.isEmpty
                  ? const Center(
                      child: Text('Nenhuma resposta encontrada para esta avaliação.'),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          color: Colors.indigo.shade50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                const Icon(Icons.assignment, color: Colors.indigo),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    nomeAvaliacao,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // TABELA QUESTÕES x TURMAS
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Colors.indigo.shade50),
                              columns: [
                                const DataColumn(label: Text('Questão', style: TextStyle(fontWeight: FontWeight.bold))),
                                for (final t in nomesTurmas)
                                  DataColumn(label: Text(_rotuloCurto(t), style: const TextStyle(fontWeight: FontWeight.bold))),
                                const DataColumn(label: Text('Geral', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: [
                                for (final q in questoesAnalise)
                                  DataRow(cells: [
                                    DataCell(Text('Q${q['numero']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                    for (final t in nomesTurmas)
                                      DataCell(_pctCell(q[t] as double?)),
                                    DataCell(_pctCell(q['geral'] as double?)),
                                  ]),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ACERTO POR NÍVEL
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Média de Acertos por Nível',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                for (final nivel in ['Básico', 'Intermediário', 'Avançado'])
                                  if (nivelAcertos[nivel] != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 110,
                                            child: Text(nivel, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          ),
                                          Expanded(
                                            child: LinearProgressIndicator(
                                              value: _pctLista(nivelAcertos[nivel]!) / 100,
                                              backgroundColor: Colors.grey[200],
                                              valueColor: AlwaysStoppedAnimation<Color>(_corPct(_pctLista(nivelAcertos[nivel]!).toDouble())),
                                              minHeight: 8,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_pctLista(nivelAcertos[nivel]!)}%',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // PONTOS DE ATENÇÃO
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pontos de Atenção',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.trending_down, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Questão com MENOS acertos: $questaoMaisDificil (${pctMaisDificil.round()}%)',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.trending_up, color: Colors.green),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Questão com MAIS acertos: $questaoMaisFacil (${pctMaisFacil.round()}%)',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
    );
  }
}
