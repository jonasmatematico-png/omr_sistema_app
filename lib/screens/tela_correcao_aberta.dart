import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class TelaCorrecaoAberta extends StatefulWidget {
  const TelaCorrecaoAberta({super.key});

  @override
  State<TelaCorrecaoAberta> createState() => _TelaCorrecaoAbertaState();
}

class _TelaCorrecaoAbertaState extends State<TelaCorrecaoAberta> {
  static const String _modeloGemini = 'gemini-3.6-flash';
  static const String _modeloGroq = 'qwen/qwen3.6-27b';

  String _provedor = 'groq';

  // Gemini (rotação antiga)
  List<String> _chavesGemini = [];
  int _chaveGeminiAtiva = 0;
  final _keyController = TextEditingController();

  // 🚨 GROQ: time de chaves com rotação automática
  List<String> _chavesGroq = [];
  int _chaveGroqAtiva = 0;
  final _groqKeyController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provedor = prefs.getString('provedor_ia') ?? 'groq';

      // Gemini
      List<String> chavesG = prefs.getStringList('gemini_api_keys') ?? [];
      if (chavesG.isEmpty) {
        final antiga = prefs.getString('gemini_api_key') ?? '';
        if (antiga.isNotEmpty) {
          chavesG = [antiga];
          await prefs.setStringList('gemini_api_keys', chavesG);
        }
      }

      // Groq (migra chave antiga e carrega time)
      List<String> chavesR = prefs.getStringList('groq_api_keys') ?? [];
      if (chavesR.isEmpty) {
        final antigaGroq = prefs.getString('groq_api_key') ?? '';
        if (antigaGroq.isNotEmpty) {
          chavesR = [antigaGroq];
          await prefs.setStringList('groq_api_keys', chavesR);
        }
      }

      final supabase = Supabase.instance.client;
      final a = await supabase.from('avaliacoes').select('*').order('id');
      final t = await supabase.from('turmas').select('*').order('nome');
      final abertas = List<Map<String, dynamic>>.from(
        a,
      ).where((av) => '${av['modo_correcao']}' == 'aberta').toList();
      final listaTurmas = List<Map<String, dynamic>>.from(t);
      listaTurmas.sort((x, y) => '${x['nome']}'.compareTo('${y['nome']}'));

