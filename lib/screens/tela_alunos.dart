import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../context/app_state.dart';
import '../models/aluno_model.dart';
import '../models/avaliacao_model.dart';
import 'tela_gabarito.dart';
import 'tela_confirmacao.dart';
import 'tela_resultado_turma.dart';
import 'tela_dashboard.dart';
import 'tela_perfil_aluno.dart';
import 'tela_cadastro_avaliacao.dart';
import 'tela_lancamento_notas.dart';
import 'tela_fechamento_bimestre.dart';
import 'tela_analise_pedagogica.dart';
import 'tela_cadastro_avaliacao_aberta.dart';
import 'tela_correcao_aberta.dart';
import 'tela_teste_ias.dart';

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

  // 🔲 Lê TODOS os QRs das folhas e junta: prova (OMRPROVA/OMRALUNO) + aluno (OMRALUNO/OMRCARD)
  Future<Map<String, int?>> _lerQRDasFolhas(List<String> caminhos) async {
    int? prova;
    int? aluno;
    try {
      final scanner = BarcodeScanner();
      for (final caminho in caminhos) {
        final input = InputImage.fromFilePath(caminho);
        final barcodes = await scanner.processImage(input);
        for (final b in barcodes) {
          final raw = (b.rawValue ?? '').trim();
          if (raw.startsWith('OMRPROVA:')) {
            prova ??= int.tryParse(raw.substring('OMRPROVA:'.length));
          } else if (raw.startsWith('OMRALUNO:')) {
            final partes = raw.split(':');
            if (partes.length >= 3) {
              prova ??= int.tryParse(partes[1]);
              aluno ??= int.tryParse(partes[2]);
            }
          } else if (raw.startsWith('OMRCARD:')) {
            aluno ??= int.tryParse(raw.substring('OMRCARD:'.length));
          } else if (raw.startsWith('OMRAV')) {
            // Formato antigo do backend (retrocompatibilidade)
            prova ??= int.tryParse(raw.substring('OMRAV'.length));
          }
        }
      }
      await scanner.close();
    } catch (e) {
      // QR é opcional: se não achar ou falhar, segue o fluxo normal
    }
    return {'prova': prova, 'aluno': aluno};
  }

  double _pesoEscola(String nivel) {
    final n = nivel.toLowerCase();
    if (n.contains('inter')) return 1.25;
    if (n.contains('avanç')) return 0.67;
    return 1.0;
  }

  bool _ehSaeb() {
    final appState = Provider.of<AppState>(context, listen: false);
    final nome = (appState.avaliacaoSelecionada?.nome ?? '').toLowerCase();
    return nome.contains('saeb');
  }

  String _nivelEscola(double nota) {
    if (nota >= 8.67) return 'Avançado';
    if (nota >= 6.51) return 'Adequado';
    if (nota >= 5) return 'Básico';
    return 'Abaixo do Básico';
  }

  String _nivelNormal(double nota) {
    if (nota >= 8) return 'Avançado';
    if (nota >= 6) return 'Adequado';
    if (nota >= 4) return 'Básico';
    return 'Abaixo do Básico';
  }

  Future<void> _recarregarLista() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.turmaSelecionada != null) {
      await appState.carregarAlunosDaTurma(appState.turmaSelecionada!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🔄 Lista atualizada!"),
            backgroundColor: Colors.indigo,
          ),
        );
      }
    }
  }

  Future<void> _confirmarExclusao(Avaliacao aval) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Excluir avaliação'),
        content: Text(
          'Excluir "${aval.nome}"?\n\nTodas as notas e respostas lançadas nela serão apagadas e ela sai da média do bimestre. Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('EXCLUIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('respostas').delete().eq('id_avaliacao', aval.id);
      await supabase.from('resultados').delete().eq('id_avaliacao', aval.id);
      await supabase.from('questoes').delete().eq('id_avaliacao', aval.id);
      await supabase
          .from('questoes_abertas')
          .delete()
          .eq('id_avaliacao', aval.id);
      await supabase.from('avaliacoes').delete().eq('id', aval.id);

      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.avaliacaoSelecionada?.id == aval.id) {
        appState.setAvaliacaoSelecionada(null);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ "${aval.nome}" excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        if (i >= avaliacao.gabarito.length) break;
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
      String nivelSaeb = _ehSaeb()
          ? _nivelEscola(notaExata)
          : _nivelNormal(notaExata);
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
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: "Excluir avaliação",
                onPressed: () => _confirmarExclusao(aval),
              ),
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

        // 🔲 Procura QR Code na folha (prova e/ou aluno)
        final qr = await _lerQRDasFolhas([fotoRecortada.path]);
        final idProvaQR = qr['prova'];
        final idAlunoQR = qr['aluno'];

        // Se achou QR da prova diferente da atual, recarrega o gabarito
        if (idProvaQR != null &&
            idProvaQR != appState.avaliacaoSelecionada?.id) {
          try {
            final rAv = await Supabase.instance.client
                .from('avaliacoes')
                .select('nome')
                .eq('id', idProvaQR)
                .maybeSingle();
            final nomeAv = rAv == null ? 'ID $idProvaQR' : '${rAv['nome']}';
            await appState.carregarGabarito(idProvaQR);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🔲 Prova reconhecida pelo QR: $nomeAv'),
                  backgroundColor: Colors.blue,
                ),
              );
            }
          } catch (e) {
            print('⚠️ Erro ao carregar prova do QR: $e');
          }
        }

        // Aluno: QR primeiro; senão, o próximo pendente da fila
        int indexAlvo = indexEspecifico ?? -1;
        if (indexAlvo == -1 && idAlunoQR != null) {
          indexAlvo = appState.alunos.indexWhere((a) => a.id == idAlunoQR);
          if (indexAlvo != -1 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '🔲 Aluno reconhecido pelo QR: ${appState.alunos[indexAlvo].nome}',
                ),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
        if (indexAlvo == -1) {
          indexAlvo = appState.alunos.indexWhere((a) => a.estaPendente);
        }

        if (indexAlvo != -1 && mounted) {
          Aluno alunoAlvo = appState.alunos[indexAlvo];
          setState(() => processandoFoto = true);
          List<String> respostasParaRevisar = [];

          try {
            String urlServidor = appState.ipServidor;
            print("🔍 Testando conectividade com: $urlServidor");
            final responseConexao = await http
                .get(Uri.parse(urlServidor))
                .timeout(const Duration(seconds: 15));
            print("✅ Conectividade OK. Status: ${responseConexao.statusCode}");

            var request = http.MultipartRequest(
              'POST',
              Uri.parse("$urlServidor/corrigir"),
            );

            request.files.add(
              await http.MultipartFile.fromPath('image', fotoRecortada.path),
            );

            request.fields['gabarito'] = jsonEncode(
              appState.avaliacaoSelecionada!.gabarito,
            );
            request.fields['id_aluno'] = alunoAlvo.id.toString();
            request.fields['id_avaliacao'] = appState.avaliacaoSelecionada!.id
                .toString();

            var response = await request.send().timeout(
              const Duration(seconds: 90),
            );

            if (response.statusCode == 200) {
              var respStr = await response.stream.bytesToString();
              var jsonResp = jsonDecode(respStr);

              if (jsonResp['sucesso'] == true &&
                  jsonResp['resultado'] != null) {
                print("✅ Correção recebida do servidor com sucesso!");

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
              String errorBody = await response.stream.bytesToString();
              print("❌ Erro HTTP ${response.statusCode}: $errorBody");
            }
          } catch (e) {
            print("⚠️ Erro no envio da foto ou recepção da resposta: $e");
          }

          if (respostasParaRevisar.isEmpty) {
            print(
              "⚠️ Python não retornou respostas ou houve erro. Preenchendo com 'Em branco' para revisão manual.",
            );
            respostasParaRevisar = List.filled(
              appState.avaliacaoSelecionada!.gabarito.length,
              "",
            );
          }

          double notaExataComPesos = 0.0;
          final gabarito = appState.avaliacaoSelecionada!.gabarito;
          final niveis = appState.avaliacaoSelecionada!.niveis;
          final bool ehSaeb = _ehSaeb();
          final double pesoNormal = gabarito.isNotEmpty
              ? 10 / gabarito.length
              : 1;

          for (int i = 0; i < respostasParaRevisar.length; i++) {
            if (i < gabarito.length && i < niveis.length) {
              double peso = ehSaeb ? _pesoEscola(niveis[i]) : pesoNormal;

              bool respostaValida = respostasParaRevisar[i].isNotEmpty;
              bool acertou =
                  respostaValida &&
                  (respostasParaRevisar[i].trim().toUpperCase() ==
                      gabarito[i].trim().toUpperCase());
              if (acertou) {
                notaExataComPesos += peso;
                print(
                  "📝 Q${i + 1}: '${respostasParaRevisar[i]}' == '${gabarito[i]}' (Peso: $peso) -> ACERTOU (+$peso)",
                );
              } else if (respostaValida) {
                print(
                  "📝 Q${i + 1}: '${respostasParaRevisar[i]}' != '${gabarito[i]}' (Peso: $peso) -> ERROU",
                );
              } else {
                print(
                  "📝 Q${i + 1}: 'Em branco' (Peso: $peso) -> NÃO CONSIDERADO",
                );
              }
            }
          }

          if (notaExataComPesos > 10) notaExataComPesos = 10;

          setState(() => processandoFoto = false);

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TelaConfirmacao(
                  fotoRecortada: fotoRecortada,
                  nomeAluno: alunoAlvo.nome,
                  respostasDetectadas: respostasParaRevisar,
                  onConfirmar: (_, respostasConfirmadas) {
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

  // 🔲 Modo QR: escaneia, carrega o gabarito da prova do QR e identifica o aluno — tudo sozinho!
  Future<void> _abrirCameraPorQR() async {
    final appState = Provider.of<AppState>(context, listen: false);

    try {
      DocumentScannerOptions options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: false,
      );
      final documentScanner = DocumentScanner(options: options);
      DocumentScanningResult result = await documentScanner.scanDocument();

      if (result.images == null || result.images!.isEmpty) return;
      File fotoRecortada = File(result.images!.first);

      final qr = await _lerQRDasFolhas([fotoRecortada.path]);
      final idProvaQR = qr['prova'];
      final idAlunoQR = qr['aluno'];

      // Prova: QR primeiro; senão, a já selecionada; senão, erro
      int? idProva = idProvaQR ?? appState.avaliacaoSelecionada?.id;
      if (idProva == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Nem gabarito carregado, nem QR de prova na foto!',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Carrega o gabarito da prova do QR (se ainda não é a atual)
      if (appState.avaliacaoSelecionada?.id != idProva ||
          appState.avaliacaoSelecionada!.gabarito.isEmpty) {
        try {
          final rAv = await Supabase.instance.client
              .from('avaliacoes')
              .select('nome')
              .eq('id', idProva)
              .maybeSingle();
          final nomeAv = rAv == null ? 'ID $idProva' : '${rAv['nome']}';
          await appState.carregarGabarito(idProva);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🔲 Gabarito carregado pelo QR: $nomeAv'),
                backgroundColor: Colors.blue,
              ),
            );
          }
        } catch (e) {
          print('⚠️ Erro ao carregar gabarito do QR: $e');
        }
      }

      if (appState.avaliacaoSelecionada == null ||
          appState.avaliacaoSelecionada!.gabarito.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Não consegui carregar o gabarito desta prova!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Aluno: no modo QR, precisa do QR
      if (idAlunoQR == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ QR do aluno não encontrado! Cole o QR na prova ou use o cartão laminado.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      int indexAlvo = appState.alunos.indexWhere((a) => a.id == idAlunoQR);
      if (indexAlvo == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ O aluno do QR não está na turma selecionada!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔲 Aluno reconhecido: ${appState.alunos[indexAlvo].nome}',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }

      Aluno alunoAlvo = appState.alunos[indexAlvo];
      setState(() => processandoFoto = true);
      List<String> respostasParaRevisar = [];

      try {
        String urlServidor = appState.ipServidor;
        await http
            .get(Uri.parse(urlServidor))
            .timeout(const Duration(seconds: 15));

        var request = http.MultipartRequest(
          'POST',
          Uri.parse("$urlServidor/corrigir"),
        );

        request.files.add(
          await http.MultipartFile.fromPath('image', fotoRecortada.path),
        );

        request.fields['gabarito'] = jsonEncode(
          appState.avaliacaoSelecionada!.gabarito,
        );
        request.fields['id_aluno'] = alunoAlvo.id.toString();
        request.fields['id_avaliacao'] = appState.avaliacaoSelecionada!.id
            .toString();

        var response = await request.send().timeout(
          const Duration(seconds: 90),
        );

        if (response.statusCode == 200) {
          var respStr = await response.stream.bytesToString();
          var jsonResp = jsonDecode(respStr);

          if (jsonResp['sucesso'] == true && jsonResp['resultado'] != null) {
            if (jsonResp['resultado']['respostas'] != null) {
              respostasParaRevisar = List<String>.from(
                jsonResp['resultado']['respostas'],
              );
            }
          } else {
            if (jsonResp['resultado']?['respostas'] != null) {
              respostasParaRevisar = List<String>.from(
                jsonResp['resultado']['respostas'],
              );
            }
          }
        }
      } catch (e) {
        print("⚠️ Erro no envio: $e");
      }

      if (respostasParaRevisar.isEmpty) {
        respostasParaRevisar = List.filled(
          appState.avaliacaoSelecionada!.gabarito.length,
          "",
        );
      }

      double notaExataComPesos = 0.0;
      final gabarito = appState.avaliacaoSelecionada!.gabarito;
      final niveis = appState.avaliacaoSelecionada!.niveis;
      final bool ehSaeb = _ehSaeb();
      final double pesoNormal = gabarito.isNotEmpty ? 10 / gabarito.length : 1;

      for (int i = 0; i < respostasParaRevisar.length; i++) {
        if (i < gabarito.length && i < niveis.length) {
          double peso = ehSaeb ? _pesoEscola(niveis[i]) : pesoNormal;
          bool respostaValida = respostasParaRevisar[i].isNotEmpty;
          bool acertou =
              respostaValida &&
              (respostasParaRevisar[i].trim().toUpperCase() ==
                  gabarito[i].trim().toUpperCase());
          if (acertou) {
            notaExataComPesos += peso;
          }
        }
      }

      if (notaExataComPesos > 10) notaExataComPesos = 10;

      setState(() => processandoFoto = false);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TelaConfirmacao(
              fotoRecortada: fotoRecortada,
              nomeAluno: alunoAlvo.nome,
              respostasDetectadas: respostasParaRevisar,
              onConfirmar: (_, respostasConfirmadas) {
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
    } catch (e) {
      print("❌ Erro geral no QR: $e");
      setState(() => processandoFoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro no QR: $e"),
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
            icon: const Icon(Icons.summarize, size: 28),
            tooltip: "Fechamento do Bimestre",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TelaFechamentoBimestre(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note, size: 28),
            tooltip: "Lançar Notas Manuais",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TelaLancamentoNotas(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'cadastro') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TelaCadastroAvaliacao(),
                  ),
                );
              } else if (value == 'saeb') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TelaResultadoTurma(),
                  ),
                );
              } else if (value == 'analise') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TelaAnalisePedagogica(),
                  ),
                );
              } else if (value == 'aberta') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TelaCadastroAvaliacaoAberta(),
                  ),
                );
              } else if (value == 'corrigiraberta') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TelaCorrecaoAberta(),
                  ),
                );
              } else if (value == 'lab') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TelaTesteIAs()),
                );
              } else if (value == 'sync') {
                _recarregarLista();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'cadastro',
                child: Text('➕ Cadastrar Avaliação'),
              ),
              const PopupMenuItem(
                value: 'aberta',
                child: Text('📝 Cadastrar Prova Aberta'),
              ),
              const PopupMenuItem(
                value: 'corrigiraberta',
                child: Text('🤖 Corrigir Prova Aberta'),
              ),
              const PopupMenuItem(
                value: 'saeb',
                child: Text('📊 Diagnóstico SAEB'),
              ),
              const PopupMenuItem(
                value: 'analise',
                child: Text('🔎 Análise Pedagógica'),
              ),
              const PopupMenuItem(
                value: 'lab',
                child: Text('🧪 Laboratório de IAs'),
              ),
              const PopupMenuItem(value: 'sync', child: Text('🔄 Recarregar')),
            ],
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
                        const SizedBox(height: 12),

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
                                  size: 18,
                                ),
                                label: const Text(
                                  "GABARITO MANUAL",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: processandoFoto
                                    ? null
                                    : _abrirCameraPorQR,
                                icon: const Icon(
                                  Icons.qr_code_scanner,
                                  size: 18,
                                ),
                                label: const Text(
                                  "QR ALUNO",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: processandoFoto
                                    ? null
                                    : () => _abrirCameraCorrecao(),
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: const Text(
                                  "FILA",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  elevation: 2,
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
                                              TelaPerfilAluno(aluno: aluno),
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
