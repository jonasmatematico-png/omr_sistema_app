import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aluno_model.dart';
import '../models/resultado_model.dart';

class TelaPerfilAluno extends StatefulWidget {
  final Aluno aluno;
  const TelaPerfilAluno({super.key, required this.aluno});

  @override
  State<TelaPerfilAluno> createState() => _TelaPerfilAlunoState();
}

class _TelaPerfilAlunoState extends State<TelaPerfilAluno> {
  bool carregando = true;

  int acertosBasico = 0, totalBasico = 0;
  int acertosInter = 0, totalInter = 0;
  int acertosAvanc = 0, totalAvanc = 0;
  List<String> descritoresErrados = [];

  @override
  void initState() {
    super.initState();
    _carregarPerfil();
  }

  Future<void> _carregarPerfil() async {
    try {
      final supabase = Supabase.instance.client;

      // 🚨 NOVA ESTRATÉGIA: Duas buscas separadas + cruzamento no Dart
      // (Muito mais robusto que o JOIN do Supabase)

      // 1. Pega as respostas do aluno
      final respostas = await supabase
          .from('respostas')
          .select('*')
          .eq('id_aluno', widget.aluno.id);

      print("🔍 [Perfil] Respostas encontradas no banco: ${respostas.length}");

      if (respostas.isEmpty) {
        print("⚠️ [Perfil] Aluno sem respostas registradas na tabela.");
        setState(() => carregando = false);
        return;
      }

      // 2. Pega o ID da avaliação (assumindo que todas as respostas são da mesma prova)
      final idAvaliacao = respostas.first['id_avaliacao'];

      // 3. Pega as questões dessa avaliação para saber o nível e descritor
      final questoes = await supabase
          .from('questoes')
          .select('*')
          .eq('id_avaliacao', idAvaliacao);

      print(
        "🔍 [Perfil] Questões da avaliação $idAvaliacao: ${questoes.length}",
      );

      // 4. Cria um mapa de acesso rápido (salva por ID e por NÚMERO, para garantir)
      final Map<dynamic, Map> mapaQuestoes = {};
      for (var q in questoes) {
        mapaQuestoes[q['id']] = q;
        mapaQuestoes[q['numero']] = q;
      }

      // 5. Cruza os dados: para cada resposta, acha a questão correspondente
      for (var r in respostas) {
        bool acertou = r['correta'] == true;
        dynamic chaveQ = r['id_questao'];

        Map? q = mapaQuestoes[chaveQ];

        if (q == null) {
          print("⚠️ [Perfil] Questão $chaveQ não encontrada no mapa!");
          continue;
        }

        String nivel = (q['nivel'] ?? '').toString().toLowerCase();
        String desc = (q['descritor'] ?? '').toString().trim();
        if (desc.isEmpty) desc = 'Q${q['numero']}';

        if (nivel.contains('básic') || nivel.contains('basic')) {
          totalBasico++;
          if (acertou) acertosBasico++;
        } else if (nivel.contains('inter')) {
          totalInter++;
          if (acertou) acertosInter++;
        } else if (nivel.contains('avanç')) {
          totalAvanc++;
          if (acertou) acertosAvanc++;
        }

        if (!acertou && !descritoresErrados.contains(desc)) {
          descritoresErrados.add(desc);
        }
      }

      print("✅ [Perfil] Totais calculados:");
      print("   Básico: $acertosBasico/$totalBasico");
      print("   Intermediário: $acertosInter/$totalInter");
      print("   Avançado: $acertosAvanc/$totalAvanc");
      print("   Descritores errados: $descritoresErrados");

      setState(() => carregando = false);
    } catch (e) {
      print("❌ [Perfil] Erro geral ao carregar: $e");
      setState(() => carregando = false);
    }
  }

  Color _corNivel(String nivel) {
    if (nivel.contains('Avanç')) return Colors.green;
    if (nivel.contains('Adequado')) return Colors.blue;
    if (nivel.contains('Básico')) return Colors.orange;
    return Colors.red;
  }

  String _gerarRecomendacao() {
    List<String> pontosFracos = [];
    if (totalBasico > 0 && (acertosBasico / totalBasico) < 0.5)
      pontosFracos.add('Básico');
    if (totalInter > 0 && (acertosInter / totalInter) < 0.5)
      pontosFracos.add('Intermediário');
    if (totalAvanc > 0 && (acertosAvanc / totalAvanc) < 0.5)
      pontosFracos.add('Avançado');

    if (pontosFracos.isEmpty && descritoresErrados.isEmpty) {
      return 'Excelente desempenho! O aluno demonstra domínio consistente em todos os níveis de complexidade avaliados.';
    } else if (pontosFracos.isEmpty) {
      return 'Bom desempenho geral! Atenção apenas aos descritores específicos listados abaixo para um refinamento final.';
    } else {
      return 'Recomenda-se reforço pedagógico focado em questões de nível ${pontosFracos.join(' e ')}. '
          'Atenção especial aos descritores listados abaixo, que apresentaram maior índice de erro.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    final nivelAtual = Resultado.calcularNivelSaeb(aluno.notaExata ?? 0);
    final corNivel = _corNivel(nivelAtual);

    return Scaffold(
      appBar: AppBar(
        title: Text('Perfil: ${aluno.nome.split(' ').first}'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Text(
                            aluno.nome,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Column(
                                children: [
                                  const Text(
                                    'Nota Final',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  Text(
                                    '${aluno.notaFinal ?? 0}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.grey.shade300,
                              ),
                              Column(
                                children: [
                                  const Text(
                                    'Nível SAEB',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: corNivel.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: corNivel),
                                    ),
                                    child: Text(
                                      nivelAtual,
                                      style: TextStyle(
                                        color: corNivel,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
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
                    'Desempenho por Nível de Complexidade',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildNivelBar(
                    'Básico',
                    acertosBasico,
                    totalBasico,
                    Colors.orange,
                  ),
                  _buildNivelBar(
                    'Intermediário',
                    acertosInter,
                    totalInter,
                    Colors.blue,
                  ),
                  _buildNivelBar(
                    'Avançado',
                    acertosAvanc,
                    totalAvanc,
                    Colors.green,
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Descritores / Questões para Reforço',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: descritoresErrados.isEmpty
                          ? const Text(
                              '🎉 Nenhum erro registrado! Desempenho perfeito.',
                              style: TextStyle(color: Colors.green),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: descritoresErrados.map((desc) {
                                return Chip(
                                  label: Text(
                                    desc,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Card(
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: Colors.amber.shade800,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Recomendação Pedagógica',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _gerarRecomendacao(),
                            style: const TextStyle(height: 1.5, fontSize: 14),
                            textAlign: TextAlign.justify,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildNivelBar(String nome, int acertos, int total, Color cor) {
    double pct = total > 0 ? acertos / total : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              nome,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(cor),
              minHeight: 10,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 50,
            child: Text(
              '$acertos/$total',
              style: TextStyle(fontWeight: FontWeight.bold, color: cor),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
