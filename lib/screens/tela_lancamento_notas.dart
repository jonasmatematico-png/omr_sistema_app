import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TelaLancamentoNotas extends StatefulWidget {
  const TelaLancamentoNotas({super.key});

  @override
  State<TelaLancamentoNotas> createState() => _TelaLancamentoNotasState();
}

class _TelaLancamentoNotasState extends State<TelaLancamentoNotas> {
  List<Map<String, dynamic>> avaliacoes = [];
  List<Map<String, dynamic>> turmas = [];
  List<Map<String, dynamic>> alunos = [];
  final Map<int, TextEditingController> _controllers = {};

  Map<String, dynamic>? avaliacaoSel;
  Map<String, dynamic>? turmaSel;
  bool carregando = true;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarBases();
  }

  Future<void> _carregarBases() async {
    try {
      final supabase = Supabase.instance.client;
      final a = await supabase.from('avaliacoes').select('*').order('id');
      final t = await supabase.from('turmas').select('*').order('nome');
      setState(() {
        avaliacoes = List<Map<String, dynamic>>.from(a);
        turmas = List<Map<String, dynamic>>.from(t);
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

  Future<void> _carregarAlunos() async {
    if (avaliacaoSel == null || turmaSel == null) return;
    setState(() => carregando = true);
    try {
      final supabase = Supabase.instance.client;
      final a = await supabase
          .from('alunos')
          .select('*')
          .eq('id_turma', turmaSel!['id'])
          .order('numero_chamada');
      final r = await supabase
          .from('resultados')
          .select('id_aluno, nota_bruta')
          .eq('id_avaliacao', avaliacaoSel!['id']);

      final Map<int, double> notasExistentes = {};
      for (final res in r) {
        final nb = res['nota_bruta'];
        if (nb is num) notasExistentes[res['id_aluno'] as int] = nb.toDouble();
      }

      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();

      setState(() {
        alunos = List<Map<String, dynamic>>.from(a);
        for (final al in alunos) {
          final id = al['id'] as int;
          final nota = notasExistentes[id];
          _controllers[id] = TextEditingController(
            text: nota == null ? '' : nota.toString().replaceAll('.', ','),
          );
        }
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

  // 🚨 PROVAS NORMAIS: cortes clássicos (0 a 10)
  String _nivelNormal(double nota) {
    if (nota >= 8) return 'Avançado';
    if (nota >= 6) return 'Adequado';
    if (nota >= 4) return 'Básico';
    return 'Abaixo do Básico';
  }

  Future<void> _salvarTudo() async {
    if (avaliacaoSel == null) return;
    setState(() => salvando = true);
    try {
      final supabase = Supabase.instance.client;
      final idAval = avaliacaoSel!['id'];
      int salvos = 0;

      for (final al in alunos) {
        final id = al['id'] as int;
        final texto = (_controllers[id]?.text ?? '').trim().replaceAll(
          ',',
          '.',
        );
        if (texto.isEmpty) continue;
        double nota = double.tryParse(texto) ?? 0;
        if (nota < 0) nota = 0;
        if (nota > 10) nota = 10;

        // garante uma única linha por aluno+avaliação
        await supabase
            .from('resultados')
            .delete()
            .eq('id_aluno', id)
            .eq('id_avaliacao', idAval);
        await supabase.from('resultados').insert({
          'id_aluno': id,
          'id_avaliacao': idAval,
          'nota_bruta': nota,
          'nota_final': nota.roundToDouble(),
          'nivel_saeb': _nivelNormal(nota),
          'devolutiva': 'Nota lançada manualmente pelo professor.',
        });
        salvos++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $salvos nota(s) salva(s) com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lançar Notas Manuais'),
        backgroundColor: Colors.deepOrange,
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
                      DropdownButtonFormField<Map<String, dynamic>>(
                        isExpanded: true,
                        value: avaliacaoSel,
                        decoration: const InputDecoration(
                          labelText: 'Avaliação',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final a in avaliacoes)
                            DropdownMenuItem(
                              value: a,
                              child: Text(
                                '${a['nome']} • ${a['bimestre'] ?? 2}º bim',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => avaliacaoSel = v);
                          _carregarAlunos();
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        isExpanded: true,
                        value: turmaSel,
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
                          setState(() => turmaSel = v);
                          _carregarAlunos();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: alunos.isEmpty
                      ? const Center(
                          child: Text(
                            'Escolha a avaliação e a turma acima. 👆',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: alunos.length,
                          itemBuilder: (context, index) {
                            final al = alunos[index];
                            final id = al['id'] as int;
                            return Card(
                              child: ListTile(
                                title: Text(
                                  '${al['numero_chamada']}. ${al['nome_completo']}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                trailing: SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: _controllers[id],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      hintText: '0-10',
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (alunos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: salvando ? null : _salvarTudo,
                        icon: salvando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text(
                          'SALVAR TODAS AS NOTAS',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
