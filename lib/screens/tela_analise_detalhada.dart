import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Modelo simples para guardar o desempenho de cada aluno
class DesempenhoAluno {
  final String nome;
  final double nota;
  final String nivel;

  DesempenhoAluno({
    required this.nome,
    required this.nota,
    required this.nivel,
  });
}

class TelaAnaliseDetalhada extends StatefulWidget {
  const TelaAnaliseDetalhada({super.key});

  @override
  State<TelaAnaliseDetalhada> createState() => _TelaAnaliseDetalhadaState();
}

class _TelaAnaliseDetalhadaState extends State<TelaAnaliseDetalhada> {
  bool carregando = true;
  String? erro;
  final List<Map<String, dynamic>> analiseTurmas = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  String _nivelPorNota(double nota) {
    if (nota >= 8) return 'Avançado';
    if (nota >= 6) return 'Adequado';
    if (nota >= 4) return 'Básico';
    return 'Abaixo do Básico';
  }

  Color _corNivel(String nivel) {
    final n = nivel.toLowerCase();
    if (n.contains('abaixo')) return Colors.red;
    if (n.contains('avanç')) return Colors.green;
    if (n.contains('adequ')) return Colors.blue;
    if (n.contains('básic')) return Colors.orange;
    return Colors.red;
  }

  Future<void> _carregarDados() async {
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      final supabase = Supabase.instance.client;

      // select('*') para não dar erro se alguma coluna tiver nome diferente
      final turmas = await supabase.from('turmas').select('*');
      final alunos = await supabase.from('alunos').select('*');
      final resultados = await supabase.from('resultados').select('*');

      // aluno id -> nome e turma
      final Map<String, String> nomeAlunos = {};
      final Map<String, String> turmaDoAluno = {};
      for (final a in alunos) {
        final id = '${a['id']}';
        nomeAlunos[id] = (a['nome'] ?? a['nome_completo'] ?? 'Sem nome')
            .toString();
        turmaDoAluno[id] = '${a['id_turma']}';
      }

      // aluno id -> resultado (se tiver mais de um, vale o último)
      final Map<String, Map<String, dynamic>> resultadoDoAluno = {};
      for (final r in resultados) {
        resultadoDoAluno['${r['id_aluno']}'] = r;
      }

      // ordena turmas por nome
      turmas.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

      analiseTurmas.clear();

      for (final t in turmas) {
        final idTurma = '${t['id']}';
        final nomeTurma = (t['nome'] ?? 'Turma').toString();

        final List<DesempenhoAluno> lista = [];
        resultadoDoAluno.forEach((idAluno, r) {
          if (turmaDoAluno[idAluno] == idTurma) {
            final notaBruta = r['nota_final'];
            final double nota = notaBruta is num
                ? notaBruta.toDouble()
                : double.tryParse('$notaBruta') ?? 0.0;
            final nivelBruto = r['nivel_saeb'];
            final String nivel =
                (nivelBruto != null && nivelBruto.toString().isNotEmpty)
                ? nivelBruto.toString()
                : _nivelPorNota(nota);
            lista.add(
              DesempenhoAluno(
                nome: nomeAlunos[idAluno] ?? 'Sem nome',
                nota: nota,
                nivel: nivel,
              ),
            );
          }
        });

        // ordena da menor nota para a maior
        lista.sort((a, b) => a.nota.compareTo(b.nota));

        analiseTurmas.add({
          'nome': nomeTurma,
          'piores': lista.take(10).toList(),
          'melhores': lista.reversed.take(10).toList(),
          'total': lista.length,
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
        title: const Text('Análise Detalhada por Turma'),
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
                    '📊 Buscando resultados no Supabase...',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
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
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final t in analiseTurmas) ...[
                  _buildSecao(
                    "TURMA ${t['nome']} — Piores Desempenhos",
                    t['piores'] as List<DesempenhoAluno>,
                    Colors.red,
                    Icons.trending_down,
                  ),
                  const SizedBox(height: 12),
                  _buildSecao(
                    "TURMA ${t['nome']} — Melhores Desempenhos",
                    t['melhores'] as List<DesempenhoAluno>,
                    Colors.green,
                    Icons.trending_up,
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
    );
  }

  Widget _buildSecao(
    String titulo,
    List<DesempenhoAluno> lista,
    Color cor,
    IconData icone,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(fontWeight: FontWeight.bold, color: cor),
                  ),
                ),
              ],
            ),
          ),
          if (lista.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nenhum aluno corrigido nesta turma ainda.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...lista.map(
              (d) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: cor.withOpacity(0.15),
                  child: Text(
                    d.nota.toStringAsFixed(1),
                    style: TextStyle(
                      color: cor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(
                  d.nome,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  d.nivel,
                  style: TextStyle(
                    fontSize: 12,
                    color: _corNivel(d.nivel),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Text(
                  d.nota.toStringAsFixed(2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: cor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