      setState(() {
        _provedor = provedor;
        _chavesGemini = chavesG;
        _chaveGeminiAtiva = 0;
        _chavesGroq = chavesR;
        _chaveGroqAtiva = 0;
        avaliacoesAbertas = abertas;
        turmas = listaTurmas;
        carregando = false;
      });
    } catch (e) {
      setState(() => carregando = false);
    }
  }

  Future<void> _salvarChave() async {
    final k = _keyController.text.trim();
    if (k.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _chavesGemini.add(k);
      _chaveGeminiAtiva = 0;
    });
    await prefs.setStringList('gemini_api_keys', _chavesGemini);
    _keyController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔑 Chave Gemini adicionada!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _salvarChaveGroq() async {
    final k = _groqKeyController.text.trim();
    if (k.isEmpty) return;
    if (_chavesGroq.contains(k)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Esta chave já está na lista!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _chavesGroq.add(k);
      _chaveGroqAtiva = 0;
    });
    await prefs.setStringList('groq_api_keys', _chavesGroq);
    await prefs.setString('groq_api_key', k); // mantém compatibilidade
    _groqKeyController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚡ Chave Groq ${_chavesGroq.length} adicionada!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _trocarProvedor(String p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provedor_ia', p);
    setState(() => _provedor = p);
  }

  Future<void> _gerenciarChaves() async {
    final novoController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  '🔑 Chaves da IA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const Text(
                  'Gemini: 20/dia por chave • Groq: ~35/dia por chave\nO app troca sozinho quando a cota acabar.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🟠 Gemini',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                        if (_chavesGemini.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Nenhuma chave.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ..._chavesGemini.asMap().entries.map((e) {
                            final i = e.key;
                            final c = e.value;
                            final mascara = c.length > 10
                                ? '${c.substring(0, 10)}...'
                                : c;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: i == _chaveGeminiAtiva
                                    ? Colors.deepOrange
                                    : Colors.grey.shade300,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                mascara,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: i == _chaveGeminiAtiva
                                  ? const Text(
                                      'ativa',
                                      style: TextStyle(fontSize: 11),
                                    )
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  setSheetState(() {
                                    _chavesGemini.removeAt(i);
                                    if (_chaveGeminiAtiva >=
                                        _chavesGemini.length)
                                      _chaveGeminiAtiva = 0;
                                  });
                                  setState(() {});
                                  await prefs.setStringList(
                                    'gemini_api_keys',
                                    _chavesGemini,
                                  );
                                },
                              ),
                            );
                          }),
                        const Divider(),
                        const Text(
                          '⚡ Groq',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        if (_chavesGroq.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Nenhuma chave.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ..._chavesGroq.asMap().entries.map((e) {
                            final i = e.key;
                            final c = e.value;
                            final mascara = c.length > 10
                                ? '${c.substring(0, 10)}...'
                                : c;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: i == _chaveGroqAtiva
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                mascara,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: i == _chaveGroqAtiva
                                  ? const Text(
                                      'ativa',
                                      style: TextStyle(fontSize: 11),
                                    )
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  setSheetState(() {
                                    _chavesGroq.removeAt(i);
                                    if (_chaveGroqAtiva >= _chavesGroq.length)
                                      _chaveGroqAtiva = 0;
                                  });
                                  setState(() {});
                                  await prefs.setStringList(
                                    'groq_api_keys',
                                    _chavesGroq,
                                  );
                                },
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: novoController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Cole a nova chave (AQ..., gsk_...)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _provedor,
                      items: const [
                        DropdownMenuItem(value: 'gemini', child: Text('🟠')),
                        DropdownMenuItem(value: 'groq', child: Text('⚡')),
                      ],
                      onChanged: null,
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () async {
                        final k = novoController.text.trim();
                        if (k.isEmpty) return;
                        final prefs = await SharedPreferences.getInstance();
                        final provedor = _provedor;
                        setSheetState(() {
                          if (provedor == 'groq') {
                            if (!_chavesGroq.contains(k)) _chavesGroq.add(k);
                          } else {
                            if (!_chavesGemini.contains(k))
                              _chavesGemini.add(k);
                          }
                        });
                        setState(() {});
                        await prefs.setStringList(
                          'gemini_api_keys',
                          _chavesGemini,
                        );
                        await prefs.setStringList('groq_api_keys', _chavesGroq);
                        novoController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '🔑 Adicionada ao time ${provedor == 'groq' ? '⚡ Groq' : '🟠 Gemini'}!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      child: const Text('Adicionar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    sb.writeln('Você é um professor assistente de Matemática (6º e 9º ano).');
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

  Future<List<Map<String, dynamic>>> _chamarIA(
    List<String> caminhos,
    List<Map<String, dynamic>> questoes,
  ) async {
    if (_provedor == 'groq') {
      return _chamarGroq(caminhos, questoes);
    }
    return _chamarGemini(caminhos, questoes);
  }

  Future<List<Map<String, dynamic>>> _chamarGemini(
    List<String> caminhos,
    List<Map<String, dynamic>> questoes,
  ) async {
    if (_chavesGemini.isEmpty)
      throw Exception('Cadastre ao menos uma chave Gemini.');

    final List<Map<String, dynamic>> partesImagem = [];
    for (final caminho in caminhos) {
      final bytesPagina = await File(caminho).readAsBytes();
      partesImagem.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(bytesPagina),
        },
      });
    }

    final corpo = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _montarPrompt(questoes)},
            ...partesImagem,
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      },
    });

    Object? ultimoErro;
    for (int k = 0; k < _chavesGemini.length; k++) {
      final indice = (_chaveGeminiAtiva + k) % _chavesGemini.length;
      final chave = _chavesGemini[indice];
      final proxima = (_chaveGeminiAtiva + k + 1) % _chavesGemini.length;
      bool trocarChave = false;

      for (int tentativa = 1; tentativa <= 2; tentativa++) {
        try {
          final response = await http
              .post(
                Uri.parse(
                  'https://generativelanguage.googleapis.com/v1beta/models/$_modeloGemini:generateContent?key=$chave',
                ),
                headers: {'Content-Type': 'application/json'},
                body: corpo,
              )
              .timeout(const Duration(seconds: 120));

          if (response.statusCode == 429) {
            ultimoErro = 'Chave ${indice + 1} sem cota (429).';
            trocarChave = true;
            break;
          }
          if (response.statusCode != 200) {
            throw Exception('Gemini ${response.statusCode}: ${response.body}');
          }

          if (_chaveGeminiAtiva != indice && mounted) {
            setState(() => _chaveGeminiAtiva = indice);
          }
          final json = jsonDecode(response.body);
          final texto =
              json['candidates'][0]['content']['parts'][0]['text'] as String;
          return _parseJson(texto);
        } catch (e) {
          ultimoErro = e;
          if (tentativa < 2)
            await Future.delayed(Duration(seconds: 2 * tentativa));
        }
      }

      if (trocarChave && mounted && k < _chavesGemini.length - 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🟠 Cota da chave ${indice + 1} esgotada — usando a ${proxima + 1}...',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
    throw Exception('Todas as chaves Gemini falharam: $ultimoErro');
  }

  Future<List<Map<String, dynamic>>> _chamarGroq(
    List<String> caminhos,
    List<Map<String, dynamic>> questoes,
  ) async {
    if (_chavesGroq.isEmpty)
      throw Exception('Cadastre ao menos uma chave Groq.');

    final List<Map<String, dynamic>> conteudo = [
      {'type': 'text', 'text': _montarPrompt(questoes)},
    ];
    for (final caminho in caminhos) {
      final bytes = await File(caminho).readAsBytes();
      conteudo.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(bytes)}'},
      });
    }

    final corpo = jsonEncode({
      'model': _modeloGroq,
      'messages': [
        {'role': 'user', 'content': conteudo},
      ],
      'temperature': 0.2,
      'reasoning_effort': 'none',
    });

    Object? ultimoErro;

    // 🚨 ROTAÇÃO DE CHAVES GROQ
    for (int k = 0; k < _chavesGroq.length; k++) {
      final indice = (_chaveGroqAtiva + k) % _chavesGroq.length;
      final chave = _chavesGroq[indice];
      final proxima = (_chaveGroqAtiva + k + 1) % _chavesGroq.length;
      bool trocarChave = false;

      for (int tentativa = 1; tentativa <= 2; tentativa++) {
        try {
          final response = await http
              .post(
                Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
                headers: {
                  'Authorization': 'Bearer $chave',
                  'Content-Type': 'application/json',
                },
                body: corpo,
              )
              .timeout(const Duration(seconds: 120));

          // 429 = cota excedida → pula pra próxima
          if (response.statusCode == 429) {
            ultimoErro = 'Chave ${indice + 1} sem cota (429).';
            trocarChave = true;
            break;
          }
          if (response.statusCode != 200) {
            throw Exception('Groq ${response.statusCode}: ${response.body}');
          }

          // Sucesso: memoriza a chave ativa
          if (_chaveGroqAtiva != indice && mounted) {
            setState(() => _chaveGroqAtiva = indice);
          }
          final json = jsonDecode(response.body);
          final texto = '${json['choices'][0]['message']['content']}';
          return _parseJson(texto);
        } catch (e) {
          ultimoErro = e;
          if (tentativa < 2)
            await Future.delayed(Duration(seconds: 2 * tentativa));
        }
      }

      if (trocarChave && mounted && k < _chavesGroq.length - 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚡ Cota da chave ${indice + 1} esgotada — usando a ${proxima + 1}...',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }

    throw Exception('Todas as chaves Groq falharam: $ultimoErro');
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
    final semChave = _provedor == 'groq'
        ? _chavesGroq.isEmpty
        : _chavesGemini.isEmpty;
    if (semChave) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔑 Cadastre uma chave no Gerenciar!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
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
        setState(() => processando = false);
        return;
      }
      _ultimosCaminhos = List<String>.from(result.images!);
      final qs = await supabase
          .from('questoes_abertas')
          .select('*')
          .eq('id_avaliacao', avalId!)
          .order('numero');
      final questoes = List<Map<String, dynamic>>.from(qs);
      if (questoes.isEmpty)
        throw Exception('Esta prova não tem questões cadastradas.');
      final sugestoes = await _chamarIA(_ultimosCaminhos, questoes);
      setState(() {
        _nomeAlunoRevisao = '${aluno['nome_completo']}';
        _idAlunoRevisao = aluno['id'] as int;
      });
      await _prepararRevisao(questoes, sugestoes);
    } catch (e) {
      setState(() => processando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
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
      final sugestoes = await _chamarIA(_ultimosCaminhos, questoes);
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildSeletorProvedor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _trocarProvedor('gemini'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _provedor == 'gemini'
                    ? Colors.deepOrange
                    : Colors.grey.shade200,
                foregroundColor: _provedor == 'gemini'
                    ? Colors.white
                    : Colors.grey.shade700,
              ),
              child: const Text(
                '🟠 Gemini',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _trocarProvedor('groq'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _provedor == 'groq'
                    ? Colors.blue
                    : Colors.grey.shade200,
                foregroundColor: _provedor == 'groq'
                    ? Colors.white
                    : Colors.grey.shade700,
              ),
              child: const Text(
                '⚡ Groq',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoChaves() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.vpn_key,
            size: 16,
            color: _provedor == 'groq' ? Colors.blue : Colors.deepOrange,
          ),
          const SizedBox(width: 6),
          Text(
            _provedor == 'groq'
                ? '⚡ ${_chavesGroq.length} chave(s) • ativa: ${_chavesGroq.isEmpty ? 0 : _chaveGroqAtiva + 1}'
                : '🟠 ${_chavesGemini.length} chave(s) • ativa: ${_chavesGemini.isEmpty ? 0 : _chaveGeminiAtiva + 1}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const Spacer(),
          TextButton(
            onPressed: _gerenciarChaves,
            child: const Text('Gerenciar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildPainelChaveVazio() {
    final ehGroq = _provedor == 'groq';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: ehGroq ? Colors.blue.shade50 : Colors.amber.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ehGroq
                    ? '⚡ Cadastre suas chaves Groq (console.groq.com/keys):'
                    : '🔑 Cadastre sua chave Gemini:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ehGroq ? _groqKeyController : _keyController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: ehGroq ? 'gsk_...' : 'AQ... ou AIza...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: ehGroq ? _salvarChaveGroq : _salvarChave,
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          if (avalId != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _editarRegras,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('✏️ Regras da prova'),
                style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
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
      padding: const EdgeInsets.all(16),
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
    final temChave = _provedor == 'groq'
        ? _chavesGroq.isNotEmpty
        : _chavesGemini.isNotEmpty;
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
                    if (!emRevisao) _buildSeletorProvedor(),
                    if (!emRevisao && !temChave) _buildPainelChaveVazio(),
                    if (!emRevisao && temChave) _buildResumoChaves(),
                    if (!emRevisao) _buildSelecaoProvaETurma(),
                    if (!emRevisao) Expanded(child: _buildListaAlunos()),
                    if (emRevisao) _buildRevisaoHeader(),
                    if (emRevisao) Expanded(child: _buildRevisaoLista()),
                    if (emRevisao) _buildBotoesAcao(),
                    if (emRevisao) _buildBotaoConfirmar(),
                  ],
                ),
          if (processando) _buildOverlayProcessando(),
        ],
      ),
      floatingActionButton: emRevisao
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => emRevisao = false),
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar'),
            )
          : null,
    );
  }
}
