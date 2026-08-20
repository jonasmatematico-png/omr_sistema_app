import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TelaAnalisePedagogica extends StatefulWidget {
  const TelaAnalisePedagogica({super.key});

  @override
  State<TelaAnalisePedagogica> createState() => _TelaAnalisePedagogicaState();
}

class _TelaAnalisePedagogicaState extends State<TelaAnalisePedagogica> {
  int _bimestre = 3;
  String _filtro = 'todos';
  List<Map<String, dynamic>> turmas = [];
  List<Map<String, dynamic>> avaliacoesTodas = [];
  int? turmaId;
  int? refId;
  List<Map<String, dynamic>> alunos = [];
  List<Map<String, dynamic>> avaliacoesBim = [];
  Map<int, Map<int, double>> notasPorAluno = {};
  Map<int, Map<String, dynamic>> refPorAluno = {};
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarTurmas();
  }

  Future<void> _carregarTurmas() async {
    try {
      final supabase = Supabase.instance.client;
      final t = await supabase.from('turmas').select('*').order('nome');
      final lista = List<Map<String, dynamic>>.from(t);
      // 🚨 Força a ordem A → Z aqui no app
      lista.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));
      setState(() {
        turmas = lista;
        carregando = false;
      });
    } catch (e) {
      setState(() => carregando = false);
    }
  }

  Future<void> _carregarDados() async {
    setState(() => carregando = true);
    try {
      final supabase = Supabase.instance.client;
      final a = await supabase.from('avaliacoes').select('*').order('id');
      final todas = List<Map<String, dynamic>>.from(a);

      // 🚨 Auto-seleciona a referência pelo nome (só na primeira vez)
      if (refId == null) {
        for (final av in todas) {
          if ('${av['nome']}'.toLowerCase().contains('saeb')) {
            refId = av['id'] as int;
            break;
          }
        }
      }

      List<Map<String, dynamic>> al = [];
      if (turmaId != null) {
        al = await supabase
            .from('alunos')
            .select('*')
            .eq('id_turma', turmaId!)
            .order('numero_chamada');
        // 🚨 Força a ordem crescente da chamada aqui no app
        al.sort(
          (a, b) => ((a['numero_chamada'] as num?)?.toInt() ?? 0).compareTo(
            (b['numero_chamada'] as num?)?.toInt() ?? 0,
          ),
        );
      }

      final bimAvals = todas
          .where(
            (av) =>
                (av['bimestre'] as int? ?? 0) == _bimestre &&
                (refId == null || av['id'] != refId),
          )
          .toList();

      final ids = <dynamic>[];
      if (refId != null) ids.add(refId);
      ids.addAll(bimAvals.map((e) => e['id']));

      final Map<int, Map<int, double>> notas = {};
      final Map<int, Map<String, dynamic>> ref = {};
      if (ids.isNotEmpty) {
        final r = await supabase
            .from('resultados')
            .select('*')
            .inFilter('id_avaliacao', ids);
        for (final res in r) {
          final idAluno = res['id_aluno'] as int;
          final idAval = res['id_avaliacao'] as int;
          if (refId != null && idAval == refId) {
            ref[idAluno] = res;
          } else {
            final nb = res['nota_bruta'];
            if (nb is num) {
              notas.putIfAbsent(idAluno, () => {});
              notas[idAluno]![idAval] = nb.toDouble();
            }
          }
        }
      }

      setState(() {
        avaliacoesTodas = todas;
        avaliacoesBim = bimAvals;
        alunos = List<Map<String, dynamic>>.from(al);
        notasPorAluno = notas;
        refPorAluno = ref;
        carregando = false;
      });
    } catch (e) {
      setState(() => carregando = false);
    }
  }

  double _media(int idAluno) {
    final notas = notasPorAluno[idAluno] ?? {};
    double sn = 0, sp = 0;
    for (final av in avaliacoesBim) {
      final nota = notas[av['id']];
      if (nota == null) continue;
      final peso = (av['peso_media'] as num?)?.toDouble() ?? 1.0;
      sn += nota * peso;
      sp += peso;
    }
    return sp > 0 ? sn / sp : -1;
  }

  String _status(int idAluno) {
    final s = refPorAluno[idAluno];
    final media = _media(idAluno);
    if (s == null || media < 0) return 'semdados';
    final nivel = '${s['nivel_saeb']}'.toLowerCase();
    final baixoRef = nivel.contains('abaixo') || nivel.contains('básic');
    if (baixoRef && media < 6) return 'reforco';
    if (baixoRef && media >= 6) return 'evoluindo';
    if (!baixoRef && media < 6) return 'atencao';
    return 'ok';
  }

  Map<String, dynamic> _meta(String status) {
    switch (status) {
      case 'reforco':
        return {
          'rotulo': 'Reforço prioritário',
          'cor': Colors.red,
          'icone': Icons.priority_high,
        };
      case 'evoluindo':
        return {
          'rotulo': 'Evoluindo no bimestre',
          'cor': Colors.blue,
          'icone': Icons.trending_up,
        };
      case 'atencao':
        return {
          'rotulo': 'Atenção: caiu no bimestre',
          'cor': Colors.orange,
          'icone': Icons.trending_down,
        };
      case 'ok':
        return {
          'rotulo': 'No caminho certo',
          'cor': Colors.green,
          'icone': Icons.check_circle,
        };
      default:
        return {
          'rotulo': 'Sem dados completos',
          'cor': Colors.grey,
          'icone': Icons.remove_circle,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    int cReforco = 0, cAtencao = 0, cEvoluindo = 0, cOk = 0, cSem = 0;
    for (final al in alunos) {
      final st = _status(al['id'] as int);
      if (st == 'reforco') cReforco++;
      if (st == 'atencao') cAtencao++;
      if (st == 'evoluindo') cEvoluindo++;
      if (st == 'ok') cOk++;
      if (st == 'semdados') cSem++;
    }

    final lista = _filtro == 'todos'
        ? alunos
        : alunos.where((al) => _status(al['id'] as int) == _filtro).toList();

    final temNotasBim = notasPorAluno.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise Pedagógica'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 🚨 Agora compara pelo ID (nunca quebra)
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: refId,
                        decoration: const InputDecoration(
                          labelText:
                              'Avaliação de referência (base do cruzamento)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final av in avaliacoesTodas)
                            DropdownMenuItem(
                              value: av['id'] as int,
                              child: Text(
                                '${av['nome']} • ${av['bimestre'] ?? '-'}º bim',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => refId = v);
                          _carregarDados();
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: _bimestre,
                        decoration: const InputDecoration(
                          labelText: 'Bimestre atual (para comparar)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('1º Bimestre'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('2º Bimestre'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('3º Bimestre'),
                          ),
                          DropdownMenuItem(
                            value: 4,
                            child: Text('4º Bimestre'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _bimestre = v ?? 3);
                          _carregarDados();
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: turmaId,
                        decoration: const InputDecoration(
                          labelText: 'Turma',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in turmas)
                            DropdownMenuItem(
                              value: t['id'] as int,
                              child: Text('${t['nome']}'),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => turmaId = v);
                          _carregarDados();
                        },
                      ),
                    ],
                  ),
                ),
                if (refId == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '⚠️ Selecione acima a avaliação de referência\n(ex: o Simulado SAEB).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                if (refId != null &&
                    turmaId != null &&
                    (!temNotasBim || avaliacoesBim.isEmpty))
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '📝 Ainda não há notas lançadas no ${_bimestre}º bimestre.\nUse "Lançar Notas Manuais" ou corrija provas pela câmera para alimentar o cruzamento.\n\nDica: selecione o 2º bimestre para ver o cruzamento com os dados do SAEB.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                if (refId != null &&
                    turmaId != null &&
                    temNotasBim &&
                    avaliacoesBim.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Colors.teal.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statChip('Reforço', '$cReforco', Colors.red),
                            _statChip('Atenção', '$cAtencao', Colors.orange),
                            _statChip('Evoluindo', '$cEvoluindo', Colors.blue),
                            _statChip('No caminho', '$cOk', Colors.green),
                            _statChip('Sem dados', '$cSem', Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _filtroChip('todos', 'Todos'),
                        _filtroChip('reforco', '🔴 Reforço'),
                        _filtroChip('atencao', '🟡 Atenção'),
                        _filtroChip('evoluindo', '🔵 Evoluindo'),
                        _filtroChip('ok', '🟢 No caminho'),
                        _filtroChip('semdados', '⚪ Sem dados'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: lista.length,
                      itemBuilder: (context, index) {
                        final al = lista[index];
                        final id = al['id'] as int;
                        final st = _status(id);
                        final meta = _meta(st);
                        final cor = meta['cor'] as Color;
                        final media = _media(id);
                        final ref = refPorAluno[id];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: cor, width: 1.5),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cor.withOpacity(0.15),
                              child: Icon(
                                meta['icone'] as IconData,
                                color: cor,
                              ),
                            ),
                            title: Text(
                              '${al['numero_chamada']}. ${al['nome_completo']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              'Referência: ${ref != null ? ref['nivel_saeb'] : '—'}  →  ${_bimestre}º bim: ${media >= 0 ? media.toStringAsFixed(1) : '—'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${meta['rotulo']}',
                                style: TextStyle(
                                  color: cor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _statChip(String label, String value, Color cor) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: cor,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _filtroChip(String valor, String rotulo) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(rotulo, style: const TextStyle(fontSize: 12)),
        selected: _filtro == valor,
        onSelected: (_) => setState(() => _filtro = valor),
      ),
    );
  }
}
