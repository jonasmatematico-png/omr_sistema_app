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
import 'package:url_launcher/url_launcher.dart';

class TelaCorrecaoLote extends StatefulWidget {
  const TelaCorrecaoLote({super.key});

  @override
  State<TelaCorrecaoLote> createState() => _TelaCorrecaoLoteState();
}

class _TelaCorrecaoLoteState extends State<TelaCorrecaoLote> {
  // ===== Dados básicos =====
  List<Map<String, dynamic>> avaliacoesAbertas = [];
  List<Map<String, dynamic>> turmas = [];
  int? avalId;
  int? turmaId;
  bool carregando = true;
  String _disciplinaAtual = 'Matemática';

  // ===== Controle das 4 ETAPAS =====
  // 1 = fotografar | 2 = conferir fila | 3 = corrigindo | 4 = revisar tudo
  int _etapa = 1;
  bool _fotografando = false;
  bool _enviando = false;

  // ===== Fila de provas (a "cesta") =====
  List<Map<String, dynamic>> _fila = [];
  final TextEditingController _metaCtl = TextEditingController();

  // ===== Regras da prova (carregadas 1 vez) =====
  List<Map<String, dynamic>> _questoes = [];
  double _somaValores = 0;
  List<Map<String, String>> _imgsEnunciado = [];
  List<int> _numsEnunciado = [];

  // ===== Controllers de nota (pra revisão em lote) =====
  final Map<int, Map<int, TextEditingController>> _notaControllers = {};

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  @override
  void dispose() {
    // Limpa todos os controllers ao sair
    for (final map in _notaControllers.values) {
      for (final controller in map.values) {
        controller.dispose();
      }
    }
    _metaCtl.dispose();
    super.dispose();
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

  Future<String> _comprimirImagem(String caminho, int idx) async {
    try {
      final dir = await Directory.systemTemp.createTemp('omr_lote');
      final alvo =
          '${dir.path}/comp_${DateTime.now().millisecondsSinceEpoch}_$idx.jpg';
      final resultado = await FlutterImageCompress.compressAndGetFile(
        caminho,
        alvo,
        quality: 78,
        minWidth: 1400,
        minHeight: 1400,
        format: CompressFormat.jpeg,
      );
      return resultado?.path ?? caminho;
    } catch (e) {
      return caminho;
    }
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
    } catch (e) {}
    return {'prova': prova, 'aluno': aluno};
  }

