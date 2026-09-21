import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../context/app_state.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class TelaCorrecaoAberta extends StatefulWidget {
  const TelaCorrecaoAberta({super.key});

  @override
  State<TelaCorrecaoAberta> createState() => _TelaCorrecaoAbertaState();
}

class _TelaCorrecaoAbertaState extends State<TelaCorrecaoAberta> {
  List<Map<String, dynamic>> avaliacoesAbertas = [];
  List<Map<String, dynamic>> turmas = [];
  List<Map<String, dynamic>> alunos = [];
  int? avalId;
  int? turmaId;
  bool carregando = true;
  bool processando = false;

  bool emRevisao = false;
  String _nomeAlunoRevisao = '';
  int? _idAlunoRevisao;
  List<Map<String, dynamic>> _questoesRevisao = [];
  List<Map<String, dynamic>> _sugestoes = [];
  final Map<int, TextEditingController> _notaControllers = {};
  List<String> _ultimosCaminhos = [];
  String _disciplinaAtual = 'Matemática';
  bool _filaQR = false;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    try {
      final supabase = Supabase.instance.client;
      final a = await supabase.from('avaliacoes').select('*').order('id');
      final t = await supabase.from('turmas').select('*').order('nome');
      final abertas = List<Map<String, dynamic>>.from(
        a,
      ).where((av) => '${av['modo_correcao']}' == 'aberta').toList();
      final listaTurmas = List<Map<String, dynamic>>.from(t);
      listaTurmas.sort((x, y) => '${x['nome']}'.compareTo('${y['nome']}'));

      setState(() {
        avaliacoesAbertas = abertas;
        turmas = listaTurmas;
        carregando = false;
      });
    } catch (e) {
      setState(() => carregando = false);
    }
  }

  Future<void> _carregarAlunos() async {
    if (turmaId == null) return;
    setState(() => carregando = true);
    try {
      final supabase = Supabase.instance.client;
      final al = await supabase
          .from('alunos')
          .select('*')
          .eq('id_turma', turmaId!)
          .order('numero_chamada');
      final lista = List<Map<String, dynamic>>.from(al);
      lista.sort(
        (x, y) => ((x['numero_chamada'] as num?)?.toInt() ?? 0).compareTo(
          (y['numero_chamada'] as num?)?.toInt() ?? 0,
        ),
      );
      setState(() {
        alunos = lista;
        carregando = false;
        emRevisao = false;
      });
    } catch (e) {
      setState(() => carregando = false);
    }
  }

  String _montarPrompt(List<Map<String, dynamic>> questoes) {
    final sb = StringBuffer();
    sb.writeln('Você é um professor assistente de $_disciplinaAtual.');
    sb.writeln(
      'Avalie com os critérios, conceitos e vocabulário próprios de $_disciplinaAtual.',
    );
    sb.writeln(
      'As imagens anexas são a prova manuscrita de um aluno (1 ou mais folhas).',
    );
    sb.writeln(
      'As questões estão NUMERADAS e podem estar em folhas diferentes — procure o número de cada questão em TODAS as folhas antes de responder.',
    );
    sb.writeln(
      'Para cada questão: leia TUDO o que o aluno escreveu (contas e rascunhos inclusos), compare com a resposta esperada e dê crédito parcial por etapas corretas.',
    );
    sb.writeln(
      'Se o aluno usou um raciocínio diferente mas possivelmente válido, marque "revisar": true.',
    );
    sb.writeln('');
    sb.writeln('QUESTÕES:');
    for (final q in questoes) {
      sb.writeln(
        '${q['numero']}) Enunciado: ${q['enunciado']} | Resposta esperada: ${q['resposta_esperada']} | Valor: ${q['valor']}',
      );
    }
    sb.writeln('');
    sb.writeln(
      'Responda SOMENTE um array JSON válido (sem markdown), no formato:',
    );
    sb.writeln(
      '[{"numero":1,"transcricao":"...","nota_sugerida":1.5,"justificativa":"...","revisar":false}]',
    );
    sb.writeln('Cada nota_sugerida deve ficar entre 0 e o valor da questão.');
    final comImagem = questoes
        .where((q) => '${q['imagem_url'] ?? ''}'.isNotEmpty)
        .toList();
    if (comImagem.isNotEmpty) {
      sb.writeln('');
      sb.writeln(
        'IMAGENS DE REFERÊNCIA: as primeiras ${comImagem.length} imagem(ns) anexadas são, NA ORDEM, os enunciados visuais das questões ${comImagem.map((q) => q['numero']).join(', ')}.',
      );
      sb.writeln(
        'As demais imagens anexadas são as folhas de resposta do aluno.',
      );
    } else {
      sb.writeln('As imagens anexadas são as folhas de resposta do aluno.');
    }
    sb.writeln('/no_think');
    sb.writeln(
      'Responda IMEDIATAMENTE somente o array JSON, sem nenhum texto antes ou depois.',
    );
    return sb.toString();
  }

  List<Map<String, dynamic>> _parseJson(String texto) {
    final t = texto.trim();
    final i = t.indexOf('[');
    final f = t.lastIndexOf(']');
    if (i == -1 || f == -1 || f <= i) {
      final amostra = t.length > 300 ? t.substring(0, 300) : t;
      throw Exception(
        'A IA não retornou uma lista válida. Ela disse: "$amostra"',
      );
    }
    final arr = jsonDecode(t.substring(i, f + 1)) as List;
    return arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<int>> _baixarImagem(String url) async {
    final r = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception(
        'Não consegui baixar a imagem do enunciado (${r.statusCode}).',
      );
    }
    return r.bodyBytes;
  }

  String _mimeDe(String url) {
    final u = url.toLowerCase();
    if (u.endsWith('.png')) return 'image/png';
    if (u.endsWith('.webp')) return 'image/webp';
    if (u.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<Map<String, int?>> _lerQRDasFolhas(List<String> caminhos) async {
    int? prova;
    int? aluno;
    try {
      final scanner = BarcodeScanner();
      for (final caminho in caminhos) {
        final input = InputImage.fromFilePath(caminho);
        final barcodes = await scanner.processImage(input);
        for (final b in barcodes) {
          final raw = (b.rawValue ?? '').trim();
          if (raw.startsWith('OMRPROVA:')) {
            prova ??= int.tryParse(raw.substring('OMRPROVA:'.length));
          } else if (raw.startsWith('OMRALUNO:')) {
            final partes = raw.split(':');
            if (partes.length >= 3) {
              prova ??= int.tryParse(partes[1]);
              aluno ??= int.tryParse(partes[2]);
            }
          } else if (raw.startsWith('OMRCARD:')) {
            aluno ??= int.tryParse(raw.substring('OMRCARD:'.length));
          }
        }
      }
      await scanner.close();
    } catch (e) {
      // QR é opcional
    }
    return {'prova': prova, 'aluno': aluno};
  }

  // 🗜️ COMPRESSÃO LOCAL: reduz foto de ~3MB pra ~300KB SEM PERDER LEGIBILIDADE
  Future<String> _comprimirImagem(String caminho, int idx) async {
    try {
      final original = await File(caminho).length();
      final dir = await Directory.systemTemp.createTemp('omr_img');
      final alvo = '${dir.path}/comp_$idx.jpg';

      final resultado = await FlutterImageCompress.compressAndGetFile(
        caminho,
        alvo,
        quality: 78,
        minWidth: 1400,
        minHeight: 1400,
        format: CompressFormat.jpeg,
      );

      if (resultado == null) {
        print('⚠️ Compressão retornou vazio, usando original');
        return caminho;
      }

      final novo = await File(resultado.path).length();
      print(
        '🗜️ Folha ${idx + 1}: ${(original / 1024).round()}KB → ${(novo / 1024).round()}KB (economia: ${((1 - novo / original) * 100).toStringAsFixed(0)}%)',
      );
      return resultado.path;
    } catch (e) {
      print('⚠️ Compressão falhou (usando original): $e');
      return caminho;
    }
  }

  // 🚀 Chama a rota do servidor (Gemini seguro no Render)
  Future<List<Map<String, dynamic>>> _chamarServidor(
    List<String> caminhos,
    List<Map<String, dynamic>> questoes,
  ) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final urlServidor = '${appState.ipServidor}/api/corrigir_dissertativa';

    // Monta a lista de imagens (enunciados primeiro, depois as folhas)
    final List<Map<String, String>> imagens = [];
    for (final q in questoes) {
      final url = '${q['imagem_url'] ?? ''}';
      if (url.isNotEmpty) {
        final bytes = await _baixarImagem(url);
        imagens.add({'mime': _mimeDe(url), 'data': base64Encode(bytes)});
      }
    }

    // 🗜️ COMPRIME AS FOTOS DO ALUNO antes de codificar em base64
    for (int i = 0; i < caminhos.length; i++) {
      final caminhoComprimido = await _comprimirImagem(caminhos[i], i);
      final bytes = await File(caminhoComprimido).readAsBytes();
      imagens.add({'mime': 'image/jpeg', 'data': base64Encode(bytes)});
    }

    final corpo = jsonEncode({
      'prompt': _montarPrompt(questoes),
      'imagens': imagens,
    });

    print('🤖 [APP] Enviando ${imagens.length} imagem(ns) pro servidor...');

    final response = await http
        .post(
          Uri.parse(urlServidor),
          headers: {'Content-Type': 'application/json'},
          body: corpo,
        )
        .timeout(const Duration(seconds: 180));

    if (response.statusCode == 429) {
      throw Exception(
        'Servidor com cota excedida. Aguarde 1 minuto e tente novamente.',
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Servidor erro ${response.statusCode}: ${response.body}');
    }

    final jsonResp = jsonDecode(response.body);
    if (jsonResp['sucesso'] != true) {
      throw Exception('Servidor: ${jsonResp['erro'] ?? 'erro desconhecido'}');
    }

    print('✅ [APP] Resposta do servidor recebida!');
    return _parseJson(jsonResp['texto'] as String);
  }

  Future<void> _prepararRevisao(
    List<Map<String, dynamic>> questoes,
    List<Map<String, dynamic>> sugestoes,
  ) async {
    for (final c in _notaControllers.values) c.dispose();
    _notaControllers.clear();
    for (final s in sugestoes) {
      final n = (s['numero'] as num?)?.toInt() ?? 0;
      final nota = (s['nota_sugerida'] as num?)?.toDouble() ?? 0;
      _notaControllers[n] = TextEditingController(
        text: nota.toString().replaceAll('.', ','),
      );
    }
    setState(() {
      _questoesRevisao = questoes;
      _sugestoes = sugestoes;
      emRevisao = true;
      processando = false;
    });
  }

  Future<void> _corrigirAluno(Map<String, dynamic> aluno) async {
    setState(() => processando = true);
    try {
      final supabase = Supabase.instance.client;
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 3,
        isGalleryImport: true,
      );
      final scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      if (result.images == null || result.images!.isEmpty) {
        setState(() {
          processando = false;
          _filaQR = false;
        });
        return;
      }
      _ultimosCaminhos = List<String>.from(result.images!);

      final qr = await _lerQRDasFolhas(_ultimosCaminhos);
      final idProvaQR = qr['prova'];
      final idAlunoQR = qr['aluno'];

      if (idProvaQR != null && idProvaQR != avalId) {
        final rAv = await supabase
            .from('avaliacoes')
            .select('nome')
            .eq('id', idProvaQR)
            .maybeSingle();
        final nomeAv = rAv == null ? 'ID $idProvaQR' : '${rAv['nome']}';
        if (mounted) {
          setState(() => avalId = idProvaQR);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🔲 Prova reconhecida pelo QR: $nomeAv'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }

      Map<String, dynamic> alunoEfetivo = aluno;
      if (idAlunoQR != null && idAlunoQR != (aluno['id'] as int?)) {
        final rAl = await supabase
            .from('alunos')
            .select('*')
            .eq('id', idAlunoQR)
            .maybeSingle();
        if (rAl != null) {
          alunoEfetivo = Map<String, dynamic>.from(rAl);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '🔲 Aluno reconhecido pelo QR: ${alunoEfetivo['nome_completo']}',
                ),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
      }
      final idAlunoEfetivo = alunoEfetivo['id'] as int?;
      if (idAlunoEfetivo == null || idAlunoEfetivo == -1) {
        throw Exception(
          'QR do aluno não encontrado. Toque no aluno na lista ou use folhas com QR do aluno.',
        );
      }

      final idAvalEfetivo = idProvaQR ?? avalId;
      if (idAvalEfetivo == null) {
        throw Exception('Escolha a prova acima — ou use folhas com QR.');
      }

      final rDisc = await supabase
          .from('avaliacoes')
          .select('disciplina')
          .eq('id', idAvalEfetivo)
          .maybeSingle();
      _disciplinaAtual =
          (rDisc != null && '${rDisc['disciplina'] ?? ''}'.isNotEmpty)
          ? '${rDisc['disciplina']}'
          : 'Matemática';

      final qs = await supabase
          .from('questoes_abertas')
          .select('*')
          .eq('id_avaliacao', idAvalEfetivo)
          .order('numero');
      final questoes = List<Map<String, dynamic>>.from(qs);
      if (questoes.isEmpty)
        throw Exception('Esta prova não tem questões cadastradas.');

      // 🚀 Chamada ÚNICA: servidor cuida do Gemini
      final sugestoes = await _chamarServidor(_ultimosCaminhos, questoes);
      setState(() {
        _nomeAlunoRevisao = '${alunoEfetivo['nome_completo']}';
        _idAlunoRevisao = alunoEfetivo['id'] as int;
      });
      await _prepararRevisao(questoes, sugestoes);
    } catch (e) {
      setState(() => processando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
        if (_filaQR) {
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted && _filaQR) {
              _corrigirAluno({'id': -1, 'nome_completo': '(QR)'});
            }
          });
        }
      }
    }
  }

  void _corrigirPorQR() {
    setState(() => _filaQR = true);
    _corrigirAluno({'id': -1, 'nome_completo': '(QR)'});
  }

  Future<void> _recorrigir() async {
    if (_ultimosCaminhos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Nenhuma foto guardada. Use Foto.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    setState(() => processando = true);
    try {
      final supabase = Supabase.instance.client;
      final qs = await supabase
          .from('questoes_abertas')
          .select('*')
          .eq('id_avaliacao', avalId!)
          .order('numero');
      final questoes = List<Map<String, dynamic>>.from(qs);
      final rDisc = await supabase
          .from('avaliacoes')
          .select('disciplina')
          .eq('id', avalId!)
          .maybeSingle();
      _disciplinaAtual =
          (rDisc != null && '${rDisc['disciplina'] ?? ''}'.isNotEmpty)
          ? '${rDisc['disciplina']}'
          : 'Matemática';
      final sugestoes = await _chamarServidor(_ultimosCaminhos, questoes);
      await _prepararRevisao(questoes, sugestoes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 Correção atualizada!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() => processando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _refotografar() {
    final aluno = <String, dynamic>{
      'id': _idAlunoRevisao,
      'nome_completo': _nomeAlunoRevisao,
    };
    setState(() => emRevisao = false);
    _corrigirAluno(aluno);
  }

  Future<void> _editarRegras() async {
    if (avalId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Escolha a prova primeiro!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final supabase = Supabase.instance.client;
    final qs = await supabase
        .from('questoes_abertas')
        .select('*')
        .eq('id_avaliacao', avalId!)
        .order('numero');
    final questoes = List<Map<String, dynamic>>.from(qs);
    if (questoes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Prova sem questões.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final Map<int, TextEditingController> respCtl = {};
    final Map<int, TextEditingController> valCtl = {};
    for (final q in questoes) {
      respCtl[q['id'] as int] = TextEditingController(
        text: '${q['resposta_esperada']}',
      );
      valCtl[q['id'] as int] = TextEditingController(
        text: '${q['valor']}'.replaceAll('.', ','),
      );
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                '✏️ Regras da prova',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ajuste os critérios e valores. Vale para as próximas correções!',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final q in questoes)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Questão ${q['numero']}: ${q['enunciado']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: respCtl[q['id'] as int],
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Resposta esperada / critério',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: valCtl[q['id'] as int],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Valor da questão',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      for (final q in questoes) {
                        final id = q['id'] as int;
                        await supabase
                            .from('questoes_abertas')
                            .update({
                              'resposta_esperada': respCtl[id]!.text.trim(),
                              'valor':
                                  double.tryParse(
                                    valCtl[id]!.text.trim().replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  ) ??
                                  (q['valor'] as num).toDouble(),
                            })
                            .eq('id', id);
                      }
                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '✅ Regras salvas! Use 🔄 Recorrigir para aplicar nesta prova.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'SALVAR REGRAS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nivelNormal(double nota) {
    if (nota >= 8) return 'Avançado';
    if (nota >= 6) return 'Adequado';
    if (nota >= 4) return 'Básico';
    return 'Abaixo do Básico';
  }

  Future<void> _confirmar() async {
    try {
      double somaNotas = 0;
      double somaValores = 0;
      final resumo = StringBuffer();

      for (final q in _questoesRevisao) {
        final n = (q['numero'] as num?)?.toInt() ?? 0;
        final valor = (q['valor'] as num?)?.toDouble() ?? 2.0;
        somaValores += valor;
        double nota =
            double.tryParse(
              (_notaControllers[n]?.text ?? '').trim().replaceAll(',', '.'),
            ) ??
            0;
        if (nota < 0) nota = 0;
        if (nota > valor) nota = valor;
        somaNotas += nota;
        resumo.write(
          'Q$n: ${nota.toStringAsFixed(1)}/${valor.toStringAsFixed(1)}; ',
        );
      }

      final nota10 = somaValores > 0 ? (somaNotas * 10 / somaValores) : 0.0;

      final supabase = Supabase.instance.client;
      await supabase
          .from('resultados')
          .delete()
          .eq('id_aluno', _idAlunoRevisao!)
          .eq('id_avaliacao', avalId!);
      await supabase.from('resultados').insert({
        'id_aluno': _idAlunoRevisao,
        'id_avaliacao': avalId,
        'nota_bruta': nota10,
        'nota_final': nota10.roundToDouble(),
        'nivel_saeb': _nivelNormal(nota10),
        'devolutiva': 'Correção assistida por IA (prova aberta). $resumo',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Nota ${nota10.toStringAsFixed(1)} de $_nomeAlunoRevisao salva!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => emRevisao = false);
        if (_filaQR) {
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted && _filaQR) {
              _corrigirAluno({'id': -1, 'nome_completo': '(QR)'});
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildSelecaoProvaETurma() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<int>(
            isExpanded: true,
            value: avalId,
            decoration: const InputDecoration(
              labelText: 'Prova aberta',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final av in avaliacoesAbertas)
                DropdownMenuItem(
                  value: av['id'] as int,
                  child: Text('${av['nome']}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => avalId = v),
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
              _carregarAlunos();
            },
          ),
          Row(
            children: [
              if (avalId != null)
                Expanded(
                  child: TextButton.icon(
                    onPressed: _editarRegras,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('✏️ Regras da prova'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                    ),
                  ),
                ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _corrigirPorQR,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('🔲 Escanear com QR do aluno'),
                  style: TextButton.styleFrom(foregroundColor: Colors.teal),
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🤖 IA processada no servidor (Gemini)',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaAlunos() {
    if (alunos.isEmpty)
      return const Center(child: Text('Escolha a prova e a turma acima. 👆'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: alunos.length,
      itemBuilder: (context, index) {
        final al = alunos[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.deepOrange,
              child: Icon(Icons.camera_alt, color: Colors.white),
            ),
            title: Text(
              '${al['numero_chamada']}. ${al['nome_completo']}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Toque para fotografar a prova 📷'),
            onTap: () => _corrigirAluno(al),
          ),
        );
      },
    );
  }

  Widget _buildRevisaoHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.rate_review, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Revisão: $_nomeAlunoRevisao',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevisaoLista() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _questoesRevisao.length,
      itemBuilder: (context, index) {
        final q = _questoesRevisao[index];
        final n = (q['numero'] as num?)?.toInt() ?? 0;
        final sug = _sugestoes
            .where((s) => (s['numero'] as num?)?.toInt() == n)
            .toList();
        final transcricao = sug.isNotEmpty
            ? '${sug.first['transcricao']}'
            : '—';
        final justificativa = sug.isNotEmpty
            ? '${sug.first['justificativa']}'
            : '';
        final revisar = sug.isNotEmpty && sug.first['revisar'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Questão $n',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      'Valor: ${(q['valor'] as num?)?.toDouble().toStringAsFixed(1)}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${q['enunciado']}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  '✍️ A IA leu: "$transcricao"',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '💡 $justificativa',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (revisar)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '⚠️ Raciocínio diferente — confira, professor!',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Nota: ',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _notaControllers[n],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBotoesAcao() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _editarRegras,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Regras', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.deepOrange,
                side: BorderSide(color: Colors.deepOrange.shade300),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _recorrigir,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Recorrigir', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _refotografar,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Foto', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.deepOrange,
                side: BorderSide(color: Colors.deepOrange.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoConfirmar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _confirmar,
          icon: const Icon(Icons.save),
          label: const Text(
            'CONFIRMAR E SALVAR NOTA',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayProcessando() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: const Center(
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.deepOrange),
                SizedBox(height: 16),
                Text(
                  '🤖 A IA está lendo a prova...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 6),
                Text(
                  'Isso pode levar até 1 minuto.\nNão feche o app!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Correção de Prova Aberta'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          carregando
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (!emRevisao) _buildSelecaoProvaETurma(),
                    if (!emRevisao) Expanded(child: _buildListaAlunos()),
                    if (emRevisao) _buildRevisaoHeader(),
                    if (emRevisao) Expanded(child: _buildRevisaoLista()),
                    if (emRevisao) _buildBotoesAcao(),
                    if (emRevisao) const SizedBox(height: 8),
                    if (emRevisao) _buildBotaoConfirmar(),
                  ],
                ),
          if (processando) _buildOverlayProcessando(),
        ],
      ),
      floatingActionButton: emRevisao
          ? FloatingActionButton.extended(
              onPressed: () => setState(() {
                emRevisao = false;
                _filaQR = false;
              }),
              backgroundColor: _filaQR ? Colors.red : Colors.grey,
              foregroundColor: Colors.white,
              icon: Icon(_filaQR ? Icons.stop : Icons.arrow_back),
              label: Text(_filaQR ? 'PARAR FILA' : 'Voltar'),
            )
          : null,
    );
  }
}
