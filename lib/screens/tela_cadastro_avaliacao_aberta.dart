import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 📝 Rascunho de questão aberta
class _QuestaoDraft {
  final TextEditingController enunciado = TextEditingController();
  final TextEditingController resposta = TextEditingController();
  final TextEditingController valor = TextEditingController(text: '2');
}

class TelaCadastroAvaliacaoAberta extends StatefulWidget {
  const TelaCadastroAvaliacaoAberta({super.key});

  @override
  State<TelaCadastroAvaliacaoAberta> createState() =>
      _TelaCadastroAvaliacaoAbertaState();
}

class _TelaCadastroAvaliacaoAbertaState
    extends State<TelaCadastroAvaliacaoAberta> {
  final _nomeController = TextEditingController();
  final _pesoController = TextEditingController(text: '1');
  int _bimestre = 3;
  bool _salvando = false;
  final List<_QuestaoDraft> _questoes = [_QuestaoDraft()];

  void _addQuestao() => setState(() => _questoes.add(_QuestaoDraft()));

  void _removeQuestao(int i) {
    if (_questoes.length > 1) setState(() => _questoes.removeAt(i));
  }

  Future<void> _salvar() async {
    if (_nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Dê um nome para a prova!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    for (int i = 0; i < _questoes.length; i++) {
      if (_questoes[i].enunciado.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ A questão ${i + 1} está sem enunciado!'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _salvando = true);
    try {
      final supabase = Supabase.instance.client;

      // 1) Cria a avaliação (modo 'aberta') e pega o ID dela
      final resp = await supabase
          .from('avaliacoes')
          .insert({
            'nome': _nomeController.text.trim(),
            'data_prova': DateTime.now().toIso8601String().split('T')[0],
            'numero_questoes': _questoes.length,
            'bimestre': _bimestre,
            'peso_media':
                double.tryParse(_pesoController.text.replaceAll(',', '.')) ??
                1.0,
            'modo_correcao': 'aberta',
            'tipo': 'Prova Aberta',
          })
          .select('id')
          .single();

      final int idAval = resp['id'] as int;

      // 2) Salva as questões vinculadas a ela
      final List<Map<String, dynamic>> linhas = [];
      for (int i = 0; i < _questoes.length; i++) {
        linhas.add({
          'id_avaliacao': idAval,
          'numero': i + 1,
          'enunciado': _questoes[i].enunciado.text.trim(),
          'resposta_esperada': _questoes[i].resposta.text.trim(),
          'valor':
              double.tryParse(_questoes[i].valor.text.replaceAll(',', '.')) ??
              2.0,
        });
      }
      await supabase.from('questoes_abertas').insert(linhas);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Prova aberta cadastrada com ${_questoes.length} questão(ões)!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _buildQuestaoCard(int i) {
    final q = _questoes[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.teal,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Questão ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => _removeQuestao(i),
                ),
              ],
            ),
            TextField(
              controller: q.enunciado,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Enunciado',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: q.resposta,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Resposta esperada / critério',
                border: OutlineInputBorder(),
                helperText: 'Ex: "12, aceitando conta armada correta"',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: q.valor,
              keyboardType: const TextInputType.numberWithOptions(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastrar Prova Aberta'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome (ex: Prova Aberta - Frações)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: _bimestre,
                    decoration: const InputDecoration(
                      labelText: 'Bimestre',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (int i = 1; i <= 4; i++)
                        DropdownMenuItem(value: i, child: Text('$iº')),
                    ],
                    onChanged: (v) => setState(() => _bimestre = v ?? 3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pesoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Peso na média',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'QUESTÕES (${_questoes.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _addQuestao,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _questoes.length; i++) _buildQuestaoCard(i),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text(
                  'SALVAR PROVA ABERTA',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
