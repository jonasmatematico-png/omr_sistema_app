import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TelaCadastroAvaliacao extends StatefulWidget {
  const TelaCadastroAvaliacao({super.key});

  @override
  State<TelaCadastroAvaliacao> createState() => _TelaCadastroAvaliacaoState();
}

class _TelaCadastroAvaliacaoState extends State<TelaCadastroAvaliacao> {
  final _nomeController = TextEditingController();
  final _pesoController = TextEditingController(text: '1');
  final _questoesController = TextEditingController(text: '10');

  int _bimestre = 3;
  String _modo = 'omr';
  String _tipo = 'Prova';
  DateTime _data = DateTime.now();
  bool _salvando = false;

  final List<String> _tipos = [
    'Prova',
    'Simulado SAEB',
    'Trabalho',
    'Atividade',
    'Projeto',
  ];

  Future<void> _salvar() async {
    if (_nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Dê um nome para a avaliação!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final supabase = Supabase.instance.client;
      // 🚨 CORREÇÃO: removida a coluna 'disciplina' (não existe na tabela)
      await supabase.from('avaliacoes').insert({
        'nome': _nomeController.text.trim(),
        'data_prova': _data.toIso8601String().split('T')[0],
        'numero_questoes': int.tryParse(_questoesController.text) ?? 10,
        'bimestre': _bimestre,
        'peso_media':
            double.tryParse(_pesoController.text.replaceAll(',', '.')) ?? 1.0,
        'modo_correcao': _modo,
        'tipo': _tipo,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Avaliação cadastrada com sucesso!'),
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
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastrar Nova Avaliação'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome (ex: Prova de Frações)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true, // 🚨 CORREÇÃO do overflow
                        value: _tipo,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in _tipos)
                            DropdownMenuItem(
                              value: t,
                              child: Text(t, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _tipo = v ?? 'Prova'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true, // 🚨 CORREÇÃO do overflow
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
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month, color: Colors.teal),
                  title: const Text('Data da avaliação'),
                  subtitle: Text(
                    '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                  ),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _data,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _data = picked);
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Como as notas serão lançadas?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('📷 Câmera (OMR)'),
                      selected: _modo == 'omr',
                      onSelected: (_) => setState(() => _modo = 'omr'),
                    ),
                    ChoiceChip(
                      label: const Text('✍️ Nota manual'),
                      selected: _modo == 'manual',
                      onSelected: (_) => setState(() => _modo = 'manual'),
                    ),
                  ],
                ),
                if (_modo == 'omr') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _questoesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de questões',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _pesoController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Peso na média do bimestre',
                    border: OutlineInputBorder(),
                    helperText: 'Ex: Prova vale 2, trabalho vale 1.',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
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
                    'SALVAR AVALIAÇÃO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
