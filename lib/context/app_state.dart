// lib/context/app_state.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/aluno_model.dart';
import '../models/turma_model.dart';
import '../models/avaliacao_model.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppState extends ChangeNotifier {
  String ipServidor = "http://192.168.3.20:5000";

  // 🚨 INICIALIZAÇÃO SEGURA: Sem 'late', usa um getter para garantir que sempre exista
  SupabaseService? _supabaseService;
  SupabaseService get service {
    if (_supabaseService == null) {
      _supabaseService = SupabaseService(ipServidor: ipServidor);
    }
    return _supabaseService!;
  }

  String _disciplinaAtual = "Matemática";
  String _anoSerieAtual = "6º Ano";
  String _bimestreAtual = "1º Bimestre";

  List<Turma> _turmas = [];
  List<Aluno> _alunos = [];
  List<Avaliacao> _avaliacoes = [];
  List<Map<String, dynamic>> _tiposAvaliacao = [];

  Turma? _turmaSelecionada;
  Avaliacao? _avaliacaoSelecionada;

  bool _carregandoDados = false;
  bool _servidorOnline = false;

  String _nomeProfessor = "Professor";
  String _nomeEscola = "Escola Estadual";

  String get disciplinaAtual => _disciplinaAtual;
  String get anoSerieAtual => _anoSerieAtual;
  String get bimestreAtual => _bimestreAtual;

  List<Turma> get turmas => _turmas;
  List<Aluno> get alunos => _alunos;
  List<Avaliacao> get avaliacoes => _avaliacoes;
  List<Map<String, dynamic>> get tiposAvaliacao => _tiposAvaliacao;

  Turma? get turmaSelecionada => _turmaSelecionada;
  Avaliacao? get avaliacaoSelecionada => _avaliacaoSelecionada;

  bool get carregandoDados => _carregandoDados;
  bool get servidorOnline => _servidorOnline;

  String get nomeProfessor => _nomeProfessor;
  String get nomeEscola => _nomeEscola;

  List<String> get listaDisciplinas => [
    "Matemática",
    "Língua Portuguesa",
    "Ciências",
    "História",
    "Geografia",
    "Ensino Religioso",
    "Artes",
    "Educação Física",
  ];

  void setDisciplina(String disciplina) {
    _disciplinaAtual = disciplina;
    notifyListeners();
  }

  void setAnoSerie(String anoSerie) {
    _anoSerieAtual = anoSerie;
    notifyListeners();
  }

  void setBimestre(String bimestre) {
    _bimestreAtual = bimestre;
    notifyListeners();
  }

  void setTurmaSelecionada(Turma? turma) {
    _turmaSelecionada = turma;
    notifyListeners();
  }

  void setAvaliacaoSelecionada(Avaliacao? avaliacao) {
    _avaliacaoSelecionada = avaliacao;
    notifyListeners();
  }

  Future<void> carregarTurmas() async {
    _carregandoDados = true;
    notifyListeners();
    try {
      _turmas = await service.buscarTurmas();
      _servidorOnline = _turmas.isNotEmpty;
    } catch (e) {
      _servidorOnline = false;
    } finally {
      _carregandoDados = false;
      notifyListeners();
    }
  }

  Future<void> carregarAlunosDaTurma(int idTurma) async {
    print(
      "🔄 [AppState] Iniciando carregamento de alunos da turma $idTurma...",
    );
    _carregandoDados = true;
    notifyListeners();
    try {
      // 1. Busca os alunos normalmente
      _alunos = await service.buscarAlunosDaTurma(idTurma);

      // 🚨 2. NOVO: Busca os resultados (notas) salvos no Supabase para esses alunos
      if (_alunos.isNotEmpty) {
        try {
          final supabase = Supabase.instance.client;
          final idsAlunos = _alunos.map((a) => a.id).toList();

          // Pega os resultados de todos os alunos da turma de uma vez
          final resultados = await supabase
              .from('resultados')
              .select('id_aluno, nota_bruta, nota_final, nivel_saeb')
              .inFilter('id_aluno', idsAlunos);

          // Cria um mapa rápido: id_aluno -> resultado
          final Map<int, Map<String, dynamic>> mapaResultados = {};
          for (final r in resultados) {
            mapaResultados[r['id_aluno'] as int] = r;
          }

          // 🚨 3. NOVO: "Mescla" as notas salvas nos objetos Aluno
          int alunosComNota = 0;
          for (final aluno in _alunos) {
            final resultado = mapaResultados[aluno.id];
            if (resultado != null) {
              // Converte os valores do banco para os tipos do modelo Aluno
              final notaBruta = resultado['nota_bruta'];
              final notaFinal = resultado['nota_final'];
              final nivelSaeb = resultado['nivel_saeb']?.toString() ?? '';

              aluno.notaExata = notaBruta is num
                  ? notaBruta.toDouble()
                  : double.tryParse('$notaBruta');
              aluno.notaFinal = notaFinal is num
                  ? notaFinal.toInt()
                  : int.tryParse('$notaFinal');

              // 🚨 Apenas mudamos o status para "Corrigido".
              // O app entende automaticamente que foiCorrigido = true, estaPendente = false, etc.
              aluno.status = "Corrigido";
              alunosComNota++;
            }
          }

          print(
            "✅ [AppState] ${_alunos.length} alunos carregados, $alunosComNota com notas do banco!",
          );
        } catch (eResultados) {
          print(
            "⚠️ [AppState] Não foi possível carregar resultados: $eResultados",
          );
          // Mesmo com erro, continua com os alunos (sem notas)
        }
      } else {
        print("✅ [AppState] Nenhum aluno encontrado nesta turma.");
      }
    } catch (e) {
      print("❌ [AppState] Erro ao carregar alunos: $e");
    } finally {
      _carregandoDados = false;
      notifyListeners();
    }
  }

  Future<void> carregarAvaliacoes() async {
    try {
      _avaliacoes = await service.buscarAvaliacoes();
      notifyListeners();
    } catch (e) {}
  }

  Future<void> carregarGabarito(int idAvaliacao) async {
    try {
      final aval = await service.buscarGabarito(idAvaliacao);
      if (aval != null) {
        _avaliacaoSelecionada = aval;
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> carregarTiposAvaliacao() async {
    try {
      _tiposAvaliacao = await service.buscarTiposAvaliacao();
      notifyListeners();
    } catch (e) {}
  }

  Future<bool> salvarResultado({
    required int idAluno,
    required int idAvaliacao,
    required double notaBruta,
    required double notaFinal,
    required String nivelSaeb,
    String devolutiva = "",
    int acertosBasico = 0,
    int acertosIntermediario = 0,
    int acertosAvancado = 0,
    double percentualAcerto = 0.0,
    List<bool> respostasCorretas = const [],
  }) async {
    try {
      final sucesso = await service.salvarResultado(
        idAluno: idAluno,
        idAvaliacao: idAvaliacao,
        notaBruta: notaBruta,
        notaFinal: notaFinal,
        nivelSaeb: nivelSaeb,
        devolutiva: devolutiva,
        acertosBasico: acertosBasico,
        acertosIntermediario: acertosIntermediario,
        acertosAvancado: acertosAvancado,
        percentualAcerto: percentualAcerto,
        respostasCorretas: respostasCorretas,
      );
      if (sucesso) {
        final index = _alunos.indexWhere((a) => a.id == idAluno);
        if (index != -1) {
          _alunos[index].status = "Corrigido";
          _alunos[index].notaFinal = notaFinal.toInt();
          notifyListeners();
        }
      }
      return sucesso;
    } catch (e) {
      return false;
    }
  }

  Future<void> salvarConfiguracoes({
    required String nomeProfessor,
    String nomeEscola = "Escola Estadual",
  }) async {
    _nomeProfessor = nomeProfessor;
    _nomeEscola = nomeEscola;
    notifyListeners();
  }

  void atualizarStatusAluno(int idAluno, String novoStatus) {
    final index = _alunos.indexWhere((a) => a.id == idAluno);
    if (index != -1) {
      _alunos[index].status = novoStatus;
      notifyListeners();
    }
  }

  // ========================================================================
  // 🌐 GERENCIAMENTO DO IP FLEXÍVEL
  // ========================================================================

  Future<void> carregarConfiguracoes() async {
    final prefs = await SharedPreferences.getInstance();
    ipServidor = prefs.getString('ip_servidor') ?? "http://192.168.3.20:5000";
    print("📡 [AppState] IP do Servidor carregado: $ipServidor");

    // Força a recriação do serviço com o novo IP
    _supabaseService = SupabaseService(ipServidor: ipServidor);
  }

  Future<void> salvarIpServidor(String novoIp) async {
    final prefs = await SharedPreferences.getInstance();
    String ipLimpo = novoIp.trim();

    if (!ipLimpo.startsWith('http://') && !ipLimpo.startsWith('https://')) {
      ipLimpo = 'http://$ipLimpo';
    }
    if (!ipLimpo.contains(':')) {
      ipLimpo = '$ipLimpo:5000';
    }

    await prefs.setString('ip_servidor', ipLimpo);
    ipServidor = ipLimpo;

    _supabaseService = SupabaseService(ipServidor: ipServidor);
    notifyListeners();
    print("💾 [AppState] Novo IP salvo e aplicado: $ipServidor");
  }

  Future<bool> verificarStatusServidor() async {
    try {
      await service.buscarTurmas();
      _servidorOnline = true;
      notifyListeners();
      return true;
    } catch (e) {
      _servidorOnline = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cadastrarAvaliacao({
    required int idTurma,
    required int idTipo,
    required String nome,
    required String dataProva,
    required String disciplina,
    required int numeroQuestoes,
  }) async {
    try {
      final sucesso = await service.criarAvaliacao(
        idTurma: idTurma,
        idTipo: idTipo,
        nome: nome,
        dataProva: dataProva,
        disciplina: disciplina,
        numeroQuestoes: numeroQuestoes,
      );
      if (sucesso) await carregarAvaliacoes();
      return sucesso;
    } catch (e) {
      print("❌ [AppState] Erro ao cadastrar avaliação: $e");
      return false;
    }
  }

  Future<bool> salvarGabaritoDaAvaliacao({
    required int idAvaliacao,
    required List<Map<String, dynamic>> questoes,
  }) async {
    try {
      final sucesso = await service.salvarGabarito(
        idAvaliacao: idAvaliacao,
        questoes: questoes,
      );
      if (sucesso && _avaliacaoSelecionada?.id == idAvaliacao) {
        _avaliacaoSelecionada!.gabarito = questoes
            .map((q) => q['resposta'].toString())
            .toList();
        _avaliacaoSelecionada!.pesos = questoes
            .map((q) => (q['peso'] as num?)?.toDouble() ?? 1.0)
            .toList();
        _avaliacaoSelecionada!.niveis = questoes
            .map((q) => q['nivel'].toString())
            .toList();
        notifyListeners();
      }
      return sucesso;
    } catch (e) {
      print("❌ [AppState] Erro ao salvar gabarito: $e");
      return false;
    }
  }

  Future<bool> adicionarNovoAluno({
    required int idTurma,
    required String nome,
    required int numeroChamada,
  }) async {
    final sucesso =
        await _supabaseService?.adicionarAluno(
          idTurma: idTurma,
          nomeCompleto: nome,
          numeroChamada: numeroChamada,
        ) ??
        false;

    if (sucesso) {
      await carregarAlunosDaTurma(idTurma); // Recarrega a lista
    }
    return sucesso;
  }

  Future<bool> transferirAluno(int idAluno, int idTurma) async {
    final sucesso = await _supabaseService?.transferirAluno(idAluno) ?? false;
    if (sucesso) {
      await carregarAlunosDaTurma(
        idTurma,
      ); // Recarrega a lista removendo o transferido
    }
    return sucesso;
  }
}
