// lib/models/aluno_model.dart
// Define a estrutura de dados de um Aluno no sistema

class Aluno {
  final int id;
  final String nome;
  final int idTurma;
  final int? numeroChamada;

  // 🚨 CORREÇÃO: Removido o 'final' para permitir que o app mude o status (ex: para "Ausente" ou "Corrigido")
  String status;

  double? notaExata;
  int? notaFinal;
  List<String> respostas;

  Aluno({
    required this.id,
    required this.nome,
    required this.idTurma,
    this.numeroChamada,
    this.status = "Ativo", // Padrão inicial
    this.notaExata,
    this.notaFinal,
    this.respostas = const [],
  });

  factory Aluno.fromJson(Map<String, dynamic> json) {
    return Aluno(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nome:
          json['nome']?.toString() ??
          json['nome_completo']?.toString() ??
          'Nome não informado',
      idTurma: (json['id_turma'] as num?)?.toInt() ?? 0,
      numeroChamada: (json['numero_chamada'] as num?)?.toInt(),
      status: json['status']?.toString() ?? "Ativo",
      notaExata: json['nota_exata'] != null
          ? double.tryParse(json['nota_exata'].toString())
          : null,
      notaFinal: (json['nota'] as num?)?.toInt(),
      respostas: json['respostas'] != null
          ? List<String>.from(json['respostas'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'id_turma': idTurma,
      'numero_chamada': numeroChamada,
      'status': status,
      'nota_exata': notaExata?.toString(),
      'nota': notaFinal,
      'respostas': respostas,
    };
  }

  // Métodos auxiliares de verificação
  bool get foiCorrigido => status == "Corrigido";
  bool get estaAusente => status == "Ausente";
  bool get estaPendente => status == "Pendente" || status == "Ativo";
  bool get estaTransferido => status == "Transferido";
}
