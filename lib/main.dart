import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'angola_regions.dart';
import 'camera_capture_screen.dart';
import 'crops.dart';
import 'history_item.dart';
import 'history_repository.dart';
import 'inference_service.dart';
import 'sync_service.dart';

void main() {
  runApp(const AgroiaApp());
}

class AgroiaApp extends StatelessWidget {
  const AgroiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    final colorScheme = ColorScheme.fromSeed(seedColor: seed);

    return MaterialApp(
      title: 'Agrolweza',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8F3),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w800, height: 1.2),
          headlineMedium: TextStyle(fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 16, height: 1.4),
          bodyMedium: TextStyle(fontSize: 15, height: 1.4),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            side: BorderSide(color: colorScheme.primary, width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          indicatorColor: colorScheme.primaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// URL base do backend de sincronizacao. Configuravel no build sem tocar no
/// codigo: `flutter run --dart-define=SYNC_BASE_URL=http://192.168.1.10:8080`.
/// O default aponta para o host da maquina visto de dentro do emulador Android
/// (10.0.2.2), onde corre o servidor de teste durante a fase 2.
const _syncBaseUrl = String.fromEnvironment(
  'SYNC_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

enum AppScreen { home, result, history }

/// Ícone de cada cultura no seletor. Fica na UI e não em [cropCatalog] para
/// manter o registo de culturas em Dart puro, testável sem plataforma.
IconData _cropIcon(String cropId) => switch (cropId) {
      'feijao' => Icons.spa_rounded,
      'mandioca' => Icons.grass,
      _ => Icons.eco_rounded,
    };

/// Cor e ícone associados ao tom do diagnóstico (ok | warn | neutral).
///
/// Não existe tom "está tudo bem". O melhor caso que o modelo consegue
/// produzir é "não encontrei as doenças que conheço", que não é o mesmo que a
/// planta estar sã — ver a nota no `healthy` do [diagnosisCatalog]. Como o
/// agricultor lê primeiro o ícone e a cor, e só depois o texto, esse melhor
/// caso usa um visto VAZADO: continua a não alarmar, mas não é o selo
/// preenchido que se dá a uma planta certificada como saudável.
class ToneVisual {
  final Color color;
  final IconData icon;

  const ToneVisual(this.color, this.icon);

  static ToneVisual of(String tone) => switch (tone) {
        'ok' => const ToneVisual(Color(0xFF2E7D32), Icons.check_circle_outline),
        'warn' => const ToneVisual(Color(0xFFE59500), Icons.warning_rounded),
        _ => const ToneVisual(Color(0xFF6B6B6B), Icons.help_rounded),
      };
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _repository = HistoryRepository();
  final _picker = ImagePicker();
  final _inference = InferenceService();
  final SyncTransport _syncTransport = HttpSyncTransport(
    endpoint: Uri.parse('$_syncBaseUrl/v1/diagnosticos'),
  );

  AppScreen _screen = AppScreen.home;
  String _crop = '';
  String _province = '';
  String _municipality = '';
  String _imageName = '';
  File? _imageFile;

  /// Moldura usada na captura, quando a foto veio da câmara-guia. Fica null
  /// para fotos escolhidas da galeria, que não têm enquadramento conhecido.
  CaptureFraming? _framing;
  HistoryItem? _result;
  List<HistoryItem> _history = [];
  String _syncMessage = '';
  bool _analyzing = false;
  String? _analyzeError;

  bool _online = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _netTimer;

  bool _syncing = false;

  /// Tudo o que ainda nao foi aceite pelo destino, incluindo o que falhou.
  /// Um item em erro continua por enviar, logo continua a contar.
  int get _pending => _history.where((item) => !item.isSynced).length;

  @override
  void initState() {
    super.initState();
    _repository.load().then((items) {
      if (mounted) setState(() => _history = items);
    });
    _startNetworkMonitoring();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _netTimer?.cancel();
    _inference.dispose();
    super.dispose();
  }

  void _startNetworkMonitoring() {
    _refreshOnline();
    // Reage na hora quando Wi-Fi/dados ligam ou caem.
    _connSub =
        Connectivity().onConnectivityChanged.listen((_) => _refreshOnline());
    // Backstop: revalida periodicamente para apanhar internet que cai sem
    // mudar a interface (ex: portal cativo, sinal fraco, Wi-Fi sem saida).
    _netTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refreshOnline());
  }

  Future<void> _refreshOnline() async {
    // Sem interface de rede nao ha o que testar. Evita gastar dados moveis
    // (caros em Angola) com um handshake TLS que so pode falhar.
    final conn = await Connectivity().checkConnectivity();
    final hasInterface = conn.any((c) => c != ConnectivityResult.none);
    final online = hasInterface && await _hasRealInternet();
    if (mounted && online != _online) setState(() => _online = online);
  }

  // Certeza real de internet: bate no endpoint generate_204 (mesma tecnica que
  // o Android usa para detetar portais cativos). 204 = internet chega mesmo,
  // nao so "tem interface de rede ligada".
  Future<bool> _hasRealInternet() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse('https://www.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      return res.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source);
    if (file != null) {
      setState(() {
        _imageName = file.name;
        _imageFile = File(file.path);
        _framing = null;
        _analyzeError = null;
      });
    }
  }

  // Abre a camera propria com moldura-guia em vez da camera nativa, para
  // empurrar o utilizador para o enquadramento aproximado de uma folha.
  Future<void> _captureWithGuide() async {
    final shot = await Navigator.of(context).push<GuidedShot?>(
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (shot != null && mounted) {
      setState(() {
        _imageName = shot.file.name;
        _imageFile = File(shot.file.path);
        _framing = shot.framing;
        _analyzeError = null;
      });
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Como quer adicionar a fotografia?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.photo_camera)),
                title: const Text('Tirar fotografia'),
                subtitle: const Text('Com moldura para enquadrar a folha'),
                onTap: () {
                  Navigator.pop(context);
                  _captureWithGuide();
                },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.photo_library)),
                title: const Text('Escolher da galeria'),
                subtitle: const Text('Veja como escolher uma boa foto'),
                onTap: () {
                  Navigator.pop(context);
                  _showGalleryGuide();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // A galeria nativa nao aceita moldura por cima, entao ensinamos ANTES de
  // abrir: exemplo "assim sim / assim nao" apoiado em icones grandes e cor
  // (verde/vermelho), para funcionar com quem le pouco.
  void _showGalleryGuide() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha uma boa fotografia',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'Uma folha de perto dá um resultado mais fiável do que a planta inteira.',
                style: TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(
                    child: _GalleryExample(
                      good: true,
                      icon: Icons.eco,
                      caption: 'Uma folha, de perto',
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: _GalleryExample(
                      good: false,
                      icon: Icons.forest,
                      caption: 'Planta inteira, de longe',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Escolher foto'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _analyze() async {
    final imageFile = _imageFile;
    if (imageFile == null) return;

    setState(() {
      _analyzing = true;
      _analyzeError = null;
    });

    try {
      final crop = cropCatalog[_crop];
      if (crop == null) {
        throw StateError('Cultura desconhecida: "$_crop".');
      }
      final result = await _inference.classify(
        imageFile,
        crop: crop,
        framing: _framing,
      );
      // Confiança abaixo do limite seguro: recusa o diagnóstico específico
      // em vez de arriscar mostrar uma classe errada. O limiar é da cultura,
      // não global: depende da calibração de cada modelo.
      final diagnosisId = result.confidence >= crop.abstentionThreshold
          ? result.classId
          : 'unknown';

      if (!mounted) return;
      setState(() {
        _result = HistoryItem(
          id: HistoryItem.newId(),
          diagnosisId: diagnosisId,
          confidence: result.confidence,
          crop: _crop,
          province: _province,
          municipality: _municipality,
          createdAt: DateTime.now(),
          syncStatus: SyncStatus.pending,
        );
        _analyzing = false;
        _screen = AppScreen.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeError = 'Não foi possível analisar esta fotografia. Tente novamente.';
      });
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null) return;
    // Guardar duas vezes o mesmo diagnostico criaria dois registos com o mesmo
    // id, quebrando a idempotencia da fila.
    if (_history.any((item) => item.id == result.id)) {
      setState(() => _screen = AppScreen.history);
      return;
    }
    final next = [result, ..._history];
    setState(() {
      _history = next;
      _screen = AppScreen.history;
      _syncMessage = 'Diagnóstico guardado no dispositivo.';
    });
    await _repository.save(next);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    if (!_online) {
      setState(() => _syncMessage =
          'Sem ligação à Internet. Os diagnósticos continuam guardados no telemóvel.');
      return;
    }

    // Idempotencia: entram na fila apenas os que o destino ainda nao aceitou.
    // Repetir a sincronizacao depois de uma falha nao reenvia os ja aceites,
    // logo nao duplica nada.
    final queue = _history.where((item) => !item.isSynced).toList();
    if (queue.isEmpty) {
      setState(() => _syncMessage = 'Não há diagnósticos por enviar.');
      return;
    }

    setState(() {
      _syncing = true;
      _syncMessage = '';
    });

    final next = [..._history];
    var sent = 0;
    var failed = 0;
    for (final item in queue) {
      final outcome = await _syncTransport.send(item);
      final index = next.indexWhere((e) => e.id == item.id);
      if (index == -1) continue;
      if (outcome == SyncOutcome.success) {
        next[index] = item.copyWith(syncStatus: SyncStatus.synced);
        sent++;
      } else {
        next[index] = item.copyWith(syncStatus: SyncStatus.error);
        failed++;
      }
    }

    await _repository.save(next);
    if (!mounted) return;
    setState(() {
      _history = next;
      _syncing = false;
      _syncMessage = failed == 0
          ? 'Enviados $sent diagnósticos.'
          : 'Enviados $sent. Faltam $failed, pode tentar novamente.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final showNav = _screen != AppScreen.result;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.eco, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Agrolweza'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_online
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF6B6B6B))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      size: 14,
                      color: _online
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF6B6B6B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _online ? 'Online' : 'Sem ligação',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _online
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF6B6B6B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: showNav
          ? NavigationBar(
              selectedIndex: _screen == AppScreen.history ? 1 : 0,
              onDestinationSelected: (index) => setState(
                () => _screen = index == 1 ? AppScreen.history : AppScreen.home,
              ),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.camera_alt_outlined),
                  selectedIcon: Icon(Icons.camera_alt),
                  label: 'Diagnóstico',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.history_outlined),
                  selectedIcon: const Icon(Icons.history),
                  label: _pending > 0 ? 'Histórico ($_pending)' : 'Histórico',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_screen) {
      case AppScreen.home:
        return _buildHome();
      case AppScreen.result:
        return _buildResult();
      case AppScreen.history:
        return _buildHistory();
    }
  }

  Widget _buildHome() {
    final canAnalyze = _crop.isNotEmpty &&
        _province.isNotEmpty &&
        _municipality.isNotEmpty &&
        _imageName.isNotEmpty;
    final municipios = municipalitiesOf(_province);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          'O que está a acontecer\ncom a sua planta?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Fotografe uma folha e receba uma orientação inicial. '
          'O resultado é apoio à decisão e não substitui um técnico agrícola.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 28),
        _StepLabel(number: 1, text: 'Escolha a cultura'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _crop.isEmpty ? null : _crop,
          hint: const Text('Selecionar cultura'),
          icon: const Icon(Icons.expand_more_rounded),
          items: [
            for (final crop in cropCatalog.values)
              DropdownMenuItem(
                value: crop.id,
                child: Row(
                  children: [
                    Icon(_cropIcon(crop.id), size: 20),
                    const SizedBox(width: 10),
                    Text(crop.label),
                  ],
                ),
              ),
          ],
          onChanged: (value) => setState(() => _crop = value ?? ''),
        ),
        const SizedBox(height: 28),
        _StepLabel(number: 2, text: 'Onde está a planta'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _province.isEmpty ? null : _province,
          hint: const Text('Selecionar província'),
          icon: const Icon(Icons.expand_more_rounded),
          isExpanded: true,
          items: [
            for (final p in angolaProvinces)
              DropdownMenuItem(
                value: p,
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(p),
                  ],
                ),
              ),
          ],
          // Trocar de província invalida o município já escolhido.
          onChanged: (value) => setState(() {
            _province = value ?? '';
            _municipality = '';
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _municipality.isEmpty ? null : _municipality,
          hint: Text(_province.isEmpty
              ? 'Escolha a província primeiro'
              : 'Selecionar município'),
          icon: const Icon(Icons.expand_more_rounded),
          isExpanded: true,
          items: [
            for (final m in municipios)
              DropdownMenuItem(
                value: m,
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(m),
                  ],
                ),
              ),
          ],
          // Sem província escolhida não há municípios para listar.
          onChanged: municipios.isEmpty
              ? null
              : (value) => setState(() => _municipality = value ?? ''),
        ),
        const SizedBox(height: 28),
        _StepLabel(number: 3, text: 'Fotografe a planta'),
        const SizedBox(height: 10),
        InkWell(
          onTap: _showImageSourceSheet,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.4),
                width: 1.4,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _imageName.isEmpty ? Icons.add_a_photo_outlined : Icons.check_circle,
                  size: 34,
                  color: scheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  _imageName.isEmpty ? 'Toque para escolher fotografia' : _imageName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Funciona com ou sem Internet',
                  style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: canAnalyze && !_analyzing ? _analyze : null,
          icon: _analyzing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.search_rounded),
          label: Text(_analyzing ? 'A analisar...' : 'Analisar fotografia'),
        ),
        if (_analyzeError != null) ...[
          const SizedBox(height: 12),
          Text(
            _analyzeError!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$_pending', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('pendentes de sincronização'),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Text('Como funciona', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Fotografar → analisar no dispositivo → guardar → sincronizar quando houver rede.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    final fixture = result.info;
    // Estado unico e coerente: badge, cor, icone, titulo e orientacao derivam
    // JUNTOS da confianca + classe, para nao mandar sinais opostos (ex: check
    // verde da classe vs badge "possivel problema" vindo da confianca).
    final String statusLabel;
    final Color color;
    final IconData icon;
    final String title;
    final String guidance;
    // Limiar da cultura do PRÓPRIO registo, não do que está selecionado agora:
    // o histórico mostra resultados antigos e cada um foi julgado pelo limiar
    // da sua cultura.
    final abstentionThreshold =
        cropCatalog[result.crop]?.abstentionThreshold ?? 0.6;
    if (result.confidence < abstentionThreshold) {
      statusLabel = 'RECUSA SEGURA';
      color = const Color(0xFF6B6B6B);
      icon = Icons.help_rounded;
      title = 'Não foi possível confirmar';
      guidance =
          'Não deu para concluir. Tire outra foto só da folha, com boa luz e fundo simples.';
    } else if (result.confidence < 0.85) {
      statusLabel = 'POUCO CONCLUSIVO';
      color = const Color(0xFFE59500);
      icon = Icons.warning_rounded;
      title = 'Resultado pouco conclusivo';
      guidance =
          'O resultado não é conclusivo. Tire outra foto mais nítida, só da folha, para confirmar.';
    } else {
      final visual = ToneVisual.of(fixture.tone);
      // "SEM SINAIS" e não "SAUDÁVEL": o crachá é a primeira coisa que o
      // agricultor lê, e o modelo não tem como afirmar que a planta está sã.
      statusLabel = switch (fixture.tone) {
        'ok' => 'SEM SINAIS',
        'warn' => 'POSSÍVEL DOENÇA',
        _ => 'NÃO CONFIRMADO',
      };
      color = visual.color;
      icon = visual.icon;
      title = fixture.label;
      guidance = fixture.recommendation;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _screen = AppScreen.home),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Nova análise'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 40),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Chip(
            label: Text(statusLabel),
            backgroundColor: color.withValues(alpha: 0.15),
            labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
            side: BorderSide.none,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Confiança estimada', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${(result.confidence * 100).round()}%',
                      style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: result.confidence,
                    minHeight: 10,
                    backgroundColor: color.withValues(alpha: 0.1),
                    color: color,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _InfoTile(label: 'Gravidade', value: fixture.severity),
                    ),
                    Expanded(
                      child: _InfoTile(
                        label: 'Cultura',
                        value: cropLabelFor(result.crop),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('O que observar', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ...fixture.observations.map(
                  (o) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle, size: 6, color: Colors.black38),
                        const SizedBox(width: 10),
                        Expanded(child: Text(o)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'ORIENTAÇÃO INICIAL',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(guidance, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar no histórico'),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Meu histórico', style: Theme.of(context).textTheme.headlineSmall),
            if (_pending > 0)
              OutlinedButton.icon(
                // Sem internet real nao ha envio possivel. O botao fica visivel
                // para o utilizador perceber que ha pendencias, mas inativo.
                onPressed: (_online && !_syncing) ? _sync : null,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(_syncing ? 'A enviar...' : 'Sincronizar $_pending'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        if (_syncMessage.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_syncMessage, style: const TextStyle(color: Colors.black87))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.eco_outlined, size: 48, color: Colors.black.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                const Text('Ainda não há diagnósticos.', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                  'Os seus registos aparecerão aqui mesmo sem Internet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          )
        else
          ..._history.map((item) {
            final visual = ToneVisual.of(item.info.tone);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 22),
                  ),
                  title: Text(item.info.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${item.createdAt.toLocal()} · ${switch (item.syncStatus) {
                      SyncStatus.synced => 'Sincronizado',
                      SyncStatus.error => 'Falha no envio, vai tentar de novo',
                      _ => 'Neste dispositivo',
                    }}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '${(item.confidence * 100).round()}%',
                    style: TextStyle(fontWeight: FontWeight.w800, color: visual.color),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Colors.black.withValues(alpha: 0.4)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Diagnóstico feito no dispositivo por um modelo de IA em fase '
                  'inicial (treinado com dados africanos, ainda não angolanos). '
                  'É apoio à decisão, não substitui um técnico agrícola.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepLabel extends StatelessWidget {
  final int number;
  final String text;

  const _StepLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          child: Text(
            '$number',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// Cartao de exemplo "assim sim / assim nao" do guia da galeria. Comunica por
/// icone + cor + selo (check verde / cruz vermelha) para leitores com pouca
/// alfabetizacao, com a legenda so a reforcar.
class _GalleryExample extends StatelessWidget {
  final bool good;
  final IconData icon;
  final String caption;

  const _GalleryExample({
    required this.good,
    required this.icon,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final color = good ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color, width: 2),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, size: 52, color: color)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(
                      good ? Icons.check : Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }
}
