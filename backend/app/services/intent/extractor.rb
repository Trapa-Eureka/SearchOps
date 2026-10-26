module Intent
  # Rule-based extraction of what Laya does not provide: country, language, target domain,
  # query candidates, and the comparison cues. It never decides the intent.
  #
  # Every value carries its evidence (the matched text), so the plan can show where it came
  # from. Nothing is guessed: ambiguous or missing values are reported, not filled in.
  class Extractor
    Extraction = Data.define(:country, :country_candidates, :country_evidence, :language, :target_domain,
                             :domain_candidates, :query, :query_candidates, :compare_cue, :only_new_cue, :masked_text)

    QUOTE_PAIRS = [
      /(?<![A-Za-z0-9])'([^'\n]{2,100}?)'(?![A-Za-z0-9])/, /"([^"\n]{2,100}?)"/, /“([^”\n]{2,100}?)”/,
      /‘([^’\n]{2,100}?)’/, /「([^」\n]{2,100}?)」/, /『([^』\n]{2,100}?)』/
    ].freeze
    DOMAIN_TOKEN = %r{(?<![A-Za-z0-9@.-])((?:https?://)?[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,24})(?:/[^\s'"“”‘’「」『』]*)?}
    CJK = /[\p{Hangul}\p{Hiragana}\p{Katakana}\p{Han}]/
    LATIN_WORD = %r{[A-Za-z][A-Za-z0-9+#/&-]*(?:\.[A-Za-z0-9]+)*}
    STOPWORDS = %w[the a an and or of in on at to for with from by is are be me my us we you it this that].freeze

    def self.call(text)
      new(text).call
    end

    def initialize(text)
      @text = text.to_s
      @downcased = @text.downcase
    end

    def call
      country, candidates, evidence = detect_country
      domains = detect_domains
      quoted = quoted_segments

      Extraction.new(
        country: country,
        country_candidates: candidates,
        country_evidence: evidence,
        language: country && Lexicon::DEFAULT_LANGUAGE[country],
        target_domain: domains.one? ? domains.first : nil,
        domain_candidates: domains,
        query: single_query(quoted),
        query_candidates: query_candidates(quoted),
        compare_cue: cue?(Lexicon::COMPARE_CUES),
        only_new_cue: cue?(Lexicon::ONLY_NEW_CUES),
        masked_text: masked_text(quoted)
      )
    end

    private

    # The sentence with the user's keyword and domain replaced by neutral words. What the user
    # wants to DO is the intent; the topic of the keyword is not. Without this, 'react developer
    # jobs' inside a rank-check sentence pulled the classifier to job_search.
    def masked_text(quoted)
      masked = @text.gsub(DOMAIN_TOKEN) { |token| accepted_domain(token) ? "DOMAIN" : token }
      quoted.each { |phrase| masked = masked.gsub(phrase, "KEYWORD") }
      masked
    end

    def cue?(patterns)
      patterns.any? { |pattern| pattern.match?(@text) }
    end

    # Country names win; cities are only used when no country is named. Longer names are
    # claimed first so "indonesia" is not read as "india"'s Korean name inside it.
    def detect_country
      found = match_table(Lexicon::COUNTRIES)
      found = match_table(Lexicon::CITIES) if found.empty?
      codes = found.map(&:first).uniq
      return [ nil, [], nil ] if codes.empty?
      return [ nil, codes, nil ] if codes.size > 1
      return [ nil, codes, found.first.last ] unless Keyword::COUNTRIES.include?(codes.first)

      [ codes.first, codes, found.first.last ]
    end

    # Returns [[code, matched_text], ...] for non-overlapping matches, longest alias first.
    def match_table(table)
      entries = table.flat_map { |code, names| names.map { |name| [ code, name, regexp_for(name) ] } }
      entries.sort_by! { |_, name, _| -(name.is_a?(Regexp) ? name.source.length : name.length) }

      claimed = []
      found = []
      entries.each do |code, _name, regexp|
        @downcased.scan(regexp) do
          span = Regexp.last_match.offset(0)
          next if claimed.any? { |taken| span[0] < taken[1] && taken[0] < span[1] }

          claimed << span
          found << [ code, @downcased[span[0]...span[1]] ]
        end
      end
      found
    end

    # Names with Latin letters must match as whole words ("uk" must not match inside "duke");
    # Hangul, Kana, and Han names match as substrings because particles attach directly to them.
    def regexp_for(name)
      return name if name.is_a?(Regexp)

      escaped = Regexp.escape(name)
      return Regexp.new(escaped) unless name.match?(/\p{Latin}/)

      Regexp.new("(?<![\\p{L}\\p{N}])#{escaped}(?![\\p{L}\\p{N}])")
    end

    def detect_domains
      @text.scan(DOMAIN_TOKEN).flatten.filter_map { |token| accepted_domain(token) }.uniq
    end

    # A token counts as a domain when it normalizes to a valid hostname and either has a scheme
    # or www., or ends in a common TLD. "Node.js" and "e.g" are therefore not domains.
    def accepted_domain(token)
      domain = DomainNormalizer.call(token)
      return nil if domain.nil?
      return domain if token.match?(%r{\A(https?://|www\.)}i) || Lexicon::COMMON_TLDS.include?(domain.split(".").last)

      nil
    end

    def quoted_segments
      QUOTE_PAIRS.flat_map { |pattern| @text.scan(pattern).flatten }.map(&:squish).reject(&:empty?).uniq
    end

    # A quoted phrase is the query only when there is exactly one and it is not a domain.
    def single_query(quoted)
      phrases = quoted.reject { |phrase| DomainNormalizer.call(phrase) }
      return phrases.first if phrases.one?
      return nil unless phrases.empty?

      runs = latin_runs
      runs.one? && @text.match?(CJK) ? runs.first : nil
    end

    # Suggestions the user can pick from; none is applied automatically. Only phrases the rules
    # are fairly sure are a keyword: quoted text, or a Latin phrase inside a sentence in another
    # script. A cleaned-up copy of the whole sentence is not offered: it is rarely a good keyword.
    def query_candidates(quoted)
      candidates = quoted.reject { |phrase| DomainNormalizer.call(phrase) }
      candidates += latin_runs if @text.match?(CJK)
      candidates.map { |candidate| candidate.first(Keyword::QUERY_MAX_LENGTH) }.reject(&:blank?).uniq.first(3)
    end

    # Runs of Latin words inside a sentence written mostly in another script, e.g. the
    # "Senior React Developer" in a Korean sentence. A run needs a word of 3+ letters.
    def latin_runs
      text = @text.gsub(DOMAIN_TOKEN) { |token| accepted_domain(token) ? " " : token }
      text.scan(/#{LATIN_WORD}(?: #{LATIN_WORD})*/).map(&:squish).select do |run|
        words = run.split
        words.any? { |word| word.length >= 3 && STOPWORDS.exclude?(word.downcase) }
      end.uniq
    end
  end
end
