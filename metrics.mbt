///|
/// Aggregated attachment scores of a predicted parse against a gold parse.
pub struct EvalResult {
  mut sentence_pairs : Int32
  mut skipped_sentences : Int32
  mut gold_tokens : Int32
  mut aligned_tokens : Int32
  mut uas_correct : Int32
  mut las_correct : Int32
}

///|
/// Unlabelled attachment score in percent.
pub fn EvalResult::uas(self : EvalResult) -> Double {
  if self.aligned_tokens == 0 {
    return 0.0
  }
  self.uas_correct.to_double() / self.aligned_tokens.to_double() * 100.0
}

///|
/// Labelled attachment score in percent.
pub fn EvalResult::las(self : EvalResult) -> Double {
  if self.aligned_tokens == 0 {
    return 0.0
  }
  self.las_correct.to_double() / self.aligned_tokens.to_double() * 100.0
}

///|
/// Compares two parses sentence by sentence. Sentences whose word counts
/// differ cannot be aligned token by token and are counted as skipped instead
/// of silently scored.
pub fn evaluate(gold : Array[Sentence], pred : Array[Sentence]) -> EvalResult {
  let r : EvalResult = {
    sentence_pairs: 0,
    skipped_sentences: 0,
    gold_tokens: 0,
    aligned_tokens: 0,
    uas_correct: 0,
    las_correct: 0,
  }
  let mut i = 0
  let common = if gold.length() < pred.length() {
    gold.length()
  } else {
    pred.length()
  }
  while i < common {
    let g = gold.at(i)
    let p = pred.at(i)
    i = i + 1
    let gw = g.words()
    let pw = p.words()
    r.gold_tokens = r.gold_tokens + gw.length()
    r.sentence_pairs = r.sentence_pairs + 1
    if gw.length() != pw.length() {
      r.skipped_sentences = r.skipped_sentences + 1
      continue
    }
    let mut j = 0
    while j < gw.length() {
      let gtok = gw.at(j)
      let ptok = pw.at(j)
      j = j + 1
      if gtok.start != ptok.start {
        continue
      }
      r.aligned_tokens = r.aligned_tokens + 1
      let gh = gtok.head()
      let ph = ptok.head()
      if gh == ph {
        r.uas_correct = r.uas_correct + 1
        if gtok.deprel == ptok.deprel {
          r.las_correct = r.las_correct + 1
        }
      }
    }
  }
  if gold.length() > pred.length() {
    r.skipped_sentences = r.skipped_sentences + (gold.length() - pred.length())
  } else if pred.length() > gold.length() {
    r.skipped_sentences = r.skipped_sentences + (pred.length() - gold.length())
  }
  r
}

///|
/// One-line summary of the evaluation, as printed by the CLI.
pub fn EvalResult::to_string(self : EvalResult) -> String {
  let uas = (self.uas() * 100.0).to_int().to_double() / 100.0
  let las = (self.las() * 100.0).to_int().to_double() / 100.0
  "sentences=\{self.sentence_pairs} tokens=\{self.aligned_tokens} skipped=\{self.skipped_sentences} UAS=\{uas}% LAS=\{las}%"
}

///|
/// Corpus-level statistics of a CoNLL-U document.
pub struct Stats {
  mut sentences : Int32
  mut words : Int32
  mut multiwords : Int32
  mut empty_nodes : Int32
  mut comments : Int32
  mut max_length : Int32
  treebanks : Array[String]
}

///|
pub fn stats(sentences : Array[Sentence]) -> Stats {
  let s : Stats = {
    sentences: 0,
    words: 0,
    multiwords: 0,
    empty_nodes: 0,
    comments: 0,
    max_length: 0,
    treebanks: [],
  }
  for sentence in sentences {
    s.sentences = s.sentences + 1
    s.comments = s.comments + sentence.comments().length()
    let len = sentence.word_count()
    s.words = s.words + len
    if len > s.max_length {
      s.max_length = len
    }
    for row in sentence.rows() {
      if row.kind is Multiword {
        s.multiwords = s.multiwords + 1
      }
      if row.kind is Empty {
        s.empty_nodes = s.empty_nodes + 1
      }
    }
    match sentence.comment("# newdoc id = ") {
      Some(line) =>
        match line.split_once("= ") {
          Some((_, v)) => {
            let id = v.to_owned()
            if !id.is_empty() {
              s.treebanks.push(id)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  s
}

///|
pub fn Stats::average_length(self : Stats) -> Double {
  if self.sentences == 0 {
    return 0.0
  }
  self.words.to_double() / self.sentences.to_double()
}

///|
pub fn Stats::to_string(self : Stats) -> String {
  let avg = (self.average_length() * 100.0).to_int().to_double() / 100.0
  "sentences=\{self.sentences} words=\{self.words} multiword=\{self.multiwords} empty=\{self.empty_nodes} comments=\{self.comments} max_len=\{self.max_length} avg_len=\{avg} docs=\{self.treebanks.length()}"
}
