import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TelaFechamentoBimestre extends StatefulWidget {
  const TelaFechamentoBimestre({super.key});

  @override
  State<TelaFechamentoBimestre> createState() => _TelaFechamentoBimestreState();
}

class _TelaFechamentoBimestreState extends State<TelaFechamentoBimestre> {
  int _bimestreSelecionado = 3;
  List<Map<String, dynamic>> turmas = [];
  List<Map<String, dynamic>> avaliacoes = [];
  List<Map<String, dynamic>> alunos = [];
  Map<int, Map<int, double>> notasPorAluno = {};
  bool carregando = false;
  Map<String, dynamic>? turmaSelecionada;

  @override
  void initState() {
    super.initState();
    _carregarTurmas();
  }

  Future<void> _carregarTurmas() async {
    setState(() => carregando = true);
    try {
      final supabase = Supabase.instance.client;
      final t = await supabase.from('turmas').select('*').order('nome');
      final lista = List<Map<String, dynamic>>.from(t);
      lista.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));
      setState(() {
        turmas = lista;
        carregando = false;
      });
    } catch (e) {
      setState(() => carregando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _carregarDados() async {
    if (turmaSelecionada == null) return;
    setState(() => carregando = true);
    try {
      final supabase = Supabase.instance.client;
      final idTurma = turmaSelecionada!['id'];

      final a = await supabase
          .from('avaliacoes')
          .select('*')
          .eq('bimestre', _bimestreSelecionado)
          .order('id');

      final al = await supabase
          .from('alunos')
          .select('*')
          .eq('id_turma', idTurma)
          .order('numero_chamada');

      final listaAlunos = List<Map<String, dynamic>>.from(al);
      listaAlunos.sort((a, b) {
        final na = (a['numero_chamada'] as num?)?.toInt() ?? 0;
        final nb = (b['numero_chamada'] as num?)?.toInt() ?? 0;
        return na.compareTo(nb);
      });

      final idsAval = a.map((av) => av['id']).toList();
      List<dynamic> r = [];
      if (idsAval.isNotEmpty) {
        r = await supabase
            .from('resultados')
            .select('id_aluno, id_avaliacao, nota_bruta')
            .inFilter('id_avaliacao', idsAval);
      }

      final Map<int, Map<int, double>> notas = {};
      for (final res in r) {
        final idAluno = res['id_aluno'] as int;
        final idAval = res['id_avaliacao'] as int;
        final nota = res['nota_bruta'];
        if (nota is num) {
          notas.putIfAbsent(idAluno, () => {});
          notas[idAluno]![idAval] = nota.toDouble();
        }
      }

      setState(() {
        avaliacoes = List<Map<String, dynamic>>.from(a);
        alunos = listaAlunos;
        notasPorAluno = notas;
        carregando = false;
      });
    } catch (e) {
      setState(() => carregando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _nivelFinal(double media) {
    if (media >= 8) return 'Avançado';
    if (media >= 6) return 'Adequado';
    if (media >= 4) return 'Básico';
    return 'Abaixo do Básico';
  }

  Color _corNivel(String nivel) {
    if (nivel.contains('Avanç')) return Colors.green;
    if (nivel.contains('Adequado')) return Colors.blue;
    if (nivel.contains('Básico')) return Colors.orange;
    return Colors.red;
  }

  // 🚨 MÉDIA PONDERADA: só conta avaliações que já têm nota lançada
  double _calcularMedia(int idAluno) {
    final notas = notasPorAluno[idAluno] ?? {};
    double somaNotas = 0;
    double somaPesos = 0;
    for (final av in avaliacoes) {
      final nota = notas[av['id']];
      if (nota == null) continue;
      final peso = (av['peso_media'] as num?)?.toDouble() ?? 1.0;
      somaNotas += nota * peso;
      somaPesos += peso;
    }
    return somaPesos > 0 ? somaNotas / somaPesos : 0.0;
  }

  bool _temNotas(int idAluno) => (notasPorAluno[idAluno] ?? {}).isNotEmpty;

  // 📋 BOLETIM INDIVIDUAL (abre ao tocar no aluno)
  void _abrirBoletim(Map<String, dynamic> aluno) {
    final id = aluno['id'] as int;
    final notas = notasPorAluno[id] ?? {};
    final media = _calcularMedia(id);
    final nivel = _nivelFinal(media);
    final cor = _corNivel(nivel);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${aluno['nome_completo']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              'Boletim • ${_bimestreSelecionado}º Bimestre • ${turmaSelecionada?['nome'] ?? ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    const Text(
                      'Média Final',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      _temNotas(id) ? media.toStringAsFixed(2) : '—',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                if (_temNotas(id))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cor),
                    ),
                    child: Text(
                      nivel,
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Avaliações do bimestre',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final av in avaliacoes)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple.shade50,
                          child: Icon(
                            (av['modo_correcao'] ?? 'omr') == 'manual'
                                ? Icons.edit_note
                                : Icons.camera_alt,
                            color: Colors.deepPurple,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${av['nome']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${av['tipo'] ?? 'Prova'} • peso ${(av['peso_media'] as num?)?.toInt() ?? 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          notas[av['id']] != null
                              ? notas[av['id']]!.toStringAsFixed(1)
                              : '—',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: notas[av['id']] != null
                                ? Colors.deepPurple
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Média = soma de (nota × peso) ÷ soma dos pesos.\nAvaliações sem nota lançada não entram na conta.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int cAbaixo = 0, cBasico = 0, cAdequado = 0, cAvancado = 0, cSemNota = 0;
    double somaMedias = 0;
    int comNota = 0;
    for (final al in alunos) {
      if (!_temNotas(al['id'] as int)) {
        cSemNota++;
        continue;
      }
      final media = _calcularMedia(al['id'] as int);
      somaMedias += media;
      comNota++;
      final nivel = _nivelFinal(media);
      if (nivel == 'Avançado')
        cAvancado++;
      else if (nivel == 'Adequado')
        cAdequado++;
      else if (nivel == 'Básico')
        cBasico++;
      else
        cAbaixo++;
    }
    final mediaTurma = comNota > 0 ? somaMedias / comNota : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fechamento do Bimestre'),
        backgroundColor: Colors.deepPurple,
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
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: _bimestreSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Bimestre',
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
                          setState(() => _bimestreSelecionado = v ?? 3);
                          _carregarDados();
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        isExpanded: true,
                        value: turmaSelecionada,
                        decoration: const InputDecoration(
                          labelText: 'Turma',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in turmas)
                            DropdownMenuItem(
                              value: t,
                              child: Text('${t['nome']}'),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => turmaSelecionada = v);
                          _carregarDados();
                        },
                      ),
                    ],
                  ),
                ),
                if (turmaSelecionada != null && avaliacoes.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma avaliação cadastrada para o ${_bimestreSelecionado}º bimestre.\nUse o botão "+" na tela da turma para cadastrar.',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else if (turmaSelecionada != null)
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Card(
                            color: Colors.deepPurple.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _statChip(
                                    'Média',
                                    comNota > 0
                                        ? mediaTurma.toStringAsFixed(2)
                                        : '—',
                                    Colors.indigo,
                                  ),
                                  _statChip('Abaixo', '$cAbaixo', Colors.red),
                                  _statChip(
                                    'Básico',
                                    '$cBasico',
                                    Colors.orange,
                                  ),
                                  _statChip(
                                    'Adequado',
                                    '$cAdequado',
                                    Colors.blue,
                                  ),
                                  _statChip(
                                    'Avançado',
                                    '$cAvancado',
                                    Colors.green,
                                  ),
                                  _statChip(
                                    'S/ nota',
                                    '$cSemNota',
                                    Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: alunos.length,
                            itemBuilder: (context, index) {
                              final al = alunos[index];
                              final id = al['id'] as int;
                              final temNota = _temNotas(id);
                              final media = _calcularMedia(id);
                              final nivel = _nivelFinal(media);
                              final cor = _corNivel(nivel);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: temNota
                                        ? cor.withOpacity(0.15)
                                        : Colors.grey.shade200,
                                    child: Text(
                                      '${al['numero_chamada'] ?? (index + 1)}',
                                      style: TextStyle(
                                        color: temNota ? cor : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    '${al['nome_completo']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    temNota
                                        ? 'Toque para ver o boletim 📋'
                                        : 'Sem notas neste bimestre',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: temNota
                                          ? Colors.deepPurple
                                          : Colors.grey,
                                    ),
                                  ),
                                  trailing: temNota
                                      ? Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              media.toStringAsFixed(2),
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: cor,
                                              ),
                                            ),
                                            Text(
                                              nivel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: cor,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Icon(
                                          Icons.remove,
                                          color: Colors.grey.shade400,
                                        ),
                                  onTap: () => _abrirBoletim(al),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
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
}
