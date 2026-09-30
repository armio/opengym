/// Spanish labels for the exercise taxonomy (body parts, equipment, target and secondary
/// muscles), identical to `frontend/src/locales/es.js` and the `*_es` fields of
/// `assets/exercises.json`. Lowercase, like the dataset; capitalise for display.
library;

const Map<String, String> bodyPartsEs = {
  'back': 'espalda',
  'cardio': 'cardio',
  'chest': 'pecho',
  'lower arms': 'antebrazos',
  'lower legs': 'pantorrillas',
  'neck': 'cuello',
  'shoulders': 'hombros',
  'upper arms': 'brazos',
  'upper legs': 'piernas',
  'waist': 'abdomen',
};

const Map<String, String> equipmentEs = {
  'assisted': 'asistido',
  'band': 'banda',
  'barbell': 'barra',
  'body weight': 'peso corporal',
  'bosu ball': 'bosu',
  'cable': 'polea',
  'custom': 'propio',
  'dumbbell': 'mancuerna',
  'elliptical machine': 'elíptica',
  'ez barbell': 'barra EZ',
  'hammer': 'martillo',
  'kettlebell': 'kettlebell',
  'leverage machine': 'máquina de palanca',
  'medicine ball': 'balón medicinal',
  'olympic barbell': 'barra olímpica',
  'resistance band': 'banda de resistencia',
  'roller': 'rodillo',
  'rope': 'cuerda',
  'skierg machine': 'SkiErg',
  'sled machine': 'trineo',
  'smith machine': 'máquina Smith',
  'stability ball': 'fitball',
  'stationary bike': 'bici estática',
  'stepmill machine': 'escaladora',
  'tire': 'neumático',
  'trap bar': 'barra hexagonal',
  'upper body ergometer': 'ergómetro de brazos',
  'weighted': 'con lastre',
  'wheel roller': 'rueda abdominal',
};

const Map<String, String> targetsEs = {
  'abductors': 'abductores',
  'abs': 'abdominales',
  'adductors': 'aductores',
  'biceps': 'bíceps',
  'calves': 'gemelos',
  'cardiovascular system': 'sistema cardiovascular',
  'delts': 'deltoides',
  'forearms': 'antebrazos',
  'glutes': 'glúteos',
  'hamstrings': 'isquiotibiales',
  'lats': 'dorsales',
  'levator scapulae': 'elevador de la escápula',
  'pectorals': 'pectorales',
  'quads': 'cuádriceps',
  'serratus anterior': 'serrato anterior',
  'spine': 'columna',
  'traps': 'trapecios',
  'triceps': 'tríceps',
  'upper back': 'espalda alta',
};

const Map<String, String> secondaryMusclesEs = {
  'abdominals': 'abdominales',
  'ankle stabilizers': 'estabilizadores de tobillo',
  'ankles': 'tobillos',
  'back': 'espalda',
  'biceps': 'bíceps',
  'brachialis': 'braquial',
  'calves': 'gemelos',
  'chest': 'pecho',
  'core': 'core',
  'deltoids': 'deltoides',
  'feet': 'pies',
  'forearms': 'antebrazos',
  'glutes': 'glúteos',
  'grip muscles': 'agarre',
  'groin': 'ingle',
  'hamstrings': 'isquiotibiales',
  'hands': 'manos',
  'hip flexors': 'flexores de cadera',
  'inner thighs': 'cara interna del muslo',
  'latissimus dorsi': 'dorsal ancho',
  'lats': 'dorsales',
  'lower abs': 'abdominales inferiores',
  'lower back': 'zona lumbar',
  'obliques': 'oblicuos',
  'quadriceps': 'cuádriceps',
  'rear deltoids': 'deltoides posterior',
  'rhomboids': 'romboides',
  'rotator cuff': 'manguito rotador',
  'shins': 'espinillas',
  'shoulders': 'hombros',
  'soleus': 'sóleo',
  'sternocleidomastoid': 'esternocleidomastoideo',
  'trapezius': 'trapecio',
  'traps': 'trapecios',
  'triceps': 'tríceps',
  'upper back': 'espalda alta',
  'upper chest': 'pecho superior',
  'wrist extensors': 'extensores de muñeca',
  'wrist flexors': 'flexores de muñeca',
  'wrists': 'muñecas',
};

/// Spanish label of a body part (`'upper legs'` → `'piernas'`); unknown values pass through.
String bodyPartLabel(String bodyPart) => bodyPartsEs[bodyPart] ?? bodyPart;

/// Spanish label of an equipment value (`'custom'` → `'propio'`); unknown values pass through.
String equipmentLabel(String equipment) => equipmentEs[equipment] ?? equipment;

/// Spanish label of a target muscle; unknown values pass through.
String targetLabel(String target) => targetsEs[target] ?? target;

/// Spanish label of a secondary muscle; unknown values pass through.
String muscleLabel(String muscle) => secondaryMusclesEs[muscle] ?? targetsEs[muscle] ?? muscle;
