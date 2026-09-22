import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tela_assistente_ia.dart';

class TelaCadastroAvaliacao extends StatefulWidget {
  const TelaCadastroAvaliacao({super.key});

  @override
  State<TelaCadastroAvaliacao> createState() => _TelaCadastroAvaliacaoState();
}

class _TelaCadastroAvaliacaoState extends State<TelaCadastroAvaliacao> {
  final _nomeController = TextEditingController();
  final _pesoController = TextEditingController(text: '1');
  final _questoesController = TextEditingController(text: '10');

  int? _idAvaliacaoSalva;
  int _bimestre = 3;
  String _modo = 'omr';
  String _tipo = 'Prova';
  DateTime _data = DateTime.now();
  bool _salvando = false;

  final List<String> _tipos = [
    'Prova',
    'Prova Aberta',
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
      final resp = await supabase
          .from('avaliacoes')
          .insert({
            'nome': _nomeController.text.trim(),
            'data_prova': _data.toIso8601String().split('T')[0],
            'numero_questoes': int.tryParse(_questoesController.text) ?? 10,
            'bimestre': _bimestre,
            'peso_media':
                double.tryParse(_pesoController.text.replaceAll(',', '.')) ??
                1.0,
            'modo_correcao': _modo,
            'tipo': _tipo,
          })
          .select('id')
          .single();

      setState(() {
        _idAvaliacaoSalva = resp['id'] as int;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Salvo! Agora o botão roxo está liberado.'),
            backgroundColor: Colors.green,
          ),
        );
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

  void _irParaAssistenteIA() {
    if (_idAvaliacaoSalva == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Preencha o nome e clique em SALVAR primeiro!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelaAssistenteIA(
          avaliacaoId: _idAvaliacaoSalva,
          nomeAvaliacao: _nomeController.text,
        ),
      ),
    );
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
                        isExpanded: true,
                        value: _tipo,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: _tipos
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _tipo = v ?? 'Prova'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: _bimestre,
                        decoration: const InputDecoration(
                          labelText: 'Bimestre',
                          border: OutlineInputBorder(),
                        ),
                        items: [1, 2, 3, 4]
                            .map(
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text('$iº'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _bimestre = v ?? 3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month, color: Colors.teal),
                  title: const Text('Data'),
                  subtitle: Text('${_data.day}/${_data.month}/${_data.year}'),
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
                      label: const Text('✍️ Nota manual / Aberta'),
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
                    labelText: 'Peso na média',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                // BOTÃO DE SALVAR
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
                    '💾 SALVAR E CONTINUAR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // 🚨 BOTÃO ROXO SEMPRE VISÍVEL PARA TESTE 🚨
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _irParaAssistenteIA,
                    icon: const Icon(Icons.smart_toy, color: Colors.white),
                    label: const Text(
                      '🤖 ASSISTENTE DE IA: GERAR QUESTÕES',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    label: const Text(
                      'FINALIZAR E VOLTAR',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ], // Fecha children do Column
            ), // Fecha Column
          ), // Fecha Padding
        ), // Fecha Card
      ), // Fecha SingleChildScrollView
    ); // Fecha return Scaffold
  } // Fecha método build
} // Fecha classe _TelaCadastroAvaliacaoState
