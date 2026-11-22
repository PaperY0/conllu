///|
/// Value of a sentence comment written as `# <key> = <value>`, the form used by
/// `# newdoc id = ...` and `# newpar id = ...`. Returns `None` when the sentence
/// carries no such comment.
pub fn Sentence::comment_value(self : Sentence, key : StringView) -> String? {
  let prefix = "# " + key.to_owned() + " = "
  for c in self.comments {
    match c.strip_prefix(prefix) {
      Some(value) => return Some(value.to_owned())
      None => ()
    }
  }
  None
}

///|
/// True when the sentence opens a new document (`# newdoc`).
pub fn Sentence::has_newdoc(self : Sentence) -> Bool {
  for c in self.comments {
    if c.has_prefix("# newdoc") {
      return true
    }
  }
  false
}

///|
/// True when the sentence opens a new paragraph (`# newpar`).
pub fn Sentence::has_newpar(self : Sentence) -> Bool {
  for c in self.comments {
    if c.has_prefix("# newpar") {
      return true
    }
  }
  false
}

///|
/// The document id of a `# newdoc id = ...` line, if any.
pub fn Sentence::newdoc_id(self : Sentence) -> String? {
  self.comment_value("newdoc id")
}

///|
/// The paragraph id of a `# newpar id = ...` line, if any.
pub fn Sentence::newpar_id(self : Sentence) -> String? {
  self.comment_value("newpar id")
}

///|
/// A run of sentences inside one paragraph. `id` is the `# newpar id` value, or
/// the empty string when the corpus does not name paragraphs.
pub struct Paragraph {
  id : String
  sentences : Array[Sentence]
}

///|
pub fn Paragraph::id(self : Paragraph) -> String {
  self.id
}

///|
pub fn Paragraph::sentences(self : Paragraph) -> Array[Sentence] {
  self.sentences
}

///|
pub fn Paragraph::sentence_count(self : Paragraph) -> Int32 {
  self.sentences.length()
}

///|
/// A document (`# newdoc`) split into the paragraphs it contains. Sentences that
/// appear before the first `# newdoc` line form one document with an empty id,
/// which is what a file without document boundaries looks like.
pub struct Document {
  id : String
  paragraphs : Array[Paragraph]
}

///|
pub fn Document::id(self : Document) -> String {
  self.id
}

///|
pub fn Document::paragraphs(self : Document) -> Array[Paragraph] {
  self.paragraphs
}

///|
pub fn Document::paragraph_count(self : Document) -> Int32 {
  self.paragraphs.length()
}

///|
pub fn Document::sentence_count(self : Document) -> Int32 {
  let mut n = 0
  for p in self.paragraphs {
    n = n + p.sentences.length()
  }
  n
}

///|
/// All sentences of the document, in file order.
pub fn Document::sentences(self : Document) -> Array[Sentence] {
  let out : Array[Sentence] = []
  for p in self.paragraphs {
    for s in p.sentences {
      out.push(s)
    }
  }
  out
}

///|
/// Serialises the document with the canonical writer, one blank line between
/// sentences. The `# newdoc` / `# newpar` lines travel as ordinary comments, so
/// the grouping survives a write.
pub fn Document::to_string(self : Document) -> String {
  let sb = StringBuilder::StringBuilder()
  for p in self.paragraphs {
    for s in p.sentences {
      sb.write_string(s.to_string())
      sb.write_string("\n")
    }
  }
  sb.to_string()
}

///|
/// Groups sentences by `# newdoc` and then by `# newpar`, in file order. A
/// `# newdoc` line always starts a new paragraph as well, so a document never
/// inherits the tail of the previous one.
pub fn documents(sentences : Array[Sentence]) -> Array[Document] {
  let docs : Array[Document] = []
  let mut doc_id = ""
  let mut pars : Array[Paragraph] = []
  let mut par_id = ""
  let mut par_rows : Array[Sentence] = []
  let mut open = false
  for sentence in sentences {
    if sentence.has_newdoc() || !open {
      if open {
        if par_rows.length() > 0 {
          pars.push({ id: par_id, sentences: par_rows })
        }
        docs.push({ id: doc_id, paragraphs: pars })
      }
      open = true
      doc_id = match sentence.comment_value("newdoc id") {
        Some(value) => value
        None => ""
      }
      pars = []
      par_id = ""
      par_rows = []
    }
    // A `# newdoc` line that also carries `# newpar id` opens the first
    // paragraph of the new document, so the two checks are not exclusive.
    if sentence.has_newpar() {
      if par_rows.length() > 0 {
        pars.push({ id: par_id, sentences: par_rows })
        par_rows = []
      }
      par_id = match sentence.comment_value("newpar id") {
        Some(value) => value
        None => ""
      }
    }
    par_rows.push(sentence)
  }
  if open {
    if par_rows.length() > 0 {
      pars.push({ id: par_id, sentences: par_rows })
    }
    docs.push({ id: doc_id, paragraphs: pars })
  }
  docs
}
