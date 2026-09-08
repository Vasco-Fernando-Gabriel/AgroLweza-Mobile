# Agrolweza Mobile

App Android que diagnostica doenças da mandioca a partir de uma foto da folha, **offline**, no telemóvel do agricultor. Flutter + TensorFlow Lite no dispositivo.

Estado do projeto e roadmap: `MVP-ESPECIFICACAO-TECNICA-PARA-PROTOTIPO.md` e `STATUS.md` na pasta do protótipo (`Pictures\Plataforma de Inteligência Agrícola para\agroia-prototipo`). Acompanhamento no quadro Kanban **AGL**.

## Requisitos

- Flutter (canal stable) e Android SDK.
- Um dispositivo ou emulador Android.

## Correr em desenvolvimento

```bash
flutter pub get
flutter run
```

## Testes e análise

```bash
flutter analyze      # tem de ficar limpo
flutter test         # 23 testes
```

## Build da APK de distribuição

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

**Regra de ABI (não ignorar):** o build tem de gerar `lib/armeabi-v7a` **e** `lib/arm64-v8a`, e **cada** pasta `lib/<abi>` da APK tem de conter `libflutter.so` + `libapp.so`. Builds com só `--target-platform android-arm64` já geraram uma `armeabi-v7a` sem essas libs; o telemóvel elegia essa ABI e rebentava no arranque com `UnsatisfiedLinkError`. A exclusão de `lib/x86*` está em `android/app/build.gradle.kts` (`packaging.jniLibs.excludes`) — `ndk.abiFilters` sozinho não chega porque o plugin Gradle do Flutter sobrepõe.

Verificar antes de distribuir:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep 'lib/.*\.so'
```

## Instalação por sideload

A APK é assinada com a **chave debug** do Flutter. Ao instalar por WhatsApp/ficheiro, o Play Protect bloqueia com "app de programador desconhecido". No modal, tocar no texto pequeno **"Instalar mesmo assim"** — **não** no botão azul "OK", que cancela. Updates com a mesma chave instalam por cima sem desinstalar. O aviso só desaparece de vez publicando na Play Store (Internal Testing).

## Notas de build conhecidas

- Plugin `camera` (camerax): `camera-core` expõe `concurrent-futures` só como `implementation` e o `javac` do módulo do plugin não acha `CallbackToFutureAdapter`. Corrigido injetando `androidx.concurrent:concurrent-futures` **só** no módulo `:camera_android_camerax` via `subprojects`/`afterEvaluate` em `android/build.gradle.kts` (não mexer no `app`).

## Estrutura

```
lib/
  main.dart                    fluxo, ecrãs, orquestração
  inference_service.dart       carrega o .tflite, recorta pela moldura, classifica
  camera_capture_screen.dart   câmara com moldura-guia
  fixtures.dart                catálogo classe -> label, gravidade, observações, recomendação
  history_item.dart            modelo do diagnóstico + estados de sincronização
  history_repository.dart      persistência local (SharedPreferences)
  sync_service.dart            fila de sincronização (transporte simulado e HTTP)
  angola_regions.dart          21 províncias e municípios
assets/models/                 agrolweza_cassava_baseline.tflite + labels
test/                          23 testes
```
