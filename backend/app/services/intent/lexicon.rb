module Intent
  # Word lists for the rule-based extraction that Laya cannot do (it only classifies).
  # Coverage is deliberately modest: English, Korean, Japanese, plus the local names used by
  # the languages in the evaluation set. Anything not recognized is simply left for the user
  # to fill in. Keep entries lowercase; Latin entries match whole words, CJK entries match
  # as substrings. A Regexp entry is used as written.
  module Lexicon
    # Country code (must be in Keyword::COUNTRIES) => names.
    COUNTRIES = {
      "us" => [ "united states", "usa", "u.s.", "미국", "アメリカ", "米国", "estados unidos", "vereinigte staaten", "états-unis", "etats-unis", "amerika serikat" ],
      "gb" => [ "united kingdom", "uk", "great britain", "britain", "england", "영국", "イギリス", "英国", "reino unido", "vereinigtes königreich", "royaume-uni", "inggris" ],
      "ca" => [ "canada", "캐나다", "カナダ", "canadá", "kanada" ],
      "au" => [ "australia", "호주", "오스트레일리아", "オーストラリア", "australien", "australie" ],
      "nz" => [ "new zealand", "뉴질랜드", "ニュージーランド", "nueva zelanda", "neuseeland", "nouvelle-zélande", "selandia baru" ],
      "ie" => [ "ireland", "아일랜드", "アイルランド", "irlanda", "irland", "irlande" ],
      "in" => [ "india", "인도", "インド", "indien", "inde" ],
      "sg" => [ "singapore", "싱가포르", "シンガポール", "singapur", "singapura" ],
      "ph" => [ "philippines", "philippine", "pilipinas", "filipinas", "philippinen", "필리핀", "フィリピン" ],
      "my" => [ "malaysia", "말레이시아", "マレーシア", "malasia", "malaisie" ],
      "id" => [ "indonesia", "인도네시아", "インドネシア", "indonesien", "indonésie" ],
      "th" => [ "thailand", "태국", "tailandia", "thaïlande" ],
      "vn" => [ "vietnam", "viet nam", "베트남", "ベトナム" ],
      "jp" => [ "japan", /일본(?!어)/, /日本(?!語)/, "japón", "japon", "jepang" ],
      "kr" => [ "south korea", "korea", /한국(?!어)/, "대한민국", "韓国", "corea", "südkorea", "corée", "korea selatan" ],
      "tw" => [ "taiwan", "대만", "台湾", "臺灣", "taiwán", "taïwan" ],
      "hk" => [ "hong kong", "hongkong", "홍콩", "香港" ],
      "de" => [ "germany", "deutschland", "독일", "ドイツ", "alemania", "allemagne", "jerman" ],
      "fr" => [ "france", "프랑스", "フランス", "francia", "frankreich", "prancis" ],
      "es" => [ "spain", "españa", "스페인", "スペイン", "spanien", "espagne", "spanyol" ],
      "it" => [ "italy", "italia", "이탈리아", "イタリア", "italien", "italie" ],
      "nl" => [ "netherlands", "holland", "네덜란드", "オランダ", "países bajos", "niederlande", "pays-bas", "belanda" ],
      "se" => [ "sweden", "스웨덴", "スウェーデン", "suecia", "schweden", "suède", "swedia" ],
      "no" => [ "norway", "노르웨이", "ノルウェー", "noruega", "norwegen", "norvège" ],
      "dk" => [ "denmark", "덴마크", "デンマーク", "dinamarca", "dänemark", "danemark" ],
      "fi" => [ "finland", "핀란드", "フィンランド", "finlandia", "finnland", "finlande" ],
      "pl" => [ "poland", "폴란드", "ポーランド", "polonia", "polen", "pologne" ],
      "br" => [ "brazil", "brasil", "브라질", "ブラジル", "brasilien", "brésil" ],
      "mx" => [ "mexico", "méxico", "멕시코", "メキシコ", "mexiko", "mexique" ],
      "ar" => [ "argentina", "아르헨티나", "アルゼンチン", "argentine", "argentinien" ],
      "cl" => [ "chile", "칠레" ],
      "co" => [ "colombia", "콜롬비아", "コロンビア", "kolumbien", "colombie" ],
      "za" => [ "south africa", "남아프리카", "남아공", "南アフリカ", "sudáfrica", "südafrika", "afrique du sud" ],
      "ae" => [ "united arab emirates", "uae", "아랍에미리트", "emiratos árabes" ],
      "sa" => [ "saudi arabia", "사우디", "サウジアラビア", "arabia saudita", "saudi-arabien", "arabie saoudite" ],
      "tr" => [ "turkey", "türkiye", "turkiye", "터키", "튀르키예", "トルコ", "turquía", "türkei", "turquie", "turki" ],
      "il" => [ "israel", "이스라엘", "イスラエル", "israël" ]
    }.freeze

    # Only consulted when no country is named. A city is weaker evidence than a country.
    CITIES = {
      "ph" => [ "manila", "cebu", "davao", "마닐라" ],
      "kr" => [ "seoul", "busan", "서울", "부산", "제주", "강남", "ソウル" ],
      "jp" => [ "tokyo", "osaka", "東京", "大阪", "도쿄", "오사카" ],
      "sg" => [],
      "id" => [ "jakarta", "surabaya", "자카르타" ],
      "es" => [ "madrid", "barcelona" ],
      "fr" => [ "paris", "lyon" ],
      "de" => [ "münchen", "munich", "berlin" ],
      "ca" => [ "toronto" ],
      "us" => [ "dallas", "new york", "san francisco" ]
    }.freeze

    # The language to search in when none is stated: the main language of the country. A
    # country without a supported language (e.g. tw) is left blank and asked about.
    DEFAULT_LANGUAGE = {
      "us" => "en", "gb" => "en", "ca" => "en", "au" => "en", "nz" => "en", "ie" => "en", "in" => "en",
      "sg" => "en", "ph" => "en", "my" => "en", "hk" => "en", "za" => "en", "id" => "id", "th" => "th",
      "vn" => "vi", "jp" => "ja", "kr" => "ko", "de" => "de", "fr" => "fr", "es" => "es", "it" => "it",
      "nl" => "nl", "se" => "sv", "no" => "no", "dk" => "da", "fi" => "fi", "pl" => "pl", "br" => "pt",
      "mx" => "es", "ar" => "es", "cl" => "es", "co" => "es", "ae" => "ar", "sa" => "ar", "tr" => "tr",
      "il" => "he"
    }.freeze

    # "Compare with an earlier result". A time reference alone ("from last week") is not a
    # comparison, so these are words that ask to compare, or that say "than before / since".
    COMPARE_CUES = [
      /\b(compare|compared|comparing|comparison|versus|vs\.?)\b/i, /\bsince\b/i, /\bwhat changed\b/i, /\bthan (it was|before|last)\b/i,
      /\bbetter than\b/i, /\bcompárala?\b/i, /\bcompar(a|ar|ado)\b/i, /\bvergleich\w*/i, /\bcompar(e|er|é)\b/i,
      /\bbandingkan\b/i, /\bdibanding\w*\b/i, /\bihambing\b/i, /\bkumpara\b/i, /\bdesde\b/i, /\bseit\b/i, /\bdepuis\b/i,
      /\bsejak\b/i, /\bmula noong\b/i, /비교/, /대비/, /보다\s*(올랐|내렸|떨어|좋|나빠)/, /이후/, /달라진/, /바뀐/,
      /比べ/, /比較/, /差分/, /以降/, /前回より/, /より.*(上が|下が)/
    ].freeze

    # "Only new or changed items".
    ONLY_NEW_CUES = [
      /\bnew\b/i, /\bnewly\b/i, /\bonly (what|the|if)\b.*\b(new|changed|different|differences)\b/i, /\bjust the (differences|changes)\b/i,
      /\bonly .*\bchanged\b/i, /\bbago\b/i, /\bbagong\b/i, /\bnuev[oa]s?\b/i, /\bneue[nr]?\b/i, /\bneu\b/i, /\bnouvel(le)?s?\b/i,
      /\bbaru\b/i, /새로/, /새\s*공고/, /새\s*채용/, /달라진\s*(것|점)/, /바뀐\s*것/, /新着/, /新しく/, /新規/, /差分/, /変わった/
    ].freeze

    # Tokens that look like a domain only because of the final label, e.g. "Node.js". A
    # domain is accepted when its last label is in this list or it carries a scheme or www.
    COMMON_TLDS = %w[
      com net org io co dev app ai info biz edu gov kr jp cn tw hk sg ph my id th vn in au nz uk ca us de fr es it nl se
      no dk fi pl br mx ar cl za ae sa tr il ru eu xyz me tv ly site shop blog online tech cloud
    ].freeze
  end
end
