///|
/// What a corpus actually covers: which universal tags and relations appear,
/// which tags it uses that the UD spec does not define, how well-formed its
/// trees are, and the shape of its sentences. Answers the questions a corpus
/// maintainer asks before trusting a treebank.
pub struct Coverage {
  mut sentences : Int32
  mut words : Int32
  upos_used : Array[String]
  mut upos_missing : Array[String]
  deprel_used : Array[String]
  mut deprel_missing : Array[String]
  unknown_upos : Array[String]
  unknown_deprel : Array[String]
  /// Word rows whose UPOS is `_`, i.e. tokens left without a tag.
  mut untagged : Int32
  mut projective : Int32
  mut non_projective : Int32
  mut single_rooted : Int32
  mut multi_rooted : Int32
  mut max_depth : Int32
  mut avg_depth : Double
  /// Sum of every word's tree depth, kept so merged reports can recompute an
  /// average weighted by tokens instead of averaging averages.
  mut depth_total : Int32
  /// Sentences with more than 50 words; long inputs are where parsers and
  /// memory budgets break first.
  mut long_sentences : Int32
  mut empty_nodes : Int32
  mut multiword_tokens : Int32
  mut documents : Int32
  mut paragraphs : Int32
}

///|
fn join(items : Array[String], separator : String) -> String {
  if items.length() == 0 {
    return "none"
  }
  let mut out = ""
  let mut i = 0
  while i < items.length() {
    if i > 0 {
      out = out + separator
    }
    out = out + items.at(i)
    i = i + 1
  }
  out
}

///|
fn push_unique(items : Array[String], value : String) -> Unit {
  if !items.contains(value) {
    items.push(value)
  }
}

///|
fn missing_from(spec : Array[String], used : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for tag in spec {
    if !used.contains(tag) {
      out.push(tag)
    }
  }
  out
}

///|
/// Measures one corpus.
pub fn coverage(sentences : Array[Sentence]) -> Coverage {
  let upos_used : Array[String] = []
  let deprel_used : Array[String] = []
  let unknown_upos : Array[String] = []
  let unknown_deprel : Array[String] = []
  let cov : Coverage = {
    sentences: 0,
    words: 0,
    upos_used,
    upos_missing: [],
    deprel_used,
    deprel_missing: [],
    unknown_upos,
    unknown_deprel,
    untagged: 0,
    projective: 0,
    non_projective: 0,
    single_rooted: 0,
    multi_rooted: 0,
    max_depth: 0,
    avg_depth: 0.0,
    depth_total: 0,
    long_sentences: 0,
    empty_nodes: 0,
    multiword_tokens: 0,
    documents: 0,
    paragraphs: 0,
  }
  let mut depth_sum : Int32 = 0
  for sentence in sentences {
    cov.sentences = cov.sentences + 1
    let words = sentence.words()
    let count = words.length()
    cov.words = cov.words + count
    if count > 50 {
      cov.long_sentences = cov.long_sentences + 1
    }
    if is_projective(sentence) {
      cov.projective = cov.projective + 1
    } else {
      cov.non_projective = cov.non_projective + 1
    }
    if is_single_rooted(sentence) {
      cov.single_rooted = cov.single_rooted + 1
    } else {
      cov.multi_rooted = cov.multi_rooted + 1
    }
    let d = max_depth(sentence)
    if d > cov.max_depth {
      cov.max_depth = d
    }
    for row in sentence.rows() {
      if row.kind is Multiword {
        cov.multiword_tokens = cov.multiword_tokens + 1
      }
      if row.kind is Empty {
        cov.empty_nodes = cov.empty_nodes + 1
      }
    }
    for row in words {
      let tag = row.upos
      if tag == "_" || tag.is_empty() {
        cov.untagged = cov.untagged + 1
      } else if is_known_upos(tag) {
        push_unique(cov.upos_used, tag)
      } else {
        push_unique(cov.unknown_upos, tag)
      }
      let rel = row.deprel
      if rel == "_" || rel.is_empty() {
        // Enhanced-only rows and empty nodes may leave the basic relation
        // empty; that is a different problem from an unknown label.
        continue
      }
      let base = base_deprel(rel)
      if is_known_deprel(base) {
        push_unique(cov.deprel_used, base)
      } else {
        push_unique(cov.unknown_deprel, base)
      }
    }
    let mut k = 0
    while k < count {
      depth_sum = depth_sum + depth(sentence, words.at(k).start)
      k = k + 1
    }
  }
  cov.avg_depth = if cov.words == 0 {
    0.0
  } else {
    depth_sum.to_double() / cov.words.to_double()
  }
  cov.depth_total = depth_sum
  cov.upos_used.sort_by(String::compare)
  cov.deprel_used.sort_by(String::compare)
  cov.unknown_upos.sort_by(String::compare)
  cov.unknown_deprel.sort_by(String::compare)
  cov.upos_missing = missing_from(upos_tags, cov.upos_used)
  cov.deprel_missing = missing_from(deprel_tags, cov.deprel_used)
  let docs = documents(sentences)
  cov.documents = docs.length()
  let mut pars = 0
  for doc in docs {
    pars = pars + doc.paragraph_count()
  }
  cov.paragraphs = pars
  cov
}

