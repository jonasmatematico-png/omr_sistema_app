import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Para formatar a data
import '../context/app_state.dart';

class CadastroAvaliacaoScreen extends StatefulWidget {
  const CadastroAvaliacaoScreen({super.key});

  @override
  State<CadastroAvaliacaoScreen> createState() =>
      _CadastroAvaliacaoScreenState();
}

class _CadastroAvaliacaoScreenState extends State<CadastroAvaliacaoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController(text: 'Simulado SAEB');
  final _numQuestoesController = TextEditingController(text: '10');

  String? _tipoSelecionado;
  int? _idTipoSelecionado;
  String? _disciplinaSelecionada;
  int? _idTurmaSelecionada;
  DateTime _dataProva = DateTime.now();

  bool _estaSalvando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.carregarTiposAvaliacao();
      appState.carregarTurmas(); // Garante que as turmas estejam carregadas
    });
    _disciplinaSelecionada = Provider.of<AppState>(
      context,
      listen: false,
    ).disciplinaAtual;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _numQuestoesController.dispose();
    super.dispose();
  }

  Future<void> _selecionarData() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dataProva,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.teal),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _dataProva) {
      setState(() => _dataProva = picked);
    }
  }

  Future<void> _salvarAvaliacao() async {
    if (_formKey.currentState!.validate()) {
      if (_idTurmaSelecionada == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Selecione uma turma'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_idTipoSelecionado == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Selecione um tipo de avaliação'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() => _estaSalvando = true);

      final appState = Provider.of<AppState>(context, listen: false);
      final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataProva);

      final sucesso = await appState.cadastrarAvaliacao(
        idTurma: _idTurmaSelecionada!,
        idTipo: _idTipoSelecionado!,
        nome: _nomeController.text,
        dataProva: dataFormatada,
        disciplina: _disciplinaSelecionada ?? 'Matemática',
        numeroQuestoes: int.tryParse(_numQuestoesController.text) ?? 10,
      );

      setState(() => _estaSalvando = false);

      if (sucesso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Avaliação salva no Supabase com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Volta para a tela anterior
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Erro ao salvar. Verifique o terminal.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Cadastrar Nova Avaliação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _estaSalvando
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📝 Dados da Avaliação',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 1. Turma (NOVO)
                            const Text(
                              'Turma:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: _idTurmaSelecionada,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              hint: const Text('Selecione a turma'),
                              items: appState.turmas.map((turma) {
                                return DropdownMenuItem<int>(
                                  value: turma.id,
                                  child: Text(turma.nome),
                                );
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _idTurmaSelecionada = value),
                              validator: (value) =>
                                  value == null ? 'Selecione uma turma' : null,
                            ),
                            const SizedBox(height: 16),

                            // 2. Tipo de Avaliação
                            const Text(
                              'Tipo de Avaliação:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _tipoSelecionado,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              hint: const Text('Selecione o tipo'),
                              items: appState.tiposAvaliacao.map((tipo) {
                                return DropdownMenuItem<String>(
                                  value: tipo['nome'],
                                  child: Text(tipo['nome']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _tipoSelecionado = value);
                                // Busca o ID correspondente ao nome selecionado
                                final tipoEncontrado = appState.tiposAvaliacao
                                    .firstWhere(
                                      (t) => t['nome'] == value,
                                      orElse: () => {'id': 0},
                                    );
                                _idTipoSelecionado = tipoEncontrado['id'];
                              },
                              validator: (value) =>
                                  value == null ? 'Selecione um tipo' : null,
                            ),
                            const SizedBox(height: 16),

                            // 3. Nome da Avaliação
                            const Text(
                              'Nome da Avaliação:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nomeController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Informe o nome'
                                  : null,
                            ),
                            const SizedBox(height: 16),

                            // 4. Data da Prova (NOVO)
                            const Text(
                              'Data da Prova:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _selecionarData,
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_dataProva),
                                    ),
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Colors.teal,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 5. Disciplina
                            const Text(
                              'Disciplina:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _disciplinaSelecionada,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              items: appState.listaDisciplinas
                                  .map(
                                    (disc) => DropdownMenuItem<String>(
                                      value: disc,
                                      child: Text(disc),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _disciplinaSelecionada = value,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 6. Número de Questões
                            const Text(
                              'Número de Questões:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _numQuestoesController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Informe o número'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _salvarAvaliacao,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'SALVAR AVALIAÇÃO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
