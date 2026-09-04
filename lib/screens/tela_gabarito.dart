import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../context/app_state.dart';

class TelaGabarito extends StatefulWidget {
  const TelaGabarito({super.key});

  @override
  State<TelaGabarito> createState() => _TelaGabaritoState();
}

class _TelaGabaritoState extends State<TelaGabarito> {
  late List<String> _gabaritoLocal;
  late List<double> _pesosLocal;
  late List<String> _niveisLocal;
  late List<String> _descritoresLocal;

  // 🔓 LIMITE LIVRE: de 1 a 30 questões (a folha OMR tem 30 bolinhas)
  static const int MIN_QUESTOES = 1;
  static const int MAX_QUESTOES = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      final aval = appState.avaliacaoSelecionada;

      if (aval != null && aval.gabarito.isNotEmpty) {
        _gabaritoLocal = List.from(aval.gabarito);
        _pesosLocal = List.from(aval.pesos);
        _niveisLocal = List.from(aval.niveis);
        _descritoresLocal = List.from(aval.descritores);
      } else {
        int qtd = aval?.numeroQuestoes ?? 10;
        _gabaritoLocal = List.generate(qtd, (index) => 'A');
        _pesosLocal = List.generate(qtd, (index) => 1.0);
        _niveisLocal = List.generate(qtd, (index) => 'Básico');
        _descritoresLocal = List.generate(qtd, (index) => '');
      }
      setState(() {});
    });
  }

  // ➕ ADICIONA UMA QUESTÃO
  void _addQuestao() {
    if (_gabaritoLocal.length >= MAX_QUESTOES) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Máximo de 30 questões (limite da folha OMR)!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _gabaritoLocal.add('A');
      _pesosLocal.add(1.0);
      _niveisLocal.add('Básico');
      _descritoresLocal.add('');
    });
  }

  // ➖ REMOVE A ÚLTIMA QUESTÃO
  void _removeQuestao() {
    if (_gabaritoLocal.length <= MIN_QUESTOES) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Mínimo de 1 questão!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _gabaritoLocal.removeLast();
      _pesosLocal.removeLast();
      _niveisLocal.removeLast();
      _descritoresLocal.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final aval = appState.avaliacaoSelecionada;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Editar Gabarito Manual',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save, size: 28),
            tooltip: "Salvar Gabarito",
            onPressed: () async {
              if (aval != null) {
                List<Map<String, dynamic>> questoes = [];
                for (int i = 0; i < _gabaritoLocal.length; i++) {
                  questoes.add({
                    'numero': i + 1,
                    'resposta': _gabaritoLocal[i],
                    'peso': _pesosLocal[i],
                    'nivel': _niveisLocal[i],
                    'descritor': _descritoresLocal[i],
                  });
                }

                final sucesso = await appState.salvarGabaritoDaAvaliacao(
                  idAvaliacao: aval.id,
                  questoes: questoes,
                );

                if (sucesso && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Gabarito atualizado com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              }
            },
          ),
        ],
      ),
      body: _gabaritoLocal.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 🔓 NOVO: CONTROLE DE QUANTIDADE (1 a 30)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: Colors.indigo.shade100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, size: 32),
                        color: Colors.indigo,
                        tooltip: 'Remover questão',
                        onPressed: _removeQuestao,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${_gabaritoLocal.length} questões',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.add_circle, size: 32),
                        color: Colors.indigo,
                        tooltip: 'Adicionar questão',
                        onPressed: _addQuestao,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.indigo.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Toque em uma questão para alterar a resposta. Use ➕/➖ para definir a quantidade (1 a 30).',
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _gabaritoLocal.length,
                    itemBuilder: (context, index) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          title: Text('Questão ${index + 1}'),
                          subtitle: Text(
                            'Peso: ${_pesosLocal[index]} | Nível: ${_niveisLocal[index]} | Desc: ${_descritoresLocal[index].isEmpty ? "Nenhum" : _descritoresLocal[index]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _gabaritoLocal[index].isEmpty
                                  ? 'Em branco'
                                  : _gabaritoLocal[index],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          onTap: () => _alterarResposta(index),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _alterarResposta(int index) {
    final opcoes = ['A', 'B', 'C', 'D', 'E', 'Em branco'];
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: opcoes.length,
          itemBuilder: (context, i) {
            final opcao = opcoes[i];
            final valor = opcao == 'Em branco' ? '' : opcao;
            final isSelected = _gabaritoLocal[index] == valor;

            return ListTile(
              title: Text(opcao),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _gabaritoLocal[index] = valor;
                });
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}