///|
fn is_known_upos(tag : String) -> Bool {
  upos_tags.contains(tag)
}

///|
fn is_known_deprel(base : String) -> Bool {
  deprel_tags.contains(base)
}

///|
fn merge_into(target : Array[String], source : Array[String]) -> Unit {
  for item in source {
    push_unique(target, item)
  }
}

///|
/// Combines per-file coverages into one corpus-wide view: counters add up,
/// used labels are unioned, missing labels are recomputed against the spec, and
/// the average depth is rebuilt from the token-weighted depth total so a merged
/// report does not average averages.
pub fn merge_coverage(items : Array[Coverage]) -> Coverage {
  let merged : Coverage = {
    sentences: 0,
    words: 0,
    upos_used: [],
    upos_missing: [],
    deprel_used: [],
    deprel_missing: [],
    unknown_upos: [],
    unknown_deprel: [],
    untagged: 0,
    projective: 0,
    non_projective: 0,
    single_rooted: 0,
    multi_rooted: 0,
    max_depth: 0,
    avg_depth: 0.0,
    depth_total: 0,
    long_sentences: 0,
    empty_nodes: 0,
    multiword_tokens: 0,
    documents: 0,
    paragraphs: 0,
  }
  for item in items {
    merged.sentences = merged.sentences + item.sentences
    merged.words = merged.words + item.words
    merged.untagged = merged.untagged + item.untagged
    merged.projective = merged.projective + item.projective
    merged.non_projective = merged.non_projective + item.non_projective
    merged.single_rooted = merged.single_rooted + item.single_rooted
    merged.multi_rooted = merged.multi_rooted + item.multi_rooted
    merged.long_sentences = merged.long_sentences + item.long_sentences
    merged.empty_nodes = merged.empty_nodes + item.empty_nodes
    merged.multiword_tokens = merged.multiword_tokens + item.multiword_tokens
    merged.documents = merged.documents + item.documents
    merged.paragraphs = merged.paragraphs + item.paragraphs
    merged.depth_total = merged.depth_total + item.depth_total
    if item.max_depth > merged.max_depth {
      merged.max_depth = item.max_depth
    }
    merge_into(merged.upos_used, item.upos_used)
    merge_into(merged.deprel_used, item.deprel_used)
    merge_into(merged.unknown_upos, item.unknown_upos)
    merge_into(merged.unknown_deprel, item.unknown_deprel)
  }
  merged.upos_used.sort_by(String::compare)
  merged.deprel_used.sort_by(String::compare)
  merged.unknown_upos.sort_by(String::compare)
  merged.unknown_deprel.sort_by(String::compare)
  merged.upos_missing = missing_from(upos_tags, merged.upos_used)
  merged.deprel_missing = missing_from(deprel_tags, merged.deprel_used)
  merged.avg_depth = if merged.words == 0 {
    0.0
  } else {
    merged.depth_total.to_double() / merged.words.to_double()
  }
  merged
}

///|
/// Share of sentences whose tree is projective, in percent.
pub fn Coverage::projectivity(self : Coverage) -> Double {
  if self.sentences == 0 {
    return 0.0
  }
  self.projective.to_double() / self.sentences.to_double() * 100.0
}

///|
/// True when every universal tag and relation of the spec appears at least
/// once. A `false` here is not a defect, but it does tell you the corpus will
/// not exercise those labels in a parser evaluation.
pub fn Coverage::full_upos(self : Coverage) -> Bool {
  self.upos_missing.length() == 0
}

///|
/// Same for the 37 universal relations.
pub fn Coverage::full_deprel(self : Coverage) -> Bool {
  self.deprel_missing.length() == 0
}

///|
fn percent(value : Double) -> String {
  let rounded = (value * 100.0).to_int().to_double() / 100.0
  rounded.to_string()
}

///|
/// Human-readable report, one section per dimension. Printed by
/// `conllu analyze`.
pub fn Coverage::to_string(self : Coverage) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string(
    "sentences=\{self.sentences} words=\{self.words} documents=\{self.documents} paragraphs=\{self.paragraphs}",
  )
  sb.write_string("\n")
  sb.write_string(
    "upos: \{self.upos_used.length()}/\{upos_tags.length()} used, missing: \{join(self.upos_missing, ",")}",
  )
  sb.write_string("\n")
  sb.write_string(
    "deprel: \{self.deprel_used.length()}/\{deprel_tags.length()} used, missing: \{join(self.deprel_missing, ",")}",
  )
  sb.write_string("\n")
  sb.write_string(
    "unknown: upos=\{join(self.unknown_upos, ",")} deprel=\{join(self.unknown_deprel, ",")} untagged=\{self.untagged}",
  )
  sb.write_string("\n")
  sb.write_string(
    "trees: projective=\{percent(self.projectivity())}% non_projective=\{self.non_projective} single_rooted=\{self.single_rooted} multi_rooted=\{self.multi_rooted} max_depth=\{self.max_depth} avg_depth=\{percent(self.avg_depth)}",
  )
  sb.write_string("\n")
  sb.write_string(
    "surface: multiword=\{self.multiword_tokens} empty_nodes=\{self.empty_nodes} long_sentences(>50w)=\{self.long_sentences}",
  )
  sb.to_string()
}
