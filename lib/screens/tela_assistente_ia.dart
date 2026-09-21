import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../context/app_state.dart';

class TelaAssistenteIA extends StatefulWidget {
  final int? avaliacaoId;
  final String nomeAvaliacao;

  const TelaAssistenteIA({
    super.key,
    this.avaliacaoId,
    this.nomeAvaliacao = '',
  });

  @override
  State<TelaAssistenteIA> createState() => _TelaAssistenteIAState();
}

class _TelaAssistenteIAState extends State<TelaAssistenteIA> {
  // ----- Configuração da matriz -----
  String _fonte = 'CP';
  int _ano = 6;
  List<Map<String, dynamic>> _matriz = [];
  final Set<String> _selecionadas = {};
  bool _carregando = false;

  // ----- Geração de questões -----
  int _quantidade = 1;
  String _dificuldade = 'média';
  final TextEditingController _contextoCtrl = TextEditingController();
  bool _gerando = false;
  bool _salvando = false;

  List<Map<String, dynamic>> _geradas = [];
  final List<TextEditingController> _ctrlEnunciado = [];
  final List<TextEditingController> _ctrlResposta = [];
  final List<TextEditingController> _ctrlCriterios = [];
  final List<TextEditingController> _ctrlValor = [];

  // ----- Identificar habilidade -----
  final TextEditingController _identificarCtrl = TextEditingController();
  bool _identificando = false;
  List<Map<String, dynamic>> _resultadosIdent = [];

  @override
  void dispose() {
    _contextoCtrl.dispose();
    _identificarCtrl.dispose();
    _limparCtrlsGeradas();
    super.dispose();
  }

  void _limparCtrlsGeradas() {
    for (final c in _ctrlEnunciado) {
      c.dispose();
    }
    for (final c in _ctrlResposta) {
      c.dispose();
    }
    for (final c in _ctrlCriterios) {
      c.dispose();
    }
    for (final c in _ctrlValor) {
      c.dispose();
    }
    _ctrlEnunciado.clear();
    _ctrlResposta.clear();
    _ctrlCriterios.clear();
    _ctrlValor.clear();
  }

  String get _ip => Provider.of<AppState>(context, listen: false).ipServidor;

