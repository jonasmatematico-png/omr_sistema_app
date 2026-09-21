import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class TelaTesteIAs extends StatefulWidget {
  const TelaTesteIAs({super.key});

  @override
  State<TelaTesteIAs> createState() => _TelaTesteIAsState();
}

class _TelaTesteIAsState extends State<TelaTesteIAs> {
  static const String _modeloGemini = 'gemini-3.6-flash';
  static const String _modeloGroq = 'qwen/qwen3.6-27b';

  List<String> _geminiChaves = [];
  String _groqKey = '';

  List<Map<String, dynamic>> _avaliacoes = [];
  int? _avalId;

  List<String> _caminhos = [];
  bool _rodando = false;
  String _etapa = '';

  List<Map<String, dynamic>> _questoesTeste = [];
  Map<String, dynamic>? _resGemini;
  Map<String, dynamic>? _resGroq;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> chaves = prefs.getStringList('gemini_api_keys') ?? [];
      if (chaves.isEmpty) {
        final antiga = prefs.getString('gemini_api_key') ?? '';
        if (antiga.isNotEmpty) chaves = [antiga];
      }
      final supabase = Supabase.instance.client;
      final a = await supabase.from('avaliacoes').select('*').order('id');
      final abertas = List<Map<String, dynamic>>.from(
        a,
      ).where((av) => '${av['modo_correcao']}' == 'aberta').toList();
      setState(() {
        _geminiChaves = chaves;
        _groqKey = prefs.getString('groq_api_key') ?? '';
        _avaliacoes = abertas;
      });
    } catch (e) {
      // silencioso
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

  Future<List<Map<String, dynamic>>> _chamarGemini(
    List<List<int>> bytesLista,
    List<Map<String, dynamic>> questoes,
  ) async {
    final partes = <Map<String, dynamic>>[
      {'text': _montarPrompt(questoes)},
    ];
    for (final b in bytesLista) {
      partes.add({
        'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(b)},
      });
    }
    final corpo = jsonEncode({
      'contents': [
        {'parts': partes},
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      },
    });

    Object? ultimoErro;
    for (final chave in _geminiChaves) {
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
          ultimoErro = 'Sem cota (429).';
          continue;
        }
        if (response.statusCode != 200) {
          throw Exception('Gemini ${response.statusCode}: ${response.body}');
        }
        final json = jsonDecode(response.body);
        return _parseJson(
          json['candidates'][0]['content']['parts'][0]['text'] as String,
        );
      } catch (e) {
        ultimoErro = e;
      }
    }
    throw Exception('Gemini falhou: $ultimoErro');
  }

  Future<List<Map<String, dynamic>>> _chamarGroq(
    List<List<int>> bytesLista,
    List<Map<String, dynamic>> questoes,
  ) async {
    final conteudo = <Map<String, dynamic>>[
      {'type': 'text', 'text': _montarPrompt(questoes)},
    ];
    for (final b in bytesLista) {
      conteudo.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(b)}'},
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

    final response = await http
        .post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_groqKey',
            'Content-Type': 'application/json',
          },
          body: corpo,
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode != 200) {
      throw Exception('Groq ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body);
    return _parseJson('${json['choices'][0]['message']['content']}');
  }

  Future<void> _escolherFoto() async {
    final options = DocumentScannerOptions(
      mode: ScannerMode.full,
      pageLimit: 3,
      isGalleryImport: true,
    );
    final scanner = DocumentScanner(options: options);
    final result = await scanner.scanDocument();
    if (result.images != null && result.images!.isNotEmpty) {
      setState(() => _caminhos = List<String>.from(result.images!));
    }
  }

  Future<void> _runTeste() async {
    if (_avalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Escolha a prova aberta!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_caminhos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Escolha a foto da prova!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_geminiChaves.isEmpty && _groqKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Cadastre ao menos uma chave na tela de correção!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _rodando = true;
      _resGemini = null;
      _resGroq = null;
      _questoesTeste = [];
    });
    try {
      final supabase = Supabase.instance.client;
      final qs = await supabase
          .from('questoes_abertas')
          .select('*')
          .eq('id_avaliacao', _avalId!)
          .order('numero');
      final questoes = List<Map<String, dynamic>>.from(qs);
      if (questoes.isEmpty) {
        throw Exception('A prova escolhida não tem questões.');
      }
      setState(() => _questoesTeste = questoes);

      final List<List<int>> bytesLista = [];
      for (final c in _caminhos) {
        bytesLista.add(await File(c).readAsBytes());
      }

      if (_geminiChaves.isNotEmpty) {
        setState(() => _etapa = '🟠 Gemini pensando...');
        final sw = Stopwatch()..start();
        try {
          final sug = await _chamarGemini(bytesLista, questoes);
          sw.stop();
          setState(
            () => _resGemini = {
              'tempo': sw.elapsedMilliseconds / 1000,
              'sugestoes': sug,
            },
          );
        } catch (e) {
          sw.stop();
          setState(
            () => _resGemini = {
              'tempo': sw.elapsedMilliseconds / 1000,
              'erro': '$e',
            },
          );
        }
      }

      if (_groqKey.isNotEmpty) {
        setState(() => _etapa = '⚡ Groq pensando...');
        final sw = Stopwatch()..start();
        try {
          final sug = await _chamarGroq(bytesLista, questoes);
          sw.stop();
          setState(
            () => _resGroq = {
              'tempo': sw.elapsedMilliseconds / 1000,
              'sugestoes': sug,
            },
          );
        } catch (e) {
          sw.stop();
          setState(
            () => _resGroq = {
              'tempo': sw.elapsedMilliseconds / 1000,
              'erro': '$e',
            },
          );
        }
      }

      setState(() => _etapa = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🏁 Teste concluído! Compare os resultados.'),
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
      setState(() => _rodando = false);
    }
  }

  Widget _chipChave(String rotulo, bool ok, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? cor.withOpacity(0.15) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? cor : Colors.grey),
      ),
      child: Text(
        ok ? '$rotulo ✅' : '$rotulo ❌',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: ok ? cor : Colors.grey,
        ),
      ),
    );
  }

  Widget _cardResultado(String titulo, Color cor, Map<String, dynamic>? res) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cor,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (res != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '⏱️ ${(res['tempo'] as double).toStringAsFixed(1)}s',
                      style: TextStyle(fontWeight: FontWeight.bold, color: cor),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (res == null)
              const Text(
                'Aguardando teste...',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              )
            else if (res['erro'] != null)
              Text(
                '❌ ${res['erro']}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              )
            else
              ..._buildLinhasResultado(res),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLinhasResultado(Map<String, dynamic> res) {
    final sugs = List<Map<String, dynamic>>.from(res['sugestoes'] as List);
    final linhas = <Widget>[];
    for (final q in _questoesTeste) {
      final n = (q['numero'] as num?)?.toInt() ?? 0;
      final s = sugs.where((x) => (x['numero'] as num?)?.toInt() == n).toList();
      final nota = s.isNotEmpty
          ? (s.first['nota_sugerida'] as num?)?.toDouble()
          : null;
      final transc = s.isNotEmpty ? '${s.first['transcricao']}' : '—';
      linhas.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Q$n • Nota: ${nota?.toStringAsFixed(1) ?? '—'} / ${(q['valor'] as num?)?.toDouble().toStringAsFixed(1)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '✍️ "$transc"',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return linhas;
  }

  @override
  Widget build(BuildContext context) {
    String? vencedor;
    if (_resGemini != null &&
        _resGroq != null &&
        _resGemini!['erro'] == null &&
        _resGroq!['erro'] == null) {
      final tg = _resGemini!['tempo'] as double;
      final tr = _resGroq!['tempo'] as double;
      vencedor = tg <= tr ? '🟠 Gemini' : '⚡ Groq';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 Laboratório de IAs'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.teal.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '🔬 Como funciona:\n1. Escolha a prova (para os critérios);\n2. Fotografe OU importe UMA prova da galeria;\n3. Aperte TESTAR — a mesma foto vai para as duas IAs com cronômetro;\n4. Compare tempo, transcrição e notas!\n\n⚠️ Cada teste gasta 1 pedido de cada IA.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            value: _avalId,
            decoration: const InputDecoration(
              labelText: 'Prova aberta (critérios)',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final av in _avaliacoes)
                DropdownMenuItem(
                  value: av['id'] as int,
                  child: Text('${av['nome']}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _avalId = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _rodando ? null : _escolherFoto,
            icon: const Icon(Icons.camera_alt),
            label: Text(
              _caminhos.isEmpty
                  ? '📷 Escolher foto da prova'
                  : '📷 ${_caminhos.length} folha(s) selecionada(s) — tocar p/ trocar',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.teal,
              side: BorderSide(color: Colors.teal.shade300),
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _chipChave(
                '🟠 Gemini',
                _geminiChaves.isNotEmpty,
                Colors.deepOrange,
              ),
              const SizedBox(width: 8),
              _chipChave('⚡ Groq', _groqKey.isNotEmpty, Colors.blue),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _rodando ? null : _runTeste,
              icon: const Icon(Icons.timer),
              label: const Text(
                '🏁 TESTAR AS DUAS IAs',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (_rodando)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.teal),
                  const SizedBox(height: 8),
                  Text(
                    _etapa,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (vencedor != null)
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '🏆 Mais rápido: $vencedor! (Agora compare QUALIDADE da leitura e das notas abaixo.)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: 8),
          _cardResultado('🟠 Gemini', Colors.deepOrange, _resGemini),
          const SizedBox(height: 8),
          _cardResultado('⚡ Groq', Colors.blue, _resGroq),
        ],
      ),
    );
  }
}
