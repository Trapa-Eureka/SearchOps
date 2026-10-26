require "rails_helper"

RSpec.describe Intent::Extractor do
  def extract(text)
    described_class.call(text)
  end

  describe "country" do
    {
      "Find remote jobs in the Philippines" => "ph",
      "필리핀에서 채용공고 찾아줘" => "ph",
      "フィリピンで求人を探して" => "ph",
      "Busco empleo en España" => "es",
      "Stellenangebote in Deutschland" => "de",
      "Cari lowongan di Indonesia" => "id",
      "한국 시장에서 순위 확인" => "kr",
      "Rank in the UK" => "gb",
      "United States results please" => "us",
      "South Korea ranking" => "kr",
      "대한민국 검색 결과" => "kr"
    }.each do |text, code|
      it "reads #{text.inspect} as #{code}" do
        expect(extract(text).country).to eq(code)
      end
    end

    it "keeps the evidence that matched" do
      expect(extract("Find jobs in the Philippines").country_evidence).to eq("philippines")
    end

    it "does not read Indonesia as India (longer names are claimed first)" do
      result = extract("인도네시아 채용")

      expect(result.country).to eq("id")
      expect(result.country_candidates).to eq([ "id" ])
    end

    it "does not read a language name as a country" do
      expect(extract("일본어 공부 방법").country).to be_nil
      expect(extract("日本語の勉強").country).to be_nil
      expect(extract("한국어 번역").country).to be_nil
    end

    it "still reads the country when it is followed by a particle" do
      expect(extract("일본에서 일하고 싶어").country).to eq("jp")
      expect(extract("日本で仕事を探す").country).to eq("jp")
    end

    it "matches Latin names as whole words only" do
      expect(extract("the duke of york").country).to be_nil
      expect(extract("Indiana Jones").country).to be_nil
      expect(extract("the chili recipe").country).to be_nil
    end

    it "reports two countries as ambiguous instead of choosing" do
      result = extract("Compare Japan and Korea")

      expect(result.country).to be_nil
      expect(result.country_candidates).to contain_exactly("jp", "kr")
    end

    it "returns nothing when no country is named" do
      result = extract("Where does example.com rank?")

      expect([ result.country, result.country_candidates, result.language ]).to eq([ nil, [], nil ])
    end

    it "falls back to a city only when no country is named" do
      expect(extract("jobs in Cebu").country).to eq("ph")
      expect(extract("서울 채용 공고").country).to eq("kr")
      expect(extract("jobs in Manila, Philippines").country_evidence).to eq("philippines")
    end

    it "lists every country alias that points at a supported country code" do
      expect(Intent::Lexicon::COUNTRIES.keys - Keyword::COUNTRIES).to eq([])
      expect(Intent::Lexicon::CITIES.keys - Keyword::COUNTRIES).to eq([])
    end
  end

  describe "language" do
    it "follows the main language of the country" do
      expect(extract("jobs in Japan").language).to eq("ja")
      expect(extract("jobs in the Philippines").language).to eq("en")
      expect(extract("jobs in Brazil").language).to eq("pt")
    end

    it "stays blank for a country without a supported language" do
      result = extract("Taiwan rankings")

      expect(result.country).to eq("tw")
      expect(result.language).to be_nil
    end

    it "only proposes supported languages" do
      expect(Intent::Lexicon::DEFAULT_LANGUAGE.values.uniq - Keyword::LANGUAGES).to eq([])
    end
  end

  describe "target domain" do
    {
      "Where does example.com rank?" => "example.com",
      "check https://www.Shop.Example.com/page?x=1 now" => "shop.example.com",
      "example.com이 몇 위인지" => "example.com",
      "순위 확인 www.example.co.kr 도메인" => "example.co.kr",
      "ranking of mysite.io for shoes" => "mysite.io"
    }.each do |text, domain|
      it "finds #{domain} in #{text.inspect}" do
        expect(extract(text).target_domain).to eq(domain)
      end
    end

    it "does not take software names such as Node.js for domains" do
      expect(extract("Senior Node.js developer").target_domain).to be_nil
      expect(extract("Vue.js and Next.js jobs").domain_candidates).to eq([])
    end

    it "ignores abbreviations and version numbers" do
      expect(extract("e.g. react, i.e. the library, version 3.5").domain_candidates).to eq([])
    end

    it "does not choose between two different domains" do
      result = extract("compare example.com and another.org")

      expect(result.target_domain).to be_nil
      expect(result.domain_candidates).to contain_exactly("example.com", "another.org")
    end

    it "counts the same domain mentioned twice once" do
      expect(extract("example.com vs https://example.com/").target_domain).to eq("example.com")
    end

    it "ignores an e-mail address" do
      expect(extract("mail me at someone@example.com").domain_candidates).to eq([])
    end

    it "never returns an IP address or a single-label host" do
      expect(extract("check 192.168.0.1 and localhost").domain_candidates).to eq([])
    end
  end

  describe "query" do
    {
      "'react developer jobs'" => "react developer jobs",
      "\"best crm software\"" => "best crm software",
      "“cloud backup”" => "cloud backup",
      "「格安SIM」で順位" => "格安SIM",
      "『英会話』の順位" => "英会話",
      "'제주 맛집' 검색에서" => "제주 맛집",
      "example.com이 'react 개발자'로 몇 위?" => "react 개발자"
    }.each do |text, query|
      it "takes the quoted phrase #{query.inspect} from #{text.inspect}" do
        expect(extract(text).query).to eq(query)
      end
    end

    it "does not mistake English apostrophes for quotes" do
      expect(extract("don't check it's rank, I'm busy").query).to be_nil
      expect(extract("Don't check 'best crm' please").query).to eq("best crm")
    end

    it "does not pick a quoted domain as the query" do
      expect(extract("rank of 'example.com' for 'shoes'").query).to eq("shoes")
    end

    it "gives up when several different phrases are quoted" do
      result = extract("'shoes' or 'boots'")

      expect(result.query).to be_nil
      expect(result.query_candidates).to eq([ "shoes", "boots" ])
    end

    it "takes the Latin phrase inside a sentence written in another script" do
      result = extract("필리핀에서 Senior React Developer 원격 채용공고를 찾아줘")

      expect(result.query).to eq("Senior React Developer")
    end

    it "keeps dots and plus signs inside such a phrase" do
      expect(extract("서울에서 Node.js 개발자 찾기").query).to eq("Node.js")
      expect(extract("C++ 개발자 채용").query).to eq("C++")
    end

    it "does not guess a query from a plain English sentence, and offers no suggestion for it" do
      result = extract("Find remote React jobs in the Philippines")

      expect(result.query).to be_nil
      expect(result.query_candidates).to eq([])
    end

    it "suggests quoted phrases and Latin phrases, never a rewrite of the whole sentence" do
      expect(extract("'shoes' or 'boots'").query_candidates).to eq([ "shoes", "boots" ])
      expect(extract("서울에서 Senior React Developer 찾아줘").query_candidates).to eq([ "Senior React Developer" ])
      expect(extract("Where does example.com rank for react jobs").query_candidates).to eq([])
    end

    it "offers nothing for an empty-ish text" do
      expect(extract("...").query_candidates).to eq([])
    end
  end

  describe "comparison and novelty cues" do
    {
      compare_cue: {
        true => [
          "Check my rank and compare it with last week", "지난주와 비교해서 알려줘", "先週と比べて順位が変わった？",
          "Ihambing sa nakaraang linggo", "compárala con la semana pasada", "Vergleiche mit letzter Woche",
          "Tolong bandingkan dengan minggu lalu", "better than it was last month?", "new postings since Monday",
          "내 순위가 지난주보다 올랐나요", "어제 대비 변화"
        ],
        false => [
          "Show me my saved snapshots from last week", "Where does example.com rank?", "순위 기록 보여줘",
          "過去の検索履歴を見せて", "Find remote React jobs", "ok thanks"
        ]
      },
      only_new_cue: {
        true => [
          "Show only new job openings", "새 공고만 보여줘", "달라진 점만 알려줘", "新着の求人だけ見せて",
          "Mga bagong job opening", "Just the differences please", "Only tell me if it changed",
          "nuevas ofertas de trabajo", "neue Jobangebote", "lowongan yang baru"
        ],
        false => [
          "Show all job openings", "Where does example.com rank?", "순위 기록 보여줘", "ok thanks", "Find remote React jobs"
        ]
      }
    }.each do |cue, groups|
      groups.each do |expected, texts|
        texts.each do |text|
          it "#{cue} is #{expected} for #{text.inspect}" do
            expect(extract(text).public_send(cue)).to eq(expected)
          end
        end
      end
    end
  end

  describe "masked text (what the classifier is given)" do
    it "replaces the quoted keyword and the domain with neutral words" do
      result = extract("Check the Google rank of example.com for 'react developer jobs' in the Philippines")

      expect(result.masked_text).to eq("Check the Google rank of DOMAIN for 'KEYWORD' in the Philippines")
    end

    it "keeps the quote marks, including CJK brackets and curly quotes" do
      expect(extract("「格安SIM」で example.com の順位").masked_text).to eq("「KEYWORD」で DOMAIN の順位")
      expect(extract("rank for “cloud backup” on mysite.io").masked_text).to eq("rank for “KEYWORD” on DOMAIN")
    end

    it "masks every quoted phrase and every domain" do
      result = extract("'shoes' on example.com and 'boots' on other.org")

      expect(result.masked_text).to eq("'KEYWORD' on DOMAIN and 'KEYWORD' on DOMAIN")
    end

    it "keeps a Latin phrase without quotes, which carries the meaning in a job search" do
      expect(extract("필리핀에서 Senior React Developer 원격 채용공고를 찾아줘").masked_text).to eq("필리핀에서 Senior React Developer 원격 채용공고를 찾아줘")
    end

    it "does not mask software names such as Node.js" do
      expect(extract("Find Node.js jobs").masked_text).to eq("Find Node.js jobs")
    end

    it "leaves text without a keyword or domain unchanged" do
      expect(extract("show my saved search history").masked_text).to eq("show my saved search history")
    end

    it "never contains the user's keyword or domain" do
      masked = extract("rank of private-site.com for 'my secret keyword'").masked_text

      expect(masked).not_to include("private-site", "secret")
    end
  end

  describe "robustness" do
    it "handles empty, whitespace, and very long input" do
      expect { extract("") }.not_to raise_error
      expect { extract("   ") }.not_to raise_error
      expect { extract("a" * 10_000) }.not_to raise_error
    end

    it "handles non-string input" do
      expect { described_class.call(nil) }.not_to raise_error
    end

    it "finishes quickly on pathological input" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      extract("a." * 2_000 + "'" * 500)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.0
    end
  end
end