  // ---------- 1) Carregar a matriz ----------
  Future<void> _carregarMatriz() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _carregando = true;
      _matriz = [];
      _selecionadas.clear();
    });
    try {
      final resp = await http
          .get(Uri.parse('$_ip/api/matriz?fonte=$_fonte&ano=$_ano'))
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body);
        if (j['sucesso'] == true) {
          final List<dynamic> itensRaw = j['itens'] ?? [];
          setState(() {
            // Conversão segura de JSON para List<Map>
            _matriz = itensRaw
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
        } else {
          throw Exception(j['erro'] ?? 'Falha ao carregar');
        }
      } else {
        throw Exception('Erro HTTP: ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao carregar matriz: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // ---------- 2) Gerar questões com IA ----------
  Future<void> _gerarQuestoes() async {
    FocusScope.of(context).unfocus();
    if (_selecionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Escolha ao menos 1 habilidade/descritor!'),
        ),
      );
      return;
    }
    setState(() => _gerando = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_ip/api/gerar_questoes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'codigos': _selecionadas.toList(),
              'fonte': _fonte,
              'componente': 'Matemática',
              'ano': _ano,
              'quantidade': _quantidade,
              'dificuldade': _dificuldade,
              'contexto': _contextoCtrl.text,
              'valor_padrao': 2.0,
            }),
          )
          .timeout(const Duration(seconds: 180));

      final j = jsonDecode(resp.body);
      if (j['sucesso'] == true) {
        final List<dynamic> qsRaw = j['questoes'] ?? [];
        // Conversão segura
        final qs = qsRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        _limparCtrlsGeradas();
        setState(() {
          _geradas = qs;
          for (final q in qs) {
            _ctrlEnunciado.add(
              TextEditingController(text: '${q['enunciado'] ?? ''}'),
            );
            _ctrlResposta.add(
              TextEditingController(text: '${q['resposta_esperada'] ?? ''}'),
            );
            _ctrlCriterios.add(
              TextEditingController(text: '${q['criterios'] ?? ''}'),
            );
            _ctrlValor.add(TextEditingController(text: '${q['valor'] ?? 2.0}'));
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ ${j['erro'] ?? 'Erro ao gerar'}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  // ---------- 3) Identificar habilidade de uma questão pronta ----------
  Future<void> _identificar() async {
    FocusScope.of(context).unfocus();
    if (_identificarCtrl.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Cole o texto completo da questão!')),
      );
      return;
    }
    setState(() => _identificando = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_ip/api/identificar_habilidade'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'texto': _identificarCtrl.text,
              'fonte': _fonte,
              'componente': 'Matemática',
              'ano': _ano,
            }),
          )
          .timeout(const Duration(seconds: 180));

      final j = jsonDecode(resp.body);
      if (j['sucesso'] == true) {
        final List<dynamic> resRaw = j['resultados'] ?? [];
        setState(() {
          // Conversão segura
          _resultadosIdent = resRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ ${j['erro'] ?? 'Erro ao identificar'}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    } finally {
      if (mounted) setState(() => _identificando = false);
    }
  }

  // ---------- 4) Salvar as questões geradas na avaliação ----------
  Future<void> _salvarNaAvaliacao() async {
    FocusScope.of(context).unfocus();
    if (widget.avaliacaoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Abra o assistente a partir de uma avaliação para salvar!',
          ),
        ),
      );
      return;
    }
    if (_geradas.isEmpty) return;
    setState(() => _salvando = true);

    try {
      final supabase = Supabase.instance.client;
      final existentes = await supabase
          .from('questoes_abertas')
          .select('numero')
          .eq('id_avaliacao', widget.avaliacaoId!);

      // CORREÇÃO DO ERRO: Removido o 'late' que causava erro de compilação
      int proximo = 1;
      for (final e in existentes) {
        final n = (e['numero'] as num?)?.toInt() ?? 0;
        if (n >= proximo) proximo = n + 1;
      }

      for (int i = 0; i < _geradas.length; i++) {
        final codigo = '${_geradas[i]['codigo'] ?? ''}';
        await supabase.from('questoes_abertas').insert({
          'id_avaliacao': widget.avaliacaoId,
          'numero': proximo + i,
          'enunciado': _ctrlEnunciado[i].text,
          'resposta_esperada': _ctrlResposta[i].text,
          'valor':
              double.tryParse(_ctrlValor[i].text.replaceAll(',', '.')) ?? 2.0,
          'habilidade_codigo': _fonte == 'CP' ? codigo : null,
          'descritor_codigo': _fonte == 'SAEB' ? codigo : null,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${_geradas.length} questão(ões) salvas e etiquetadas!',
            ),
          ),
        );
        _limparCtrlsGeradas();
        setState(() => _geradas = []);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao salvar no banco: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String _descricaoDe(String codigo) {
    for (final m in _matriz) {
      if ('${m['codigo']}' == codigo) return '${m['descricao']}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🤖 Assistente Pedagógico IA'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.nomeAvaliacao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '📝 ${widget.nomeAvaliacao}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),

            // ===== 1) CONFIGURAR MATRIZ =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1️⃣ Matriz de referência',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _fonte,
                            decoration: const InputDecoration(
                              labelText: 'Fonte',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'CP',
                                child: Text('Currículo Paulista'),
                              ),
                              DropdownMenuItem(
                                value: 'SAEB',
                                child: Text('SAEB'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _fonte = v ?? 'CP'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _ano,
                            decoration: const InputDecoration(labelText: 'Ano'),
                            items: const [
                              DropdownMenuItem(value: 5, child: Text('5º ano')),
                              DropdownMenuItem(value: 6, child: Text('6º ano')),
                              DropdownMenuItem(value: 9, child: Text('9º ano')),
                            ],
                            onChanged: (v) => setState(() => _ano = v ?? 6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _carregando ? null : _carregarMatriz,
                          child: _carregando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('🔄 Carregar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ===== 2) ESCOLHER HABILIDADES =====
            if (_matriz.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '2️⃣ Habilidades/descritores (${_selecionadas.length} selecionados)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _matriz.length,
                          itemBuilder: (_, i) {
                            final codigo = '${_matriz[i]['codigo']}';
                            return CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _selecionadas.contains(codigo),
                              title: Text(
                                codigo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${_matriz[i]['descricao']}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selecionadas.add(codigo);
                                } else {
                                  _selecionadas.remove(codigo);
                                }
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ===== 3) PARÂMETROS + GERAR =====
            if (_matriz.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '3️⃣ Gerar questões com IA',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _quantidade,
                              decoration: const InputDecoration(
                                labelText: 'Questões por habilidade',
                              ),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('1')),
                                DropdownMenuItem(value: 2, child: Text('2')),
                                DropdownMenuItem(value: 3, child: Text('3')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _quantidade = v ?? 1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _dificuldade,
                              decoration: const InputDecoration(
                                labelText: 'Dificuldade',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'fácil',
                                  child: Text('Fácil'),
                                ),
                                DropdownMenuItem(
                                  value: 'média',
                                  child: Text('Média'),
                                ),
                                DropdownMenuItem(
                                  value: 'difícil',
                                  child: Text('Difícil'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _dificuldade = v ?? 'média'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contextoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contexto (opcional)',
                          hintText:
                              'Ex.: feira livre, mesada, horta da escola...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _gerando ? null : _gerarQuestoes,
                          icon: _gerando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome),
                          label: const Text('✨ GERAR QUESTÕES COM IA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ===== QUESTÕES GERADAS (editáveis) =====
            for (int i = 0; i < _geradas.length; i++)
              Card(
                color: Colors.purple.shade50,
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              '${_geradas[i]['codigo'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: Colors.deepPurple.shade100,
                          ),
                          const Spacer(),
                          Text(
                            'Questão ${i + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ctrlEnunciado[i],
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Enunciado',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ctrlResposta[i],
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Resposta esperada',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ctrlCriterios[i],
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Critérios de correção',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _ctrlValor[i],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_geradas.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _salvando ? null : _salvarNaAvaliacao,
                    icon: _salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      '💾 SALVAR ${_geradas.length} QUESTÃO(ÕES) NA AVALIAÇÃO',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

            // ===== 4) IDENTIFICAR HABILIDADE =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔍 Tenho uma questão pronta — qual habilidade ela avalia?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _identificarCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText:
                            'Cole aqui o enunciado da questão que você já tem...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _identificando ? null : _identificar,
                        icon: _identificando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: const Text('IDENTIFICAR HABILIDADE'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final r in _resultadosIdent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Text(
                            '${r['aderencia'] ?? '?'}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          '${r['codigo']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _descricaoDe('${r['codigo']}'),
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${r['justificativa'] ?? ''}'),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
