import 'dart:io'; // Import necessário para SocketException
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import '../context/app_state.dart';
import '../models/aluno_model.dart';
import '../models/resultado_model.dart';
import 'tela_gabarito.dart';
import 'tela_confirmacao.dart';
import 'tela_resultado_turma.dart';
import 'tela_analise.dart';
import 'tela_dashboard.dart'; // 🚨 IMPORT DO DASHBOARD ADICIONADO AQUI

class TelaAlunos extends StatefulWidget {
  const TelaAlunos({super.key});

  @override
  State<TelaAlunos> createState() => _TelaAlunosState();
}

class _TelaAlunosState extends State<TelaAlunos> {
  bool processandoFoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.turmaSelecionada != null) {
        appState.carregarAlunosDaTurma(appState.turmaSelecionada!.id);
      }
    });
  }

  Future<void> _salvarCorrecaoInteligente(
    Aluno aluno,
    double notaExata,
    List<String> respostas,
  ) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final avaliacao = appState.avaliacaoSelecionada;

    if (avaliacao == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Selecione uma avaliação primeiro!"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      int acertosBasico = 0, acertosInter = 0, acertosAvanc = 0;
      List<bool> respostasCorretas = [];

      for (int i = 0; i < respostas.length; i++) {
        if (i >= avaliacao.gabarito.length) break; // Proteção extra
        bool acertou =
            (respostas[i].trim().toUpperCase() ==
            avaliacao.gabarito[i].trim().toUpperCase());
        respostasCorretas.add(acertou);

        if (acertou && i < avaliacao.niveis.length) {
          String nivel = avaliacao.niveis[i].toLowerCase();
          if (nivel.contains("básic"))
            acertosBasico++;
          else if (nivel.contains("inter"))
            acertosInter++;
          else if (nivel.contains("avanç"))
            acertosAvanc++;
        }
      }

      double percentual =
          (respostasCorretas.where((e) => e).length /
              avaliacao.gabarito.length) *
          100;
      String nivelSaeb = Resultado.calcularNivelSaeb(notaExata);
      String devolutiva = "Corrigido via App Flutter 2.0. Nota: $notaExata";

      bool sucesso = await appState.salvarResultado(
        idAluno: aluno.id,
        idAvaliacao: avaliacao.id,
        notaBruta: notaExata,
        notaFinal: (notaExata + 0.5).toInt().toDouble(),
        nivelSaeb: nivelSaeb,
        devolutiva: devolutiva,
        acertosBasico: acertosBasico,
        acertosIntermediario: acertosInter,
        acertosAvancado: acertosAvanc,
        percentualAcerto: percentual,
        respostasCorretas: respostasCorretas,
      );

      if (sucesso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ Nota ${notaExata.toStringAsFixed(2)} de ${aluno.nome} salva!",
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Erro ao salvar: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selecionarAvaliacao() async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.carregarAvaliacoes();

    if (appState.avaliacoes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Nenhuma avaliação encontrada."),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: appState.avaliacoes.length,
          itemBuilder: (context, index) {
            final aval = appState.avaliacoes[index];
            return ListTile(
              leading: const Icon(Icons.assignment, color: Colors.teal),
              title: Text(aval.nome),
              subtitle: Text("${aval.numeroQuestoes} questões"),
              onTap: () async {
                Navigator.pop(context);
                await appState.carregarGabarito(aval.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("✅ Gabarito de '${aval.nome}' carregado!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> _abrirCameraCorrecao({int? indexEspecifico}) async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.avaliacaoSelecionada == null ||
        appState.avaliacaoSelecionada!.gabarito.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Carregue um gabarito antes!"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      DocumentScannerOptions options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: false,
      );
      final documentScanner = DocumentScanner(options: options);
      DocumentScanningResult result = await documentScanner.scanDocument();

      if (result.images != null && result.images!.isNotEmpty) {
        File fotoRecortada = File(result.images!.first);

        int indexAlvo =
            indexEspecifico ??
            appState.alunos.indexWhere((a) => a.estaPendente);

        if (indexAlvo != -1 && mounted) {
          Aluno alunoAlvo = appState.alunos[indexAlvo];
          setState(() => processandoFoto = true);
          List<String> respostasParaRevisar = [];

          try {
            // 🔹 PASSO 1: TESTE DE CONECTIVIDADE ANTES DO ENVIO
            String urlServidor = appState.ipServidor;
            print("🔍 Testando conectividade com: $urlServidor");
            final responseConexao = await http
                .get(Uri.parse(urlServidor))
                .timeout(const Duration(seconds: 15));
            print("✅ Conectividade OK. Status: ${responseConexao.statusCode}");

            // 2. Cria a requisição para o servidor Python
            var request = http.MultipartRequest(
              'POST',
              Uri.parse("$urlServidor/corrigir"), // Concatenação segura
            );

            // 3. Adiciona a foto recortada
            request.files.add(
              await http.MultipartFile.fromPath('image', fotoRecortada.path),
            );

            // 4. Adiciona o gabarito e os IDs
            request.fields['gabarito'] = jsonEncode(
              appState.avaliacaoSelecionada!.gabarito,
            );
            request.fields['id_aluno'] = alunoAlvo.id.toString();
            request.fields['id_avaliacao'] = appState.avaliacaoSelecionada!.id
                .toString();

            // 5. Envia e aguarda a resposta (timeout aumentado)
            var response = await request.send().timeout(
              const Duration(seconds: 90), // Timeout longo para Render Free
            );

            // 6. Trata a resposta
            if (response.statusCode == 200) {
              var respStr = await response.stream.bytesToString();
              var jsonResp = jsonDecode(respStr);

              if (jsonResp['sucesso'] == true &&
                  jsonResp['resultado'] != null) {
                print("✅ Correção recebida do servidor com sucesso!");

                // 7. ATRIBUI AS RESPOSTAS LIDAS PELO PYTHON
                if (jsonResp['resultado']['respostas'] != null) {
                  respostasParaRevisar = List<String>.from(
                    jsonResp['resultado']['respostas'],
                  );
                  print(
                    "👁️ Respostas recebidas do Python: $respostasParaRevisar",
                  );
                } else {
                  print("⚠️ Servidor não retornou lista de respostas.");
                }
              } else {
                print(
                  "❌ Erro retornado pelo servidor: ${jsonResp['erro'] ?? 'Desconhecido'}",
                );
                // Mesmo com erro de lógica, tenta obter as respostas se vierem
                if (jsonResp['resultado']?['respostas'] != null) {
                  respostasParaRevisar = List<String>.from(
                    jsonResp['resultado']['respostas'],
                  );
                  print(
                    "👁️ Tentando usar respostas mesmo com erro: $respostasParaRevisar",
                  );
                }
              }
            } else {
              // Se o status não for 200, é um erro HTTP
              String errorBody = await response.stream.bytesToString();
              print("❌ Erro HTTP ${response.statusCode}: $errorBody");
            }
          } catch (e) {
            print("⚠️ Erro no envio da foto ou recepção da resposta: $e");
          }

          // 8. CORREÇÃO: Se o Python não retornou respostas válidas, preenche com vazio
          if (respostasParaRevisar.isEmpty) {
            print(
              "⚠️ Python não retornou respostas ou houve erro. Preenchendo com 'Em branco' para revisão manual.",
            );
            respostasParaRevisar = List.filled(
              appState.avaliacaoSelecionada!.gabarito.length,
              "", // String vazia = Em branco, para revisão
            );
          }

          // 9. Cálculo da nota baseado nas respostas *reais* (vazias ou lidas)
          double notaExataComPesos = 0.0;
          final gabarito = appState.avaliacaoSelecionada!.gabarito;
          final pesos = appState.avaliacaoSelecionada!.pesos;

          for (int i = 0; i < respostasParaRevisar.length; i++) {
            if (i < gabarito.length && i < pesos.length) {
              bool respostaValida = respostasParaRevisar[i].isNotEmpty;
              bool acertou =
                  respostaValida &&
                  (respostasParaRevisar[i].trim().toUpperCase() ==
                      gabarito[i].trim().toUpperCase());
              if (acertou) {
                notaExataComPesos += pesos[i];
                print(
                  "📝 Q${i + 1}: '${respostasParaRevisar[i]}' == '${gabarito[i]}' (Peso: ${pesos[i]}) -> ACERTOU (+${pesos[i]})",
                );
              } else if (respostaValida) {
                print(
                  "📝 Q${i + 1}: '${respostasParaRevisar[i]}' != '${gabarito[i]}' (Peso: ${pesos[i]}) -> ERROU",
                );
              } else {
                print(
                  "📝 Q${i + 1}: 'Em branco' (Peso: ${pesos[i]}) -> NÃO CONSIDERADO",
                );
              }
            }
          }

          setState(() => processandoFoto = false);

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TelaConfirmacao(
                  fotoRecortada: fotoRecortada,
                  nomeAluno: alunoAlvo.nome,
                  respostasDetectadas: respostasParaRevisar,
                  onConfirmar: (notaConfirmada, respostasConfirmadas) {
                    setState(() {
                      alunoAlvo.status = "Corrigido";
                      alunoAlvo.notaFinal = (notaExataComPesos + 0.5).toInt();
                      alunoAlvo.notaExata = notaExataComPesos;
                      alunoAlvo.respostas = respostasConfirmadas;
                    });
                    _salvarCorrecaoInteligente(
                      alunoAlvo,
                      notaExataComPesos,
                      respostasConfirmadas,
                    );
                  },
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Todos os alunos pendentes já foram corrigidos!"),
                backgroundColor: Colors.indigo,
              ),
            );
          }
        }
      }
    } catch (e) {
      print("❌ Erro geral na câmera: $e");
      setState(() => processandoFoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro na câmera: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void marcarFaltaAluno(int index) {
    final appState = Provider.of<AppState>(context, listen: false);
    Aluno aluno = appState.alunos[index];

    setState(() {
      aluno.status = "Ausente";
      aluno.notaFinal = null;
      aluno.notaExata = null;
    });

    appState.atualizarStatusAluno(aluno.id, "Ausente");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🚫 ${aluno.nome} marcado como Ausente!"),
        backgroundColor: Colors.orange.shade800,
      ),
    );
  }

  void _mostrarDialogoAdicionarAluno(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final nomeController = TextEditingController();
    final numeroController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Adicionar Novo Aluno',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome Completo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numeroController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Número de Chamada',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nomeController.text.isEmpty ||
                    numeroController.text.isEmpty)
                  return;

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Salvando no Supabase...'),
                    backgroundColor: Colors.indigo,
                  ),
                );

                final sucesso = await appState.adicionarNovoAluno(
                  idTurma: appState.turmaSelecionada!.id,
                  nome: nomeController.text.trim(),
                  numeroChamada:
                      int.tryParse(numeroController.text.trim()) ?? 0,
                );

                if (mounted) {
                  if (sucesso) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Aluno adicionado com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '❌ Erro ao adicionar aluno. Verifique o terminal.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'SALVAR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final alunos = appState.alunos;
    final nomeTurma = appState.turmaSelecionada?.nome ?? "Turma";

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          nomeTurma,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, size: 28),
            tooltip: "Diagnóstico SAEB",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TelaResultadoTurma(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync, size: 26),
            tooltip: "Recarregar",
            onPressed: () async {
              if (appState.turmaSelecionada != null) {
                await appState.carregarAlunosDaTurma(
                  appState.turmaSelecionada!.id,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(" Lista atualizada!"),
                      backgroundColor: Colors.indigo,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.indigo.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, color: Colors.indigo, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${appState.disciplinaAtual} • ${appState.bimestreAtual}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Text(
                        "Gabarito: ${appState.avaliacaoSelecionada?.gabarito.length ?? 0} Questões",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // 🚨 BOTÃO NOVO DO DASHBOARD 🚨
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TelaDashboard(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.dashboard, size: 22),
                            label: const Text(
                              "📊 ABRIR DASHBOARD",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12), // Espacinho

                        ElevatedButton.icon(
                          onPressed: _selecionarAvaliacao,
                          icon: const Icon(Icons.cloud_download, size: 22),
                          label: const Text(
                            " CARREGAR GABARITO DA AVALIAÇÃO",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const TelaGabarito(),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.playlist_add_check,
                                  size: 22,
                                ),
                                label: const Text(
                                  "GABARITO MANUAL",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.indigo,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(
                                    color: Colors.indigo.shade300,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: processandoFoto
                                    ? null
                                    : () => _abrirCameraCorrecao(),
                                icon: const Icon(Icons.camera_alt, size: 24),
                                label: const Text(
                                  "LER PROVAS EM FILA",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        appState.carregandoDados
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.indigo,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      "📡 Buscando alunos no Supabase...",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : alunos.isEmpty
                            ? const Center(
                                child: Text(
                                  "Nenhum aluno ATIVO encontrado nesta turma.",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: alunos.length,
                                itemBuilder: (context, index) {
                                  final aluno = alunos[index];
                                  final bool corrigido = aluno.foiCorrigido;
                                  final bool ausente = aluno.estaAusente;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    elevation: 1,
                                    color: ausente
                                        ? Colors.grey.shade100
                                        : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: corrigido
                                            ? Colors.green.shade300
                                            : (ausente
                                                  ? Colors.orange.shade300
                                                  : Colors.grey.shade300),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: ListTile(
                                      isThreeLine: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                      leading: CircleAvatar(
                                        backgroundColor: corrigido
                                            ? Colors.green.shade100
                                            : (ausente
                                                  ? Colors.orange.shade100
                                                  : Colors.grey.shade200),
                                        child: Icon(
                                          corrigido
                                              ? Icons.check
                                              : (ausente
                                                    ? Icons.person_off
                                                    : Icons.person_outline),
                                          color: corrigido
                                              ? Colors.green.shade800
                                              : (ausente
                                                    ? Colors.orange.shade800
                                                    : Colors.grey.shade700),
                                        ),
                                      ),
                                      title: Text(
                                        "${aluno.numeroChamada ?? (index + 1)}. ${aluno.nome}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          decoration: ausente
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          color: corrigido
                                              ? Colors.black87
                                              : (ausente
                                                    ? Colors.grey.shade500
                                                    : Colors.grey.shade800),
                                        ),
                                      ),
                                      subtitle: Text(
                                        corrigido
                                            ? "Toque para ver o Perfil SAEB"
                                            : (ausente
                                                  ? "Aluno ausente"
                                                  : "Pendente • Escolha uma ação 👉"),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: corrigido
                                              ? Colors.indigo.shade700
                                              : (ausente
                                                    ? Colors.orange.shade800
                                                    : Colors.grey.shade600),
                                        ),
                                      ),

                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.refresh,
                                              color: Colors.blue,
                                              size: 28,
                                            ),
                                            tooltip: "Re-corrigir",
                                            onPressed: () {
                                              setState(() {
                                                aluno.status = "Pendente";
                                                aluno.notaFinal = null;
                                                aluno.notaExata = null;
                                              });
                                              _abrirCameraCorrecao(
                                                indexEspecifico: index,
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),

                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                "Ex: ${aluno.notaExata?.toStringAsFixed(2) ?? '-'}",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.green,
                                                  ),
                                                ),
                                                child: Text(
                                                  "${aluno.notaFinal}",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color:
                                                        Colors.green.shade800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),

                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              TelaAnalise(aluno: aluno),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (processandoFoto)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: Card(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.indigo),
                        SizedBox(height: 16),
                        Text(
                          "🤖 Python analisando bolinhas...",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarDialogoAdicionarAluno(context),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text(
          'ADICIONAR ALUNO',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
