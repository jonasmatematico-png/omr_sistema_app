// lib/models/resultado_model.dart
// Define a estrutura de dados de um Resultado (nota de um aluno em uma avaliação)

class Resultado {
  final int id;
  final int idAluno;
  final int idAvaliacao;
  final double notaBruta;
  final double notaFinal;
  final String nivelSaeb; // "Abaixo do Básico", "Básico", "Adequado", "Avançado"
  final String devolutiva;
  final DateTime? dataCorrecao;
  
  // Dados detalhados (opcionais, para análises mais profundas)
  final int acertosBasico;
  final int acertosIntermediario;
  final int acertosAvancado;
  final double percentualAcerto;
  final List<bool> respostasCorretas; // true = acertou, false = errou

  Resultado({
    this.id = 0,
    required this.idAluno,
    required this.idAvaliacao,
    required this.notaBruta,
    required this.notaFinal,
    required this.nivelSaeb,
    this.devolutiva = "",
    this.dataCorrecao,
    this.acertosBasico = 0,
    this.acertosIntermediario = 0,
    this.acertosAvancado = 0,
    this.percentualAcerto = 0.0,
    this.respostasCorretas = const [],
  });

  // Fábrica: Cria um Resultado a partir de um JSON (que vem do Supabase)
  factory Resultado.fromJson(Map<String, dynamic> json) {
    return Resultado(
      id: json['id'] as int? ?? 0,
      idAluno: json['id_aluno'] as int,
      idAvaliacao: json['id_avaliacao'] as int,
      notaBruta: (json['nota_bruta'] as num?)?.toDouble() ?? 0.0,
      notaFinal: (json['nota_final'] as num?)?.toDouble() ?? 0.0,
      nivelSaeb: json['nivel_saeb'] as String? ?? "Não avaliado",
      devolutiva: json['devolutiva'] as String? ?? "",
      dataCorrecao: json['data_correcao'] != null 
          ? DateTime.tryParse(json['data_correcao']) 
          : null,
      acertosBasico: json['acertos_basico'] as int? ?? 0,
      acertosIntermediario: json['acertos_intermediario'] as int? ?? 0,
      acertosAvancado: json['acertos_avancado'] as int? ?? 0,
      percentualAcerto: (json['percentual_acerto'] as num?)?.toDouble() ?? 0.0,
      respostasCorretas: json['respostas_corretas'] != null
          ? List<bool>.from(json['respostas_corretas'])
          : [],
    );
  }

  // Converte o Resultado de volta para JSON (para salvar no Supabase)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_aluno': idAluno,
      'id_avaliacao': idAvaliacao,
      'nota_bruta': notaBruta,
      'nota_final': notaFinal,
      'nivel_saeb': nivelSaeb,
      'devolutiva': devolutiva,
      'data_correcao': dataCorrecao?.toIso8601String(),
      'acertos_basico': acertosBasico,
      'acertos_intermediario': acertosIntermediario,
      'acertos_avancado': acertosAvancado,
      'percentual_acerto': percentualAcerto,
      'respostas_corretas': respostasCorretas,
    };
  }

  // Método auxiliar: Determina o nível SAEB baseado na nota (0-10)
  static String calcularNivelSaeb(double nota) {
    if (nota >= 8.0) return "Avançado";
    if (nota >= 6.0) return "Adequado";
    if (nota >= 4.0) return "Básico";
    return "Abaixo do Básico";
  }

  // Método auxiliar: Gera uma devolutiva automática baseada no desempenho
  String gerarDevolutivaAutomatica() {
    if (percentualAcerto >= 80) {
      return "Excelente desempenho! O aluno demonstrou domínio avançado dos conteúdos.";
    } else if (percentualAcerto >= 60) {
      return "Bom desempenho! O aluno atingiu o nível adequado, mas pode melhorar em alguns pontos.";
    } else if (percentualAcerto >= 40) {
      return "Desempenho básico. O aluno precisa de reforço em conteúdos fundamentais.";
    } else {
      return "Desempenho abaixo do esperado. Recomenda-se intervenção pedagógica imediata.";
    }
  }

  // Método auxiliar: Verifica se o aluno foi aprovado (nota >= 6)
  bool get foiAprovado => notaFinal >= 6.0;

  // Método auxiliar: Cor da nota para exibição visual
  String get corNota {
    if (notaFinal >= 8.0) return "verde";
    if (notaFinal >= 6.0) return "azul";
    if (notaFinal >= 4.0) return "laranja";
    return "vermelho";
  }
}