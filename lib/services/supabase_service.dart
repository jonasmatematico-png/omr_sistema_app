// lib/services/supabase_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aluno_model.dart';
import '../models/turma_model.dart';
import '../models/avaliacao_model.dart';

class SupabaseService {
  final String ipServidor;
  final SupabaseClient client = Supabase.instance.client;

  SupabaseService({required this.ipServidor});

  // ====================================================================
  // 🔍 MÉTODOS DE BUSCA (Leitura)
  // ====================================================================

  Future<List<Turma>> buscarTurmas() async {
    try {
      final response = await client
          .from("turmas")
          .select()
          .order('nome', ascending: true);
      return response.map((item) => Turma.fromJson(item)).toList();
    } catch (e) {
      print("❌ [SupabaseService] Erro ao buscar turmas: $e");
      return [];
    }
  }

  Future<List<Aluno>> buscarAlunosDaTurma(int idTurma) async {
    try {
      print(
        "🔍 [SupabaseService] Buscando alunos ATIVOS da turma ID $idTurma...",
      );
      final response = await client
          .from("alunos")
          .select()
          .eq('id_turma', idTurma)
          .eq('status', 'Ativo') // 🚨 FILTRA APENAS ALUNOS ATIVOS
          .order('numero_chamada', ascending: true);

      print(
        "📦 [SupabaseService] Dados brutos recebidos: ${response.length} itens",
      );

      List<Aluno> lista = [];
      for (var item in response) {
        try {
          final itemNormalizado = Map<String, dynamic>.from(item);
          if (item.containsKey('nome_completo') && !item.containsKey('nome')) {
            itemNormalizado['nome'] = item['nome_completo'];
          }
          lista.add(Aluno.fromJson(itemNormalizado));
        } catch (e) {
          print(
            "⚠️ [SupabaseService] Erro ao converter aluno: $e | Dados: $item",
          );
        }
      }
      print(
        "✅ [SupabaseService] ${lista.length} alunos convertidos com sucesso!",
      );
      return lista;
    } catch (e) {
      print("❌ [SupabaseService] Erro ao buscar alunos: $e");
      return [];
    }
  }

  // 🚨 ESTE ERA O MÉTODO QUE ESTAVA FALTANDO!
  Future<List<Avaliacao>> buscarAvaliacoes() async {
    try {
      final response = await client
          .from("avaliacoes")
          .select()
          .order('data_prova', ascending: false);

      List<Avaliacao> lista = [];
      for (var item in response) {
        lista.add(
          Avaliacao(
            id: (item['id'] as num?)?.toInt() ?? 0,
            idTurma: (item['id_turma'] as num?)?.toInt() ?? 0,
            idTipo: (item['id_tipo'] as num?)?.toInt() ?? 0,
            nome: item['nome']?.toString() ?? 'Sem nome',
            dataProva: item['data_prova']?.toString() ?? '',
            numeroQuestoes: (item['numero_questoes'] as num?)?.toInt() ?? 10,
            gabarito: [],
            pesos: [],
            niveis: [],
            descritores: [],
          ),
        );
      }
      return lista;
    } catch (e) {
      print("❌ [SupabaseService] Erro ao buscar avaliações: $e");
      return [];
    }
  }

