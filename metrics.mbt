///|
/// Aggregated attachment scores of a predicted parse against a gold parse.
pub struct EvalResult {
  mut sentence_pairs : Int32
  mut skipped_sentences : Int32
  mut gold_tokens : Int32
  mut aligned_tokens : Int32
  mut uas_correct : Int32
  mut uuas_correct : Int32
  mut las_correct : Int32
}

///|
/// Undirected attachment score in percent: a token counts as correct when it
/// points at the same head as the gold parse, ignoring the direction of the
/// dependency. Useful when a parser gets the attachment right but the direction
/// or the label wrong.
pub fn EvalResult::uuas(self : EvalResult) -> Double {
  if self.aligned_tokens == 0 {
    return 0.0
  }
  self.uuas_correct.to_double() / self.aligned_tokens.to_double() * 100.0
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
    uuas_correct: 0,
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
      if undirected_match(gw, gtok.start, gh, ph) {
        r.uuas_correct = r.uuas_correct + 1
      }
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
/// True when the gold edge and the predicted edge connect the same pair of
/// words, in either direction. A parser that attaches `a` to `b` while gold has
/// `b` attached to `a` still found the right pair, just picked the wrong side.
fn undirected_match(
  gold_words : Array[Token],
  id : Int32,
  gold_head : Int32?,
  pred_head : Int32?,
) -> Bool {
  if gold_head == pred_head {
    return true
  }
  match pred_head {
    Some(p) =>
      if p == 0 || p == id || p > gold_words.length() {
        false
      } else {
        gold_words.at(p - 1).head() == Some(id)
      }
    None => false
  }
}

///|
/// Labelled accuracy of one dependency relation.
pub struct LabelScore {
  label : String
  gold : Int32
  correct : Int32
}

///|
/// Labelled accuracy of this relation in percent.
pub fn LabelScore::las(self : LabelScore) -> Double {
  if self.gold == 0 {
    return 0.0
  }
  self.correct.to_double() / self.gold.to_double() * 100.0
}

///|
/// One-line summary: `label=nsubj gold=210 correct=198 las=94.29%`.
pub fn LabelScore::to_string(self : LabelScore) -> String {
  let las = (self.las() * 100.0).to_int().to_double() / 100.0
  "label=\{self.label} gold=\{self.gold} correct=\{self.correct} las=\{las}%"
}

///|
fn label_index(labels : Array[String], label : String) -> Int32 {
  let mut i = 0
  while i < labels.length() {
    if labels.at(i) == label {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Labelled accuracy broken down by the gold relation, worst first, so a parser
/// can see which relations it confuses instead of a single aggregate number.
pub fn evaluate_by_label(
  gold : Array[Sentence],
  pred : Array[Sentence],
) -> Array[LabelScore] {
  let labels : Array[String] = []
  let counts : Array[Int32] = []
  let correct : Array[Int32] = []
  let mut i = 0
  let common = if gold.length() < pred.length() {
    gold.length()
  } else {
    pred.length()
  }
  while i < common {
    let gw = gold.at(i).words()
    let pw = pred.at(i).words()
    i = i + 1
    if gw.length() != pw.length() {
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
      let mut idx = label_index(labels, gtok.deprel)
      if idx < 0 {
        labels.push(gtok.deprel)
        counts.push(0)
        correct.push(0)
        idx = labels.length() - 1
      }
      counts[idx] = counts[idx] + 1
      if gtok.head() == ptok.head() && gtok.deprel == ptok.deprel {
        correct[idx] = correct[idx] + 1
      }
    }
  }
  let out : Array[LabelScore] = []
  let mut k = 0
  while k < labels.length() {
    out.push({
      label: labels.at(k),
      gold: counts.at(k),
      correct: correct.at(k),
    })
    k = k + 1
  }
  out.sort_by(fn(a, b) {
    let ea = a.gold - a.correct
    let eb = b.gold - b.correct
    if ea != eb {
      eb - ea
    } else {
      compare_labels(a.label, b.label)
    }
  })
  out
}

///|
/// Scores of one document: the aggregate `EvalResult` of its sentences, keyed by
/// the `# newdoc id` of the gold file. A parser can be 90% LAS overall and still
/// lose entire documents, which is what this view exposes.
pub struct DocumentScore {
  id : String
  result : EvalResult
}

///|
pub fn DocumentScore::id(self : DocumentScore) -> String {
  self.id
}

///|
pub fn DocumentScore::sentences(self : DocumentScore) -> Int32 {
  self.result.sentence_pairs
}

///|
pub fn DocumentScore::tokens(self : DocumentScore) -> Int32 {
  self.result.aligned_tokens
}

///|
pub fn DocumentScore::uas(self : DocumentScore) -> Double {
  self.result.uas()
}

///|
pub fn DocumentScore::las(self : DocumentScore) -> Double {
  self.result.las()
}

///|
pub fn DocumentScore::to_string(self : DocumentScore) -> String {
  "doc id=\{self.id} sentences=\{self.sentences()} tokens=\{self.tokens()} UAS=\{self.uas()}% LAS=\{self.las()}%"
}

///|
/// Evaluates document by document instead of sentence by sentence. Documents
/// come from `# newdoc` in the gold file; predictions are matched by position,
/// so a prediction that merged or dropped a document shows up as a document
/// with skipped sentences rather than as a silently reshuffled score.
/// Documents are returned worst-first by LAS.
pub fn evaluate_by_document(
  gold : Array[Sentence],
  pred : Array[Sentence],
) -> Array[DocumentScore] {
  let gold_docs = documents(gold)
  let pred_docs = documents(pred)
  let out : Array[DocumentScore] = []
  let mut i = 0
  while i < gold_docs.length() {
    let gold_sentences = gold_docs.at(i).sentences()
    let pred_sentences = if i < pred_docs.length() {
      pred_docs.at(i).sentences()
    } else {
      let none : Array[Sentence] = []
      none
    }
    out.push({
      id: gold_docs.at(i).id(),
      result: evaluate(gold_sentences, pred_sentences),
    })
    i = i + 1
  }
  out.sort_by(fn(a, b) {
    let la = a.result.las()
    let lb = b.result.las()
    if la != lb {
      (la - lb).to_int()
    } else {
      compare_labels(a.id, b.id)
    }
  })
  out
}

///|
/// One-line summary of the evaluation, as printed by the CLI.
pub fn EvalResult::to_string(self : EvalResult) -> String {
  let uas = (self.uas() * 100.0).to_int().to_double() / 100.0
  let uuas = (self.uuas() * 100.0).to_int().to_double() / 100.0
  let las = (self.las() * 100.0).to_int().to_double() / 100.0
  "sentences=\{self.sentence_pairs} tokens=\{self.aligned_tokens} skipped=\{self.skipped_sentences} UAS=\{uas}% UUAS=\{uuas}% LAS=\{las}%"
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

///|
/// Same numbers as `Stats::to_string`, as one JSON object, so a wrapper in
/// another language does not have to parse the sentence-level summary.
pub fn Stats::to_json(self : Stats) -> String {
  let avg = (self.average_length() * 100.0).to_int().to_double() / 100.0
  let sb = StringBuilder::StringBuilder()
  sb.write_string("{\"sentences\":")
  sb.write_string(self.sentences.to_string())
  sb.write_string(",\"words\":")
  sb.write_string(self.words.to_string())
  sb.write_string(",\"multiword\":")
  sb.write_string(self.multiwords.to_string())
  sb.write_string(",\"empty_nodes\":")
  sb.write_string(self.empty_nodes.to_string())
  sb.write_string(",\"comments\":")
  sb.write_string(self.comments.to_string())
  sb.write_string(",\"max_length\":")
  sb.write_string(self.max_length.to_string())
  sb.write_string(",\"avg_length\":")
  sb.write_string(avg.to_string())
  sb.write_string(",\"treebanks\":")
  sb.write_string(json_str_array(self.treebanks))
  sb.write_string("}")
  sb.to_string()
}
