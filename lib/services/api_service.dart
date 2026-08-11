import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // ✅ MÁGICA: Lê o IP direto da memória do celular (o mesmo da TelaConfiguracoes)
  static Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // Se não tiver nada salvo, usa o padrão
    return prefs.getString('ipServidor') ?? 'http://192.168.3.20:5000';
  }

  static Future<List<dynamic>> getTurmas() async {
    final baseUrl = await _getBaseUrl();
    final response = await http.get(Uri.parse('$baseUrl/api/turmas'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Falha ao carregar turmas: ${response.body}');
  }

  static Future<List<dynamic>> getReferenciais({
    String? tipo,
    String? anoSerie,
  }) async {
    final baseUrl = await _getBaseUrl();
    String url = '$baseUrl/api/referenciais';
    List<String> params = [];
    if (tipo != null) params.add('tipo=$tipo');
    if (anoSerie != null) params.add('ano_serie=$anoSerie');

    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Falha ao carregar referenciais: ${response.body}');
  }

  static Future<Map<String, dynamic>> criarAvaliacao(
    Map<String, dynamic> dados,
  ) async {
    final baseUrl = await _getBaseUrl();
    final response = await http.post(
      Uri.parse('$baseUrl/api/avaliacoes'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(dados),
    );

    final responseData = json.decode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return responseData;
    }
    throw Exception(
      responseData['erro'] ?? 'Erro desconhecido ao criar avaliação',
    );
  }
}
