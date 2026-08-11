// lib/models/avaliacao_model.dart
// Define a estrutura de dados de uma Avaliação no sistema

class Avaliacao {
  final int id;
  final int idTurma;
  final int idTipo;
  final String nome;
  final String dataProva;
  final int numeroQuestoes;

  // 🚨 REMOVEMOS O 'final' DESTAS LISTAS PARA PERMITIR EDIÇÃO LOCAL
  List<String> gabarito;
  List<double> pesos;
  List<String> niveis;
  List<String> descritores;

  Avaliacao({
    required this.id,
    required this.idTurma,
    required this.idTipo,
    required this.nome,
    required this.dataProva,
    required this.numeroQuestoes,
    List<String>? gabarito,
    List<double>? pesos,
    List<String>? niveis,
    List<String>? descritores,
  }) : gabarito = gabarito ?? [],
       pesos = pesos ?? [],
       niveis = niveis ?? [],
       descritores = descritores ?? [];

  factory Avaliacao.fromJson(Map<String, dynamic> json) {
    return Avaliacao(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idTurma: (json['id_turma'] as num?)?.toInt() ?? 0,
      idTipo: (json['id_tipo'] as num?)?.toInt() ?? 0,
      nome: json['nome']?.toString() ?? 'Sem nome',
      dataProva: json['data_prova']?.toString() ?? '',
      numeroQuestoes: (json['numero_questoes'] as num?)?.toInt() ?? 10,

      gabarito: json['gabarito'] != null
          ? List<String>.from(json['gabarito'])
          : [],
      pesos: json['pesos'] != null
          ? List<double>.from(json['pesos'].map((e) => (e as num).toDouble()))
          : [],
      niveis: json['niveis'] != null ? List<String>.from(json['niveis']) : [],
      descritores: json['descritores'] != null
          ? List<String>.from(json['descritores'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_turma': idTurma,
      'id_tipo': idTipo,
      'nome': nome,
      'data_prova': dataProva,
      'numero_questoes': numeroQuestoes,
      'gabarito': gabarito,
      'pesos': pesos,
      'niveis': niveis,
      'descritores': descritores,
    };
  }

  // Método auxiliar para saber se o gabarito já foi preenchido
  bool get gabaritoCompleto =>
      gabarito.isNotEmpty && gabarito.length == numeroQuestoes;
}
