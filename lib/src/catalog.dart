import 'core.dart';
import 'kinds/fun.dart';
import 'kinds/pen.dart';
import 'kinds/quiz.dart';
import 'kinds/social.dart';
import 'kinds/talk.dart';

/// Parti ve Aile oyun türleri.
const Map<String, PartiKind> kPartiKinds = {
  'isim-sehir': NameCityKind(),
  'yasakli-kelime': TabuKind(),
  'ciz-tahmin': DrawKind(),
  'sessiz-sinema': MimeKind(),
  'dogruluk-cesaret': TruthKind(),
  'sise-cevirme': SpinKind(),
  'ben-kimim': ForeheadKind(),
  'koylu-vampir': VampireKind(),
  'casus-kim': SpyKind(),
  'aile-bilgi': FamilyQuizKind(),
  'skor-tahtasi': ScoreKind(),
  'kelime-ipucu': EmojiClueKind(),
  'emoji-hikaye': StoryKind(),
  'hafiza-zinciri': ChainKind(),
  'hizli-parmak': ReflexKind(),
  'kirik-kalem': BrokenPenKind(),
  'isi-olcer': HeatDialKind(),
};

PartiRules partiRulesFor(String gameId, String kind) => partiRules(gameId, kPartiKinds[kind]!);
