// lib/models/turma_model.dart
// Define a estrutura de dados de uma Turma no sistema

class Turma {
  final int id;
  final String nome;
  final int? ano;
  final String? serie;

  Turma({
    required this.id,
    required this.nome,
    this.ano,
    this.serie,
  });

  // Fábrica: Cria uma Turma a partir de um JSON (que vem do Supabase)
  factory Turma.fromJson(Map<String, dynamic> json) {
    return Turma(
      id: json['id'] as int,
      nome: json['nome'] as String,
      ano: json['ano'] as int?,
      serie: json['serie'] as String?,
    );
  }

  // Converte a Turma de volta para JSON (para salvar no Supabase)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'ano': ano,
      'serie': serie,
    };
  }

  // Método auxiliar: Extrai o ano/série do nome (ex: "6º Ano A" -> "6º Ano")
  String get anoSerie {
    // Remove a letra da turma no final (A, B, C, D)
    final partes = nome.split(' ');
    if (partes.length >= 2) {
      return '${partes[0]} ${partes[1]}';
    }
    return nome;
  }

  // Método auxiliar: Extrai apenas a letra da turma (ex: "6º Ano A" -> "A")
  String get letraTurma {
    final partes = nome.split(' ');
    if (partes.isNotEmpty) {
      return partes.last;
    }
    return '';
  }
}