  String _mimeDe(String url) {
    final u = url.toLowerCase();
    if (u.endsWith('.png')) return 'image/png';
    if (u.endsWith('.webp')) return 'image/webp';
    if (u.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _montarPrompt() {
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
    for (final q in _questoes) {
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
    if (_imgsEnunciado.isNotEmpty) {
      sb.writeln('');
      sb.writeln(
        'IMAGENS DE REFERÊNCIA: as primeiras ${_imgsEnunciado.length} imagem(ns) anexadas são, NA ORDEM, os enunciados visuais das questões ${_numsEnunciado.join(', ')}.',
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

  List<Map<String, dynamic>> _parseSugestoes(String texto) {
    try {
      final t = texto.trim();
      final i = t.indexOf('[');
      final f = t.lastIndexOf(']');
      if (i == -1 || f == -1 || f <= i) return [];
      final arr = jsonDecode(t.substring(i, f + 1)) as List;
      return arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  double _somaNotasEditadas(int idxFila) {
    final controllers = _notaControllers[idxFila];
    if (controllers == null) return 0;
    double soma = 0;
    for (final entry in controllers.entries) {
      final nota = double.tryParse(entry.value.text.replaceAll(',', '.')) ?? 0;
      soma += nota;
    }
    return soma;
  }

  Future<bool> _prepararProva() async {
    try {
      final supabase = Supabase.instance.client;
      final rDisc = await supabase
          .from('avaliacoes')
          .select('disciplina')
          .eq('id', avalId!)
          .maybeSingle();
      _disciplinaAtual =
          (rDisc != null && '${rDisc['disciplina'] ?? ''}'.isNotEmpty)
          ? '${rDisc['disciplina']}'
          : 'Matemática';

      final qs = await supabase
          .from('questoes_abertas')
          .select('*')
          .eq('id_avaliacao', avalId!)
          .order('numero');
      _questoes = List<Map<String, dynamic>>.from(qs);
      if (_questoes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Esta prova não tem questões cadastradas!'),
            ),
          );
        }
        return false;
      }

      _somaValores = 0;
      for (final q in _questoes) {
        _somaValores += (q['valor'] as num?)?.toDouble() ?? 0;
      }

      _imgsEnunciado = [];
      _numsEnunciado = [];
      for (final q in _questoes) {
        final url = '${q['imagem_url'] ?? ''}';
        if (url.isEmpty) continue;
        try {
          final r = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (r.statusCode == 200) {
            _imgsEnunciado.add({
              'mime': _mimeDe(url),
              'data': base64Encode(r.bodyBytes),
            });
            _numsEnunciado.add((q['numero'] as num?)?.toInt() ?? 0);
          }
        } catch (e) {}
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Erro ao preparar: $e')));
      }
      return false;
    }
  }

  Future<void> _iniciarFotografia() async {
    if (avalId == null || turmaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Escolha a prova e a turma primeiro!')),
      );
      return;
    }
    setState(() => carregando = true);
    final ok = await _prepararProva();
    setState(() => carregando = false);
    if (!ok) return;

    setState(() {
      _etapa = 1;
      _fotografando = true;
    });
    _loopFotos();
  }

  Future<void> _loopFotos() async {
    while (_fotografando && mounted) {
      final meta = int.tryParse(_metaCtl.text.trim());
      if (meta != null && meta > 0 && _fila.length >= meta) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🎯 Meta de $meta provas atingida!')),
          );
        }
        break;
      }

      final caminhos = await _abrirScanner();
      if (caminhos == null) break;
      await _adicionarNaFila(caminhos);
    }
    if (mounted) {
      setState(() {
        _fotografando = false;
        _etapa = 2;
      });
    }
  }

  Future<List<String>?> _abrirScanner() async {
    try {
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 3,
        isGalleryImport: true,
      );
      final scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      if (result.images == null || result.images!.isEmpty) return null;
      return List<String>.from(result.images!);
    } catch (e) {
      return null;
    }
  }

  Future<void> _adicionarNaFila(List<String> caminhos) async {
    final List<String> comp = [];
    for (int i = 0; i < caminhos.length; i++) {
      comp.add(await _comprimirImagem(caminhos[i], i));
    }

    final qr = await _lerQRDasFolhas(comp);
    int? idAluno;
    String nomeAluno = '';
    if (qr['aluno'] != null) {
      try {
        final supabase = Supabase.instance.client;
        final rAl = await supabase
            .from('alunos')
            .select('*')
            .eq('id', qr['aluno']!)
            .maybeSingle();
        if (rAl != null) {
          idAluno = rAl['id'] as int;
          nomeAluno = '${rAl['nome_completo'] ?? rAl['nome'] ?? 'Aluno'}';
        }
      } catch (e) {}
    }

    if (mounted) {
      setState(() {
        _fila.add({
          'id_aluno': idAluno,
          'nome_aluno': nomeAluno,
          'caminhos': comp,
          'folhas': comp.length,
          'status': 'fila',
        });
      });
    }
  }

  void _pararFotografia() {
    setState(() => _fotografando = false);
  }

  void _removerDaFila(int idx) {
    setState(() => _fila.removeAt(idx));
  }

