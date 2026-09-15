/// Catálogo de diagnósticos possíveis (classes do modelo real MobileNetV3Small
/// treinado no dataset Cassava Leaf Disease, mais o estado de recusa por
/// baixa confiança). A confiança em si é dinâmica, vem da inferência real —
/// não faz parte deste catálogo.
class DiagnosisInfo {
  final String id;
  final String label;
  final String severity;
  final String tone; // good | warn | neutral
  final List<String> observations;
  final String recommendation;

  const DiagnosisInfo({
    required this.id,
    required this.label,
    required this.severity,
    required this.tone,
    required this.observations,
    required this.recommendation,
  });
}

const Map<String, DiagnosisInfo> diagnosisCatalog = {
  // ATENÇÃO antes de "melhorar" este texto de volta para "Planta saudável":
  // o modelo NÃO sabe dizer que uma planta está sã. Só sabe dizer que não
  // encontrou as doenças que lhe ensinámos. Medido a 2026-09-15 com o modelo
  // do feijão contra folhas de outras culturas: uma folha de milho COM
  // ferrugem foi classificada como saudável em 78% dos casos, e folhas sãs de
  // batata, soja e videira deram confiança 0.99-1.00. Fora das classes
  // conhecidas, "saudável" é o balde onde cai tudo o que o modelo não percebe.
  // Prometer saúde aqui faz o agricultor não tratar e perder a lavra.
  'healthy': DiagnosisInfo(
    id: 'healthy',
    label: 'Sem sinais das doenças que sei reconhecer',
    severity: 'Indefinida',
    tone: 'ok',
    observations: [
      'Não encontrei nesta folha as doenças que fui treinado a reconhecer',
      'Isto NÃO garante que a planta esteja sã: há doenças e pragas que ainda '
          'não sei identificar',
    ],
    recommendation:
        'Continue a acompanhar a plantação. Se a planta piorar, ou se vir '
        'sinais que esta análise não explica, procure um técnico agrícola.',
  ),
  'cassava_mosaic': DiagnosisInfo(
    id: 'cassava_mosaic',
    label: 'Possível mosaico da mandioca',
    severity: 'Moderada',
    tone: 'warn',
    observations: [
      'Manchas claras e amareladas nas folhas',
      'Possível deformação foliar',
    ],
    recommendation:
        'Separe a planta suspeita e procure um técnico agrícola para confirmação.',
  ),
  'cassava_bacterial_blight': DiagnosisInfo(
    id: 'cassava_bacterial_blight',
    label: 'Possível bacteriose da mandioca',
    severity: 'Moderada',
    tone: 'warn',
    observations: [
      'Manchas encharcadas nas folhas',
      'Possível murcha nos ramos',
    ],
    recommendation:
        'Remova os ramos afetados e evite trabalhar na plantação em dias de chuva.',
  ),
  'cassava_brown_streak': DiagnosisInfo(
    id: 'cassava_brown_streak',
    label: 'Possível estria castanha da mandioca',
    severity: 'Alta',
    tone: 'warn',
    observations: [
      'Estrias acastanhadas visíveis no caule',
      'Pode afetar a raiz mesmo sem sinais fortes na folha',
    ],
    recommendation:
        'Evite usar esta planta para novas estacas e procure orientação técnica com urgência.',
  ),
  'cassava_green_mottle': DiagnosisInfo(
    id: 'cassava_green_mottle',
    label: 'Possível mosqueado verde da mandioca',
    severity: 'Moderada',
    tone: 'warn',
    observations: ['Manchas verde-claras irregulares nas folhas'],
    recommendation:
        'Observe a evolução nas próximas semanas e informe um técnico se piorar.',
  ),
  'unknown': DiagnosisInfo(
    id: 'unknown',
    label: 'Não foi possível confirmar com segurança',
    severity: 'Indefinida',
    tone: 'neutral',
    observations: [
      'A confiança do modelo ficou abaixo do limite seguro para esta imagem',
    ],
    recommendation:
        'Tire uma nova fotografia com boa luz, focando bem a folha, ou peça avaliação de um técnico.',
  ),
};
