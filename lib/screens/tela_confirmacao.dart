import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../context/app_state.dart';

class TelaConfirmacao extends StatefulWidget {
  final File fotoRecortada;
  final String nomeAluno;
  final List<String> respostasDetectadas;
  final Function(double, List<String>) onConfirmar;

  const TelaConfirmacao({
    super.key,
    required this.fotoRecortada,
    required this.nomeAluno,
    required this.respostasDetectadas,
    required this.onConfirmar,
  });

  @override
  State<TelaConfirmacao> createState() => _TelaConfirmacaoState();
}

class _TelaConfirmacaoState extends State<TelaConfirmacao> {
  late List<String> _respostasRevisadas;

  @override
  void initState() {
    super.initState();
    // Começa com as respostas detectadas pela câmera
    _respostasRevisadas = List.from(widget.respostasDetectadas);
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // 🚨 AQUI ESTÁ A CORREÇÃO: Pegamos o gabarito da avaliação selecionada
    final gabaritoOficial = appState.avaliacaoSelecionada?.gabarito ?? [];
    final pesos = appState.avaliacaoSelecionada?.pesos ?? [];

    // Calcula a nota exata baseada nas respostas revisadas e nos pesos
    double notaExata = 0.0;
    for (int i = 0; i < _respostasRevisadas.length; i++) {
      if (i < gabaritoOficial.length && i < pesos.length) {
        if (_respostasRevisadas[i].trim().toUpperCase() ==
            gabaritoOficial[i].trim().toUpperCase()) {
          notaExata += pesos[i];
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Revisão da Correção',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, size: 28),
            tooltip: "Confirmar e Salvar",
            onPressed: () {
              widget.onConfirmar(notaExata, _respostasRevisadas);
              Navigator.pop(context); // Volta para a tela de alunos
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Miniatura da Foto
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Image.file(widget.fotoRecortada, fit: BoxFit.contain),
          ),

          // 2. Informações do Aluno e Nota
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aluno:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        widget.nomeAluno,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Nota Calculada',
                        style: TextStyle(fontSize: 11, color: Colors.green),
                      ),
                      Text(
                        notaExata.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 3. Lista de Revisão das Respostas
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _respostasRevisadas.length,
              itemBuilder: (context, index) {
                final respostaAluno = _respostasRevisadas[index];
                final respostaCerta = index < gabaritoOficial.length
                    ? gabaritoOficial[index]
                    : '?';
                final peso = index < pesos.length ? pesos[index] : 0.0;
                final acertou =
                    respostaAluno.trim().toUpperCase() ==
                    respostaCerta.trim().toUpperCase();

                return Card(
                  elevation: 1,
                  color: acertou ? Colors.white : Colors.red.shade50,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: acertou
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: acertou
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          'Sua resposta: ',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        Text(
                          respostaAluno.isEmpty ? 'Em branco' : respostaAluno,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: acertou
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Gabarito: $respostaCerta',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text('Peso da questão: $peso ponto(s)'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.indigo),
                      tooltip: "Alterar resposta",
                      onPressed: () => _alterarResposta(index),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // 🔄 MÉTODO PARA ALTERAR UMA RESPOSTA MANUALMENTE
  // ====================================================================
  void _alterarResposta(int index) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final opcoes = ['A', 'B', 'C', 'D', 'E', 'Em Branco'];
        return ListView.builder(
          itemCount: opcoes.length,
          itemBuilder: (context, i) {
            return ListTile(
              title: Text(opcoes[i]),
              trailing: _respostasRevisadas[index] == opcoes[i]
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _respostasRevisadas[index] = opcoes[i] == 'Em Branco'
                      ? ''
                      : opcoes[i];
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
