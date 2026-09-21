import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../context/app_state.dart';

class TelaDiario extends StatefulWidget {
  const TelaDiario({super.key});

  @override
  State<TelaDiario> createState() => _TelaDiarioState();
}

class _Contagem {
  int vistos = 0;
  int positivos = 0;
}

class _TelaDiarioState extends State<TelaDiario> {
  bool _carregando = true;
  final Map<int, _Contagem> _contagens = {};
  late DateTime _mes;

  static const _MESES = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  @override
  void initState() {
    super.initState();
    _mes = DateTime.now();
    _carregarContagens();
  }

  String get _inicioMes =>
      '${_mes.year.toString().padLeft(4, '0')}-${_mes.month.toString().padLeft(2, '0')}-01';

  String get _inicioProximoMes {
    final m = _mes.month == 12 ? 1 : _mes.month + 1;
    final y = _mes.month == 12 ? _mes.year + 1 : _mes.year;
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-01';
  }

  Future<void> _carregarContagens() async {
    final appState = Provider.of<AppState>(context, listen: false);
    setState(() => _carregando = true);
    try {
      final ids = appState.alunos.map((a) => a.id).toList();
      if (ids.isEmpty) {
        setState(() => _carregando = false);
        return;
      }

      // ✅ CORREÇÃO: sem .execute(), retorno direto é a lista
      final resp = await Supabase.instance.client
          .from('diario')
          .select('id_aluno, tipo')
          .inFilter('id_aluno', ids)
          .gte('data', _inicioMes)
          .lt('data', _inicioProximoMes);

      final map = <int, _Contagem>{};
      for (final row in resp) {
        final id = row['id_aluno'] as int;
        final tipo = row['tipo'] as String;
        final reg = map.putIfAbsent(id, () => _Contagem());
        if (tipo == 'visto') reg.vistos++;
        if (tipo == 'positivo') reg.positivos++;
      }
      setState(() {
        _contagens.clear();
        _contagens.addAll(map);
        _carregando = false;
      });
    } catch (e) {
      setState(() => _carregando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao carregar diário: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _registrar(int idAluno, String tipo, String nome) async {
    try {
      await Supabase.instance.client.from('diario').insert({
        'id_aluno': idAluno,
        'tipo': tipo,
        'data': DateTime.now().toIso8601String().substring(0, 10),
      });
      setState(() {
        final reg = _contagens.putIfAbsent(idAluno, () => _Contagem());
        if (tipo == 'visto')
          reg.vistos++;
        else
          reg.positivos++;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tipo == 'visto'
                  ? '👁️ Visto de $nome registrado!'
                  : '⭐ Positivo de $nome registrado!',
            ),
            backgroundColor: tipo == 'visto' ? Colors.blue : Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao registrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _desfazer(int idAluno, String tipo, String nome) async {
    try {
      // ✅ CORREÇÃO: sem .execute(), retorno direto é a lista
      final resp = await Supabase.instance.client
          .from('diario')
          .select('id')
          .eq('id_aluno', idAluno)
          .eq('tipo', tipo)
          .gte('data', _inicioMes)
          .lt('data', _inicioProximoMes)
          .order('created_at', ascending: false)
          .limit(1);

      if (resp.isNotEmpty) {
        await Supabase.instance.client
            .from('diario')
            .delete()
            .eq('id', resp[0]['id']);
        setState(() {
          final reg = _contagens.putIfAbsent(idAluno, () => _Contagem());
          if (tipo == 'visto' && reg.vistos > 0) reg.vistos--;
          if (tipo == 'positivo' && reg.positivos > 0) reg.positivos--;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '↩️ Último ${tipo == 'visto' ? 'visto' : 'positivo'} de $nome desfeito.',
              ),
              backgroundColor: Colors.grey.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao desfazer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final alunos = appState.alunos;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          '📔 Diário de Classe',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Seletor de mês
          Container(
            color: Colors.indigo.shade50,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(
                      () => _mes = DateTime(_mes.year, _mes.month - 1, 1),
                    );
                    _carregarContagens();
                  },
                ),
                Text(
                  '${_MESES[_mes.month - 1]} de ${_mes.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.indigo,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(
                      () => _mes = DateTime(_mes.year, _mes.month + 1, 1),
                    );
                    _carregarContagens();
                  },
                ),
              ],
            ),
          ),
          Container(
            color: Colors.indigo.shade50,
            padding: const EdgeInsets.only(bottom: 8),
            child: const Text(
              'Toque = registrar • Segure = desfazer o último',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),

          _carregando
              ? const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.indigo),
                  ),
                )
              : Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: alunos.length,
                    itemBuilder: (context, index) {
                      final aluno = alunos[index];
                      final reg = _contagens[aluno.id] ?? _Contagem();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        child: ListTile(
                          title: Text(
                            '${aluno.numeroChamada ?? (index + 1)}. ${aluno.nome}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Botão VISTO
                              InkWell(
                                onTap: () =>
                                    _registrar(aluno.id, 'visto', aluno.nome),
                                onLongPress: () =>
                                    _desfazer(aluno.id, 'visto', aluno.nome),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.blue),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.visibility,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${reg.vistos}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Botão POSITIVO
                              InkWell(
                                onTap: () => _registrar(
                                  aluno.id,
                                  'positivo',
                                  aluno.nome,
                                ),
                                onLongPress: () =>
                                    _desfazer(aluno.id, 'positivo', aluno.nome),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.orange),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${reg.positivos}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
}
