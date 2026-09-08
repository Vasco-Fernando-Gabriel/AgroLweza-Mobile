/// Divisao administrativa de Angola para etiquetar o local do diagnostico.
///
/// FONTE DOS DADOS
/// - Estrutura de 21 provincias: reforma politico-administrativa de 2024, em
///   vigor desde 01/01/2025 (Bengo, Benguela, Bie, Cabinda, Cuando, Cuando
///   Cubango dividido em Cubango+Cuando, Icolo e Bengo separado de Luanda,
///   Moxico Leste separado de Moxico).
/// - Nomes dos municipios: PDF "Angola - Provincias & Municipios" fornecido
///   pelo utilizador (base dos 164 municipios estabelecidos), limpos a mao.
///
/// LIMITES CONHECIDOS (a verificar contra o Decreto Presidencial da nova
/// divisao antes de tratar isto como fonte oficial):
/// 1. A reforma de 2025 elevou comunas e passou de 164 para 326 municipios.
///    Os municipios NOVOS ainda nao constam aqui: esta lista e a base 164
///    reestruturada, suficiente para etiquetar o campo, nao exaustiva.
/// 2. A reparticao dos municipios entre CUBANGO/CUANDO e entre MOXICO/
///    MOXICO LESTE e best-effort geografico (marcada abaixo). Confirmar.
///
/// A UI depende SO da forma (provincia -> lista de municipios); completar ou
/// corrigir os dados aqui nao exige mudar o ecra nem o modelo.
library;

/// Provincias na ordem a mostrar (alfabetica).
const angolaProvinces = <String>[
  'Bengo',
  'Benguela',
  'Bié',
  'Cabinda',
  'Cuando', // novo (2024), capital Mavinga
  'Cuanza Norte',
  'Cuanza Sul',
  'Cubango', // ex-Cuando Cubango (2024), capital Menongue
  'Cunene',
  'Huambo',
  'Huíla',
  'Icolo e Bengo', // novo (2024), separado de Luanda, capital Catete
  'Luanda',
  'Lunda Norte',
  'Lunda Sul',
  'Malanje',
  'Moxico',
  'Moxico Leste', // novo (2024), capital Cazombo
  'Namibe',
  'Uíge',
  'Zaire',
];

/// Municipios por provincia (ordenados alfabeticamente).
const angolaMunicipalities = <String, List<String>>{
  'Bengo': [
    'Ambriz',
    'Bula Atumba',
    'Dande',
    'Dembos',
    'Nambuangongo',
    'Pango Aluquém',
  ],
  'Benguela': [
    'Baía Farta',
    'Balombo',
    'Benguela',
    'Bocoio',
    'Caimbambo',
    'Catumbela',
    'Chongorói',
    'Cubal',
    'Ganda',
    'Lobito',
  ],
  'Bié': [
    'Andulo',
    'Camacupa',
    'Catabola',
    'Chinguar',
    'Chitembo',
    'Cuemba',
    'Cunhinga',
    'Kuito',
    'Nharea',
  ],
  'Cabinda': [
    'Belize',
    'Buco-Zau',
    'Cabinda',
    'Cacongo',
  ],
  // best-effort: reparticao Cuando/Cubango carece de confirmacao oficial.
  'Cuando': [
    'Cuito Cuanavale',
    'Dirico',
    'Mavinga',
    'Rivungo',
  ],
  'Cuanza Norte': [
    'Ambaca',
    'Banga',
    'Bolongongo',
    'Cambambe',
    'Cazengo',
    'Golungo Alto',
    'Gonguembo',
    'Lucala',
    'Quiculungo',
    'Samba Caju',
  ],
  'Cuanza Sul': [
    'Amboim',
    'Cassongue',
    'Cela',
    'Conda',
    'Ebo',
    'Libolo',
    'Mussende',
    'Porto Amboim',
    'Quibala',
    'Quilenda',
    'Seles',
    'Sumbe',
  ],
  // best-effort: reparticao Cuando/Cubango carece de confirmacao oficial.
  'Cubango': [
    'Calai',
    'Cuangar',
    'Cuchi',
    'Menongue',
    'Nancova',
  ],
  'Cunene': [
    'Cahama',
    'Cuanhama',
    'Curoca',
    'Cuvelai',
    'Namacunde',
    'Ombadja',
  ],
  'Huambo': [
    'Bailundo',
    'Caála',
    'Catchiungo',
    'Chicala-Cholohanga',
    'Chinjenje',
    'Ecunha',
    'Huambo',
    'Londuimbali',
    'Longonjo',
    'Mungo',
    'Ucuma',
  ],
  'Huíla': [
    'Caconda',
    'Cacula',
    'Caluquembe',
    'Chibia',
    'Chicomba',
    'Chipindo',
    'Cuvango',
    'Gambos',
    'Humpata',
    'Jamba',
    'Lubango',
    'Matala',
    'Quilengues',
    'Quipungo',
  ],
  // separado de Luanda (2024): antigos municipios de Icolo e Bengo e Quissama.
  'Icolo e Bengo': [
    'Icolo e Bengo',
    'Quissama',
  ],
  'Luanda': [
    'Belas',
    'Cacuaco',
    'Cazenga',
    'Kilamba Kiaxi',
    'Luanda',
    'Talatona',
    'Viana',
  ],
  'Lunda Norte': [
    'Cambulo',
    'Capenda-Camulemba',
    'Caungula',
    'Chitato',
    'Cuango',
    'Cuilo',
    'Lóvua',
    'Lubalo',
    'Lucapa',
    'Xá-Muteba',
  ],
  'Lunda Sul': [
    'Cacolo',
    'Dala',
    'Muconda',
    'Saurimo',
  ],
  'Malanje': [
    'Cacuso',
    'Cahombo',
    'Calandula',
    'Cambundi-Catembo',
    'Cangandala',
    'Cunda-Dia-Baze',
    'Kiwaba Nzoji',
    'Luquembo',
    'Malanje',
    'Marimba',
    'Massango',
    'Mucari',
    'Quela',
    'Quirima',
  ],
  // best-effort: reparticao Moxico/Moxico Leste carece de confirmacao oficial.
  'Moxico': [
    'Bundas',
    'Camanongue',
    'Léua',
    'Luchazes',
    'Moxico',
  ],
  // best-effort: reparticao Moxico/Moxico Leste carece de confirmacao oficial.
  'Moxico Leste': [
    'Alto Zambeze',
    'Cameia',
    'Luacano',
    'Luau',
  ],
  'Namibe': [
    'Bibala',
    'Camucuio',
    'Moçâmedes',
    'Tômbwa',
    'Virei',
  ],
  'Uíge': [
    'Ambuíla',
    'Bembe',
    'Buengas',
    'Bungo',
    'Cangola',
    'Damba',
    'Maquela do Zombo',
    'Milunga',
    'Mucaba',
    'Negage',
    'Puri',
    'Quimbele',
    'Quitexe',
    'Sanza Pombo',
    'Songo',
    'Uíge',
  ],
  'Zaire': [
    'Cuimba',
    "M'Banza Congo",
    "N'zeto",
    'Nóqui',
    'Soyo',
    'Tomboco',
  ],
};

/// Municipios de uma provincia (vazio se a provincia for desconhecida).
List<String> municipalitiesOf(String province) =>
    angolaMunicipalities[province] ?? const [];
