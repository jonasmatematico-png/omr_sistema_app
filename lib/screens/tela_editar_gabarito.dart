import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../context/app_state.dart';
import '../models/avaliacao_model.dart';

class TelaEditarGabarito extends StatefulWidget {
  final Avaliacao avaliacao;
  const TelaEditarGabarito({super.key, required this.avaliacao});

  @override
  State<TelaEditarGabarito> createState() => _TelaEditarGabaritoState();
}

class _TelaEditarGabaritoState extends State<TelaEditarGabarito> {
  late int _numeroQuestoes;
  late List<String> _respostas;
  late List<double> _pesos;
  late List<String> _niveis;
  late List<String> _descritores;

  late List<TextEditingController> _pesoControllers;
  late List<TextEditingController> _descritorControllers;
  bool _estaSalvando = false;

  final List<String> _opcoesResposta = ['A', 'B', 'C', 'D', 'E'];
  final List<String> _opcoesNivel = ['Básico', 'Intermediário', 'Avançado'];

  @override
  void initState() {
    super.initState();
    _numeroQuestoes = widget.avaliacao.numeroQuestoes > 0
        ? widget.avaliacao.numeroQuestoes
        : 10;

    // 🚨 BLINDAGEM CONTRA NULL: Garante que sempre sejam listas válidas
    final gabaritoRaw = widget.avaliacao.gabarito;
    final pesosRaw = widget.avaliacao.pesos;
    final niveisRaw = widget.avaliacao.niveis;
    final descritoresRaw = widget.avaliacao.descritores;

    _respostas = List<String>.from(
      gabaritoRaw.isEmpty
          ? List.generate(_numeroQuestoes, (i) => 'A')
          : gabaritoRaw,
    );
    _pesos = List<double>.from(
      pesosRaw.isEmpty ? List.generate(_numeroQuestoes, (i) => 1.0) : pesosRaw,
    );
    _niveis = List<String>.from(
      niveisRaw.isEmpty
          ? List.generate(_numeroQuestoes, (i) => 'Básico')
          : niveisRaw,
    );
    _descritores = List<String>.from(
      descritoresRaw.isEmpty
          ? List.generate(_numeroQuestoes, (i) => '')
          : descritoresRaw,
    );

    // Ajusta o tamanho das listas se o número de questões for diferente
    while (_respostas.length < _numeroQuestoes) {
      _respostas.add('A');
      _pesos.add(1.0);
      _niveis.add('Básico');
      _descritores.add('');
    }
    while (_respostas.length > _numeroQuestoes) {
      _respostas.removeLast();
      _pesos.removeLast();
      _niveis.removeLast();
      _descritores.removeLast();
    }

    _pesoControllers = List.generate(
      _numeroQuestoes,
      (i) => TextEditingController(text: _pesos[i].toStringAsFixed(2)),
    );
    _descritorControllers = List.generate(
      _numeroQuestoes,
      (i) => TextEditingController(text: _descritores[i]),
    );
  }

  @override
  void dispose() {
    for (var c in _pesoControllers) c.dispose();
    for (var c in _descritorControllers) c.dispose();
    super.dispose();
  }

  void _atualizarNumeroQuestoes(int novoNumero) {
    setState(() {
      _numeroQuestoes = novoNumero;
      while (_respostas.length < _numeroQuestoes) {
        _respostas.add('A');
        _pesos.add(1.0);
        _niveis.add('Básico');
        _descritores.add('');
        _pesoControllers.add(TextEditingController(text: "1.00"));
        _descritorControllers.add(TextEditingController(text: ""));
      }
      while (_respostas.length > _numeroQuestoes) {
        _respostas.removeLast();
        _pesos.removeLast();
        _niveis.removeLast();
        _descritores.removeLast();
        _pesoControllers.removeLast().dispose();
        _descritorControllers.removeLast().dispose();
      }
    });
  }

  Future<void> _salvarGabarito() async {
    setState(() => _estaSalvando = true);
    final appState = Provider.of<AppState>(context, listen: false);

    List<Map<String, dynamic>> questoes = [];
    for (int i = 0; i < _numeroQuestoes; i++) {
      questoes.add({
        'numero': i + 1,
        'resposta': _respostas[i],
        'peso': _pesos[i],
        'nivel': _niveis[i],
        'descritor': _descritores[i],
      });
    }

    final sucesso = await appState.salvarGabaritoDaAvaliacao(
      idAvaliacao: widget.avaliacao.id,
      questoes: questoes,
    );

    setState(() => _estaSalvando = false);

    if (sucesso && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Gabarito de ${_numeroQuestoes} questões salvo!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Erro ao salvar. Verifique o terminal Python.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Gabarito: ${widget.avaliacao.nome}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (!_estaSalvando)
            IconButton(
              icon: const Icon(Icons.save, size: 28),
              onPressed: _salvarGabarito,
            ),
        ],
      ),
      body: _estaSalvando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.indigo),
                  SizedBox(height: 16),
                  Text(
                    'Salvando no Supabase...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.indigo.shade50,
                  child: Row(
                    children: [
                      const Text(
                        'Questões:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _numeroQuestoes,
                        items: [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]
                            .map(
                              (n) =>
                                  DropdownMenuItem(value: n, child: Text('$n')),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) _atualizarNumeroQuestoes(value);
                        },
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade300),
                        ),
                        child: Text(
                          'Total: ${_pesos.fold(0.0, (s, p) => s + p).toStringAsFixed(2)} pts',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _numeroQuestoes,
                    itemBuilder: (context, index) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.indigo.shade100,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: _respostas[index],
                                underline: const SizedBox(),
                                items: _opcoesResposta
                                    .map(
                                      (r) => DropdownMenuItem(
                                        value: r,
                                        child: Container(
                                          width: 32,
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: Colors.teal,
                                            ),
                                          ),
                                          child: Text(
                                            r,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null)
                                    setState(() => _respostas[index] = value);
                                },
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: TextField(
                                  controller: _pesoControllers[index],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: 'Peso',
                                    labelStyle: const TextStyle(fontSize: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    final peso = double.tryParse(
                                      value.replaceAll(',', '.'),
                                    );
                                    if (peso != null)
                                      setState(() => _pesos[index] = peso);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: _niveis[index],
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  items: _opcoesNivel
                                      .map(
                                        (n) => DropdownMenuItem(
                                          value: n,
                                          child: Text(
                                            n,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null)
                                      setState(() => _niveis[index] = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 60,
                                child: TextField(
                                  controller: _descritorControllers[index],
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    hintText: 'D1',
                                    hintStyle: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                    labelStyle: const TextStyle(fontSize: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(
                                      () => _descritores[index] = value
                                          .toUpperCase(),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _salvarGabarito,
                      icon: const Icon(Icons.save),
                      label: const Text(
                        'SALVAR GABARITO COMPLETO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
