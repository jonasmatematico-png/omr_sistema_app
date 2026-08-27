import 'dart:convert';
import 'dart:io';
//#import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

//import 'package:flutter_image_compress/flutter_image_compress.dart';

class TelaCorrecaoAberta extends StatefulWidget {
  const TelaCorrecaoAberta({super.key});

  @override
  State<TelaCorrecaoAberta> createState() => _TelaCorrecaoAbertaState();
}

class _TelaCorrecaoAbertaState extends State<TelaCorrecaoAberta> {
  // 🚨 TROQUE AQUI se o Google mudar o nome do modelo
  static const String _modeloGemini = 'gemini-3.6-flash';

  String _apiKey = '';
  final _keyController = TextEditingController();

  List<Map<String, dynamic>> avaliacoesAbertas = [];
  List<Map<String, dynamic>> turmas = [];
  List<Map<String, dynamic>> alunos = [];
  int? avalId;
  int? turmaId;
  bool carregando = true;
  bool processando = false;

  // modo revisão
  bool emRevisao = false;
  String _nomeAlunoRevisao = '';
  int? _idAlunoRevisao;
  List<Map<String, dynamic>> _questoesRevisao = [];
  List<Map<String, dynamic>> _sugestoes = [];
  final Map<int, TextEditingController> _notaControllers = {};

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chave = prefs.getString('gemini_api_key') ?? '';
      final supabase = Supabase.instance.client;
      final a = await supabase.from('avaliacoes').select('*').order('id');
      final t = await supabase.from('turmas').select('*').order('nome');

      final abertas = List<Map<String, dynamic>>.from(
        a,
      ).where((av) => '${av['modo_correcao']}' == 'aberta').toList();
      final listaTurmas = List<Map<String, dynamic>>.from(t);
      listaTurmas.sort((x, y) => '${x['nome']}'.compareTo('${y['nome']}'));

      setState(() {
        _apiKey = chave;
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
    await prefs.setString('gemini_api_key', k);
    setState(() => _apiKey = k);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔑 Chave da IA salva!'),
          backgroundColor: Colors.green,
        ),
      );
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
    return sb.toString();
  }

  List<Map<String, dynamic>> _parseJson(String texto) {
    final t = texto.trim();
    final i = t.indexOf('[');
    final f = t.lastIndexOf(']');
    if (i == -1 || f == -1 || f <= i) {
      throw Exception('A IA não retornou uma lista válida.');
    }
    final arr = jsonDecode(t.substring(i, f + 1)) as List;
    return arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _corrigirAluno(Map<String, dynamic> aluno) async {
    if (_apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔑 Cole sua chave da IA no campo do topo!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    setState(() => processando = true);
    try {
      final supabase = Supabase.instance.client;

      // 1) Fotografa a prova (até 3 folhas)
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 3,
        isGalleryImport: false,
      );
      final scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      if (result.images == null || result.images!.isEmpty) {
        setState(() => processando = false);
        return;
      }

      // 2) Lê as folhas escaneadas (sem compressão = mais rápido no celular)
      final List<Map<String, dynamic>> partesImagem = [];
      for (final caminho in result.images!) {
        final bytesPagina = await File(caminho).readAsBytes();
        partesImagem.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(bytesPagina),
          },
        });
      }

      // 3) Busca as questões abertas da avaliação
      final qs = await supabase
          .from('questoes_abertas')
          .select('*')
          .eq('id_avaliacao', avalId!)
          .order('numero');
      final questoes = List<Map<String, dynamic>>.from(qs);
      if (questoes.isEmpty) {
        throw Exception('Esta prova aberta não tem questões cadastradas.');
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

      // 4) 🚨 RETENTATIVAS: se a internet cair, o app tenta 3 vezes sozinho
      http.Response? response;
      String? ultimoErro;
      for (int tentativa = 1; tentativa <= 3; tentativa++) {
        try {
          response = await http
              .post(
                Uri.parse(
                  'https://generativelanguage.googleapis.com/v1beta/models/$_modeloGemini:generateContent?key=$_apiKey',
                ),
                headers: {'Content-Type': 'application/json'},
                body: corpo,
              )
              .timeout(const Duration(seconds: 120));
          break;
        } catch (e) {
          ultimoErro = '$e';
          if (tentativa < 3) {
            await Future.delayed(Duration(seconds: 2 * tentativa));
          }
        }
      }
      if (response == null) {
        throw Exception('Falha de conexão após 3 tentativas: $ultimoErro');
      }

      if (response.statusCode != 200) {
        throw Exception(
          'IA respondeu ${response.statusCode}: ${response.body}',
        );
      }

      final json = jsonDecode(response.body);
      final texto =
          json['candidates'][0]['content']['parts'][0]['text'] as String;
      final sugestoes = _parseJson(texto);

      // 5) Prepara a revisão
      for (final c in _notaControllers.values) {
        c.dispose();
      }
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
        _nomeAlunoRevisao = '${aluno['nome_completo']}';
        _idAlunoRevisao = aluno['id'] as int;
        emRevisao = true;
        processando = false;
      });
    } catch (e) {
      setState(() => processando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
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

  // ---------- PARTES DA TELA ----------

  Widget _buildChavePanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Colors.amber.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🔑 Cole aqui sua chave da IA (Gemini):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keyController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'AQ... ou AIza...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _salvarChave,
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
        ],
      ),
    );
  }

  Widget _buildListaAlunos() {
    if (alunos.isEmpty) {
      return const Center(child: Text('Escolha a prova e a turma acima. 👆'));
    }
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
                    if (_apiKey.isEmpty) _buildChavePanel(),
                    if (!emRevisao) _buildSelecaoProvaETurma(),
                    if (!emRevisao) Expanded(child: _buildListaAlunos()),
                    if (emRevisao) _buildRevisaoHeader(),
                    if (emRevisao) Expanded(child: _buildRevisaoLista()),
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
