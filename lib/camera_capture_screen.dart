import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'inference_service.dart' show CaptureFraming;

/// Fotografia tirada com a moldura-guia, acompanhada da geometria dessa
/// moldura para que a analise use so o que estava la dentro.
class GuidedShot {
  final XFile file;
  final CaptureFraming framing;

  const GuidedShot({required this.file, required this.framing});
}

/// Geometria da moldura-guia. Vive num so sitio porque e usada duas vezes: para
/// desenhar o overlay e para recortar a foto antes da inferencia. Se as duas
/// contas divergirem, o agricultor enquadra uma coisa e o modelo ve outra.
Rect guideFrameRect(Size size) {
  // Moldura quase quadrada, centrada, ~80% da largura. Enquadra uma folha.
  final side = size.width * 0.80;
  final left = (size.width - side) / 2;
  final top = (size.height - side) / 2 - 10;
  return Rect.fromLTWH(left, top, side, side);
}

/// Tela de captura com moldura-guia. Ao contrario da camera nativa aberta pelo
/// image_picker, aqui temos o preview ao vivo dentro do app, o que permite
/// desenhar por cima uma moldura e a instrucao "Aproxime de uma folha".
///
/// O modelo foi treinado com fotos aproximadas de UMA folha; fotos de planta
/// inteira a distancia degradam muito a inferencia. A moldura empurra o
/// agricultor para o enquadramento certo.
///
/// Devolve o [GuidedShot] capturado via Navigator.pop, ou null se cancelar.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _capturing = false;
  String? _error;

  /// Area onde o preview e o overlay foram efetivamente pintados. E a mesma
  /// base de coordenadas que o painter recebe, por isso e ela que viaja com a
  /// foto para o recorte.
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // A camera segura recursos do sistema: ao sair do app libertamos o
  // controlador e reinicializamos ao voltar, evitando preview congelado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'Nenhuma câmara disponível.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      final future = controller.initialize();
      if (!mounted) {
        await future;
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      await future;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Não foi possível abrir a câmara. Verifique a permissão nas definições.');
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(
        GuidedShot(
          file: file,
          framing: CaptureFraming(
            frame: guideFrameRect(_viewport),
            viewport: _viewport,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Falha ao tirar a fotografia. Tente novamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildPreview(),
              // Escurece tudo menos a moldura e desenha os cantos da moldura.
              const Positioned.fill(child: _FrameOverlay()),
              _buildTopInstruction(),
              _buildBottomBar(context),
              if (_error != null) _buildError(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    // previewSize vem em orientacao paisagem; trocamos os lados para preencher
    // o ecra em retrato sem distorcer (BoxFit.cover).
    final preview = controller.value.previewSize;
    final w = preview?.height ?? controller.value.previewSize?.width ?? 1;
    final h = preview?.width ?? controller.value.previewSize?.height ?? 1;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: w,
        height: h,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildTopInstruction() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aproxime de uma folha',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Encha a moldura · boa luz · fundo simples',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final ready =
        _controller?.value.isInitialized == true && !_capturing;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 28, top: 12),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Uma folha inteira dentro da moldura dá um diagnóstico mais fiável.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: ready ? _capture : null,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: ready ? 1 : 0.5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 4,
                    ),
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(22),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.black54,
                          ),
                        )
                      : const Icon(Icons.camera_alt_rounded,
                          color: Color(0xFF2E7D32), size: 34),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 140,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// Desenha um scrim escuro por todo o ecra, deixando transparente apenas a
/// moldura central (quadrada, cantos arredondados) e realca os quatro cantos.
class _FrameOverlay extends StatelessWidget {
  const _FrameOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _FramePainter()),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = guideFrameRect(size);
    const radius = Radius.circular(24);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // Scrim: preenche tudo e recorta a moldura (even-odd).
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Borda fina da moldura.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    // Cantos em destaque (verde da marca) para guiar o olhar.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF7CDB84);
    const len = 30.0;
    // Superior esquerdo
    canvas.drawLine(rect.topLeft + const Offset(0, 24),
        rect.topLeft + const Offset(0, 24 + len), corner);
    canvas.drawLine(rect.topLeft + const Offset(24, 0),
        rect.topLeft + const Offset(24 + len, 0), corner);
    // Superior direito
    canvas.drawLine(rect.topRight + const Offset(0, 24),
        rect.topRight + const Offset(0, 24 + len), corner);
    canvas.drawLine(rect.topRight + const Offset(-24, 0),
        rect.topRight + const Offset(-24 - len, 0), corner);
    // Inferior esquerdo
    canvas.drawLine(rect.bottomLeft + const Offset(0, -24),
        rect.bottomLeft + const Offset(0, -24 - len), corner);
    canvas.drawLine(rect.bottomLeft + const Offset(24, 0),
        rect.bottomLeft + const Offset(24 + len, 0), corner);
    // Inferior direito
    canvas.drawLine(rect.bottomRight + const Offset(0, -24),
        rect.bottomRight + const Offset(0, -24 - len), corner);
    canvas.drawLine(rect.bottomRight + const Offset(-24, 0),
        rect.bottomRight + const Offset(-24 - len, 0), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