  Future<Avaliacao?> buscarGabarito(int idAvaliacao) async {
    try {
      final avalResponse = await client
          .from("avaliacoes")
          .select()
          .eq('id', idAvaliacao)
          .single();

      final questoesResponse = await client
          .from("questoes")
          .select("gabarito, peso, nivel, descritor")
          .eq('id_avaliacao', idAvaliacao)
          .order('numero', ascending: true);

      List<String> gabarito = [];
      List<double> pesos = [];
      List<String> niveis = [];
      List<String> descritores = [];

      for (var q in questoesResponse) {
        gabarito.add(q['gabarito']?.toString() ?? 'A');
        pesos.add((q['peso'] as num?)?.toDouble() ?? 1.0);
        niveis.add(q['nivel']?.toString() ?? 'Básico');
        descritores.add(q['descritor']?.toString() ?? '');
      }

      return Avaliacao(
        id: (avalResponse['id'] as num?)?.toInt() ?? 0,
        idTurma: (avalResponse['id_turma'] as num?)?.toInt() ?? 0,
        idTipo: (avalResponse['id_tipo'] as num?)?.toInt() ?? 0,
        nome: avalResponse['nome']?.toString() ?? 'Sem nome',
        dataProva: avalResponse['data_prova']?.toString() ?? '',
        numeroQuestoes:
            (avalResponse['numero_questoes'] as num?)?.toInt() ??
            gabarito.length,
        gabarito: gabarito,
        pesos: pesos,
        niveis: niveis,
        descritores: descritores,
      );
    } catch (e) {
      print("❌ [SupabaseService] Erro ao buscar gabarito: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> buscarTiposAvaliacao() async {
    try {
      final response = await client.from("tipos_avaliacao").select();
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("❌ [SupabaseService] Erro ao buscar tipos: $e");
      return [];
    }
  }

  // ====================================================================
  // 💾 MÉTODOS DE SALVAMENTO (Escrita)
  // ====================================================================

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
      print(
        "💾 [SupabaseService] Salvando/atualizando resultado no Supabase (Upsert)...",
      );

      // 🚨 UPSERT: Atualiza se já existir, insere se for novo.
      // O 'onConflict' garante que ele saiba quando é uma duplicata (mesmo aluno, mesma avaliação)
      final response = await client.from("resultados").upsert({
        "id_aluno": idAluno,
        "id_avaliacao": idAvaliacao,
        "nota_bruta": notaBruta,
        "nota_final": notaFinal,
        "nivel_saeb": nivelSaeb,
        "acertos_basico": acertosBasico,
        "acertos_intermediario": acertosIntermediario,
        "acertos_avancado": acertosAvancado,
        "percentual_acerto": percentualAcerto,
        "data_correcao": DateTime.now().toIso8601String(),
      }, onConflict: 'id_aluno, id_avaliacao').select();

      if (response.isNotEmpty) {
        print(
          "✅ [SupabaseService] Resultado salvo/atualizado com sucesso! ID: ${response.first['id']}",
        );
        return true;
      }
      return false;
    } catch (e) {
      print("❌ [SupabaseService] Erro ao salvar resultado: $e");
      return false;
    }
  }

  Future<bool> criarAvaliacao({
    required int idTurma,
    required int idTipo,
    required String nome,
    required String dataProva,
    required String disciplina,
    required int numeroQuestoes,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$ipServidor/api/avaliacoes/criar"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              'id_turma': idTurma,
              'id_tipo': idTipo,
              'nome': nome,
              'data_prova': dataProva,
              'disciplina': disciplina,
              'numero_questoes': numeroQuestoes,
              'status': 'ativa',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final dados = jsonDecode(response.body);
        return dados['sucesso'] == true;
      }
      return false;
    } catch (e) {
      print("❌ [SupabaseService] Erro ao criar avaliação: $e");
      return false;
    }
  }

  Future<bool> salvarGabarito({
    required int idAvaliacao,
    required List<Map<String, dynamic>> questoes,
  }) async {
    try {
      print("💾 [SupabaseService] Enviando gabarito para o Python...");
      final response = await http
          .post(
            Uri.parse("$ipServidor/api/avaliacoes/gabarito/salvar"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              'id_avaliacao': idAvaliacao,
              'questoes': questoes,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final dados = jsonDecode(response.body);
        if (dados['sucesso'] == true) {
          print("✅ [SupabaseService] Gabarito salvo com sucesso!");
          return true;
        }
      }
      print("⚠️ [SupabaseService] Erro ao salvar gabarito: ${response.body}");
      return false;
    } catch (e) {
      print(
        "❌ [SupabaseService] Erro de conexão/timeout ao salvar gabarito: $e",
      );
      return false;
    }
  }

  // ====================================================================
  // 🆕 NOVOS MÉTODOS: GERENCIAMENTO DE ALUNOS
  // ====================================================================

  Future<bool> adicionarAluno({
    required int idTurma,
    required String nomeCompleto,
    required int numeroChamada,
  }) async {
    try {
      final response = await client.from("alunos").insert({
        "id_turma": idTurma,
        "nome_completo": nomeCompleto,
        "numero_chamada": numeroChamada,
        "status": "Ativo",
      }).select();
      return response.isNotEmpty;
    } catch (e) {
      print("❌ [SupabaseService] Erro ao adicionar aluno: $e");
      return false;
    }
  }

  Future<bool> transferirAluno(int idAluno) async {
    try {
      // 🚨 CORREÇÃO: Removido o .execute() que é de versões antigas do Supabase.
      // Nas versões atuais, a chamada é executada automaticamente.
      await client
          .from("alunos")
          .update({"status": "Transferido"})
          .eq("id", idAluno);
      return true;
    } catch (e) {
      print("❌ [SupabaseService] Erro ao transferir aluno: $e");
      return false;
    }
  }
}