  Future<void> _escolherAlunoManual(int idxFila) async {
    try {
      final supabase = Supabase.instance.client;
      final r = await supabase
          .from('alunos')
          .select('*')
          .eq('id_turma', turmaId!)
          .order('numero_chamada');
      final lista = List<Map<String, dynamic>>.from(r);

      final escolhido = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('👤 Escolha o aluno desta prova'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: lista.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(
                  '${lista[i]['numero_chamada']}. ${lista[i]['nome_completo']}',
                ),
                onTap: () => Navigator.pop(ctx, lista[i]),
              ),
            ),
          ),
        ),
      );

      if (escolhido != null && mounted) {
        setState(() {
          _fila[idxFila]['id_aluno'] = escolhido['id'];
          _fila[idxFila]['nome_aluno'] = '${escolhido['nome_completo']}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  Future<void> _enviarTudo() async {
    final pendentes = _fila.where((f) => f['status'] == 'fila').toList();
    if (pendentes.isEmpty || _enviando) return;

    final semAluno = pendentes.where((f) => f['id_aluno'] == null).toList();
    if (semAluno.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Há provas SEM aluno! Toque nelas para escolher o aluno ou remova-as.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _etapa = 3;
      _enviando = true;
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final url = '${appState.ipServidor}/api/corrigir_lote';
    const int TAM_BLOCO = 4;

    for (int i = 0; i < pendentes.length; i += TAM_BLOCO) {
      final fim = (i + TAM_BLOCO > pendentes.length)
          ? pendentes.length
          : i + TAM_BLOCO;
      final grupo = pendentes.sublist(i, fim);

      if (!mounted) return;
      setState(() {
        for (final f in grupo) {
          f['status'] = 'enviando';
        }
      });

      final List<Map<String, dynamic>> provas = [];
      for (final f in grupo) {
        final List<Map<String, String>> imagens =
            List<Map<String, String>>.from(_imgsEnunciado);
        for (final c in (f['caminhos'] as List<String>)) {
          try {
            final bytes = await File(c).readAsBytes();
            imagens.add({'mime': 'image/jpeg', 'data': base64Encode(bytes)});
          } catch (e) {}
        }
        provas.add({
          'id_aluno': f['id_aluno'],
          'nome_aluno': f['nome_aluno'],
          'prompt': _montarPrompt(),
          'imagens': imagens,
        });
      }

      try {
        final resp = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'provas': provas}),
            )
            .timeout(const Duration(seconds: 300));

        if (resp.statusCode == 200) {
          final jr = jsonDecode(resp.body);
          final resultados = List<Map<String, dynamic>>.from(
            jr['resultados'] ?? [],
          );
          if (mounted) {
            setState(() {
              for (final r in resultados) {
                final idx = _fila.indexWhere(
                  (f) => f['id_aluno'] == r['id_aluno'],
                );
                if (idx < 0) continue;
                if (r['sucesso'] == true) {
                  _fila[idx]['status'] = 'sucesso';
                  _fila[idx]['texto'] = r['texto'];
                  _fila[idx]['sugestoes'] = _parseSugestoes('${r['texto']}');
                  _fila[idx]['modelo'] = r['modelo'];
                  _fila[idx]['chave'] = r['chave_usada'];

                  // Cria controllers pra revisão
                  _notaControllers[idx] = {};
                  final sugs =
                      _fila[idx]['sugestoes'] as List<Map<String, dynamic>>;
                  for (final s in sugs) {
                    final numero = (s['numero'] as num?)?.toInt() ?? 0;
                    final nota = (s['nota_sugerida'] as num?)?.toDouble() ?? 0;
                    _notaControllers[idx]![numero] = TextEditingController(
                      text: nota.toString().replaceAll('.', ','),
                    );
                  }
                } else {
                  _fila[idx]['status'] = 'falha';
                  _fila[idx]['erro'] = '${r['erro']}';
                }
              }
            });
          }
        } else {
          if (mounted) {
            setState(() {
              for (final f in grupo) {
                f['status'] = 'falha';
                f['erro'] = 'Servidor respondeu ${resp.statusCode}';
              }
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            for (final f in grupo) {
              f['status'] = 'falha';
              f['erro'] = '$e';
            }
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _enviando = false;
        _etapa = 4; // Vai pra REVISÃO!
      });
      final ok = _fila.where((f) => f['status'] == 'sucesso').length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🏁 Correção concluída: $ok de ${_fila.length} prontas pra revisão!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _reenviarFalhas() async {
    setState(() {
      _etapa = 3;
      for (final f in _fila) {
        if (f['status'] == 'falha') f['status'] = 'fila';
      }
    });
    await _enviarTudo();
  }

  Future<void> _salvarNotas() async {
    try {
      final supabase = Supabase.instance.client;
      int salvas = 0;
      for (int i = 0; i < _fila.length; i++) {
        final f = _fila[i];
        if (f['status'] != 'sucesso') continue;

        final soma = _somaNotasEditadas(i);
        double nota10 = _somaValores > 0 ? (soma * 10 / _somaValores) : soma;
        if (nota10 < 0) nota10 = 0;
        if (nota10 > 10) nota10 = 10;

        String nivel = 'Abaixo do Básico';
        if (nota10 >= 8)
          nivel = 'Avançado';
        else if (nota10 >= 6)
          nivel = 'Adequado';
        else if (nota10 >= 4)
          nivel = 'Básico';

        final resumo = StringBuffer();
        final controllers = _notaControllers[i];
        if (controllers != null) {
          for (final entry in controllers.entries) {
            final notaQ =
                double.tryParse(entry.value.text.replaceAll(',', '.')) ?? 0;
            final q = _questoes.firstWhere(
              (q) => (q['numero'] as num?)?.toInt() == entry.key,
              orElse: () => {},
            );
            final valQ = (q['valor'] as num?)?.toDouble() ?? 0;
            resumo.write(
              'Q${entry.key}: ${notaQ.toStringAsFixed(1)}/${valQ.toStringAsFixed(1)}; ',
            );
          }
        }

        await supabase
            .from('resultados')
            .delete()
            .eq('id_aluno', f['id_aluno'])
            .eq('id_avaliacao', avalId!);

        await supabase.from('resultados').insert({
          'id_aluno': f['id_aluno'],
          'id_avaliacao': avalId,
          'nota_bruta': nota10,
          'nota_final': nota10.roundToDouble(),
          'nivel_saeb': nivel,
          'devolutiva': 'Correção em lote (IA, revisada). $resumo',
        });

        // 💾 NOVO: Salvar detalhes da correção (transcrições, justificativas)
        try {
          final appState = Provider.of<AppState>(context, listen: false);
          final sugs = (f['sugestoes'] as List<Map<String, dynamic>>?) ?? [];
          final questoesDetalhadas = <Map<String, dynamic>>[];
          for (final s in sugs) {
            final numQ = (s['numero'] as num?)?.toInt() ?? 0;
            final controller = _notaControllers[i]?[numQ];
            final notaFinal =
                double.tryParse(
                  (controller?.text ?? '').replaceAll(',', '.'),
                ) ??
                0;
            final q = _questoes.firstWhere(
              (q) => (q['numero'] as num?)?.toInt() == numQ,
              orElse: () => <String, dynamic>{},
            );
            questoesDetalhadas.add({
              'numero': numQ,
              'enunciado': '${q['enunciado'] ?? ''}',
              'transcricao': '${s['transcricao'] ?? ''}',
              'nota_sugerida_ia': (s['nota_sugerida'] as num?)?.toDouble() ?? 0,
              'nota_final': notaFinal,
              'valor_questao': (q['valor'] as num?)?.toDouble() ?? 0,
              'justificativa': '${s['justificativa'] ?? ''}',
              'revisar': s['revisar'] == true,
            });
          }
          await http
              .post(
                Uri.parse(
                  '${appState.ipServidor}/api/salvar_correcao_detalhada',
                ),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'id_aluno': f['id_aluno'],
                  'id_avaliacao': avalId,
                  'modelo_usado': '${f['modelo'] ?? ''}',
                  'questoes': questoesDetalhadas,
                }),
              )
              .timeout(const Duration(seconds: 30));
        } catch (e) {
          print('⚠️ Erro ao salvar detalhes: $e');
        }

        f['status'] = 'salvo';
        salvas++;
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $salvas nota(s) revisada(s) e salva(s) no banco!'),
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
    }
  }

  int get _corrigidas => _fila
      .where(
        (f) =>
            f['status'] == 'sucesso' ||
            f['status'] == 'salvo' ||
            f['status'] == 'falha',
      )
      .length;
  int get _sucessos => _fila
      .where((f) => f['status'] == 'sucesso' || f['status'] == 'salvo')
      .length;
  int get _falhas => _fila.where((f) => f['status'] == 'falha').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _etapa == 1
              ? '📸 1. Fotografar'
              : _etapa == 2
              ? '🛒 2. Conferir'
              : _etapa == 3
              ? '🤖 3. Corrigindo'
              : '✏️ 4. Revisar',
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : _etapa == 1
          ? _buildEtapa1()
          : _etapa == 2
          ? _buildEtapa2()
          : _etapa == 3
          ? _buildEtapa3()
          : _buildEtapa4(),
    );
  }

  // 📄 Abrir PDF do aluno no navegador
  void _abrirPdfAluno(int? idAluno) {
    if (idAluno == null || avalId == null) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final url = '${appState.ipServidor}/api/relatorio/aluno/$idAluno/$avalId';
    _abrirUrl(url);
  }

  // 📄 Abrir PDF da turma no navegador
  void _abrirPdfTurma() {
    if (turmaId == null || avalId == null) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final url = '${appState.ipServidor}/api/relatorio/turma/$turmaId/$avalId';
    _abrirUrl(url);
  }

  // 🌐 Abre URL no navegador do celular (onde o PDF aparece de verdade!)
  Future<void> _abrirUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📄 Abrindo PDF no navegador...'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Não foi possível abrir o navegador.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  Widget _buildEtapa1() {
    if (_fotografando) {
      return Column(
        children: [
          Container(
            color: Colors.deepPurple,
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('📸', '${_fila.length}', 'Na cesta'),
                _stat(
                  '🎯',
                  _metaCtl.text.trim().isEmpty ? '∞' : _metaCtl.text.trim(),
                  'Meta',
                ),
              ],
            ),
          ),
          Expanded(
            child: _fila.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '📷 Fotografe as provas uma a uma.\nElas entram na CESTA — nada é enviado ainda!\n\nPara parar: botão VERMELHO abaixo\nou cancele a câmera (voltar).',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _fila.length,
                    itemBuilder: (_, i) {
                      final f = _fila[i];
                      return Card(
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.photo_album,
                            color: Colors.deepPurple,
                          ),
                          title: Text(
                            '${i + 1}. ${f['nome_aluno'] == '' ? '(sem QR — escolher depois)' : f['nome_aluno']}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${f['folhas']} folha(s)',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _pararFotografia,
                icon: const Icon(Icons.stop),
                label: Text(
                  'PARAR E CONFERIR (${_fila.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

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
                  child: Text('${av['nome']}'),
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
            onChanged: (v) => setState(() => turmaId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _metaCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Meta de provas (opcional — ex.: 10)',
              hintText: 'Vazio = fotografa até você parar',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, color: Colors.deepPurple),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Como funciona:\n1️⃣ Fotografa as provas (elas ficam na CESTA)\n2️⃣ Confere a lista e remove o que quiser\n3️⃣ Envia pra correção\n4️⃣ REVISA cada prova antes de salvar!',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: _iniciarFotografia,
              icon: const Icon(Icons.photo_camera, size: 28),
              label: const Text(
                'COMEÇAR A FOTOGRAFAR',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildEtapa2() {
    final prontas = _fila.where((f) => f['id_aluno'] != null).length;
    return Column(
      children: [
        Container(
          color: Colors.deepPurple.shade50,
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat2('📸', '${_fila.length}', 'Na cesta'),
              _stat2('✅', '$prontas', 'Com aluno'),
              _stat2('⚠️', '${_fila.length - prontas}', 'Sem aluno'),
            ],
          ),
        ),
        Expanded(
          child: _fila.isEmpty
              ? const Center(child: Text('Cesta vazia. Volte e fotografe! 📷'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _fila.length,
                  itemBuilder: (_, i) {
                    final f = _fila[i];
                    final semAluno = f['id_aluno'] == null;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          semAluno ? Icons.person_off : Icons.person,
                          color: semAluno ? Colors.orange : Colors.green,
                        ),
                        title: Text(
                          '${i + 1}. ${semAluno ? 'SEM ALUNO — toque para escolher' : f['nome_aluno']}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: semAluno
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: semAluno
                                ? Colors.orange.shade800
                                : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '${f['folhas']} folha(s)',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Remover da cesta',
                          onPressed: () => _removerDaFila(i),
                        ),
                        onTap: semAluno ? () => _escolherAlunoManual(i) : null,
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _etapa = 1;
                          _fotografando = true;
                        });
                        _loopFotos();
                      },
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('+ FOTOS'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _fila.isEmpty ? null : _enviarTudo,
                  icon: const Icon(Icons.send),
                  label: Text(
                    'ENVIAR ${_fila.length} PROVA(S) PARA CORREÇÃO',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEtapa3() {
    final total = _fila.length;
    final prog = total == 0 ? 0.0 : _corrigidas / total;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: prog,
                minHeight: 10,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 8),
              Text(
                _enviando
                    ? '🤖 Corrigindo... $_corrigidas de $total'
                    : '🏁 Concluído: $_sucessos ok, $_falhas falha(s)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _fila.length,
            itemBuilder: (_, i) {
              final f = _fila[i];
              final st = f['status'];
              IconData ic;
              Color cor;
              String sub;
              if (st == 'sucesso') {
                ic = Icons.check_circle;
                cor = Colors.green;
                sub = 'Pronta pra revisão';
              } else if (st == 'salvo') {
                ic = Icons.cloud_done;
                cor = Colors.blue;
                sub = 'Nota salva no banco!';
              } else if (st == 'falha') {
                ic = Icons.error;
                cor = Colors.red;
                sub = '${f['erro']}';
              } else if (st == 'enviando') {
                ic = Icons.hourglass_top;
                cor = Colors.orange;
                sub = 'Corrigindo agora...';
              } else {
                ic = Icons.schedule;
                cor = Colors.grey;
                sub = 'Aguardando na fila...';
              }
              return Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(ic, color: cor),
                  title: Text(
                    '${f['nome_aluno']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(sub, style: const TextStyle(fontSize: 11)),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (!_enviando && _falhas > 0)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _reenviarFalhas,
                    icon: const Icon(Icons.refresh),
                    label: Text('TENTAR DE NOVO AS $_falhas FALHA(S)'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEtapa4() {
    final revisadas = _fila.where((f) => f['status'] == 'sucesso').length;
    return Column(
      children: [
        Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat2('✅', '$revisadas', 'Prontas'),
              _stat2('📝', '${_questoes.length}', 'Questões'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _fila.length,
            itemBuilder: (_, i) {
              final f = _fila[i];
              if (f['status'] != 'sucesso' && f['status'] != 'salvo') {
                return const SizedBox.shrink();
              }
              return _buildCardRevisao(i, f);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: revisadas > 0 ? _salvarNotas : null,
                  icon: const Icon(Icons.save),
                  label: Text('SALVAR $revisadas NOTA(S) NO BANCO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (turmaId != null && avalId != null)
                      ? _abrirPdfTurma
                      : null,
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  label: const Text('📄 RELATÓRIO DA TURMA (PDF)'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardRevisao(int idxFila, Map<String, dynamic> f) {
    final sugs = (f['sugestoes'] as List<Map<String, dynamic>>?) ?? [];
    final soma = _somaNotasEditadas(idxFila);
    final nota10 = _somaValores > 0 ? (soma * 10 / _somaValores) : soma;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.all(12),
        title: Text(
          '${f['nome_aluno']}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          'Nota: ${nota10.toStringAsFixed(1)} / 10.0',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: nota10 >= 6 ? Colors.green : Colors.red,
          ),
        ),
        trailing: f['status'] == 'salvo'
            ? IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                tooltip: 'Gerar Relatório PDF',
                onPressed: () => _abrirPdfAluno(f['id_aluno']),
              )
            : null,
        children: [
          for (final q in _questoes) ...[
            _buildQuestaoRevisao(idxFila, q, sugs),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestaoRevisao(
    int idxFila,
    Map<String, dynamic> q,
    List<Map<String, dynamic>> sugs,
  ) {
    final n = (q['numero'] as num?)?.toInt() ?? 0;
    final valor = (q['valor'] as num?)?.toDouble() ?? 0;
    final sug = sugs.where((s) => (s['numero'] as num?)?.toInt() == n).toList();
    final transcricao = sug.isNotEmpty ? '${sug.first['transcricao']}' : '—';
    final justificativa = sug.isNotEmpty ? '${sug.first['justificativa']}' : '';
    final revisar = sug.isNotEmpty && sug.first['revisar'] == true;

    final controller = _notaControllers[idxFila]?[n];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
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
                'Valor: ${valor.toStringAsFixed(1)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${q['enunciado']}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            '✍️ IA leu: "$transcricao"',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.blue.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '💡 $justificativa',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          if (revisar)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '⚠️ Confira!',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Nota:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/ ${valor.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String emoji, String valor, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _stat2(String emoji, String valor, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.deepPurple),
        ),
      ],
    );
  }
}